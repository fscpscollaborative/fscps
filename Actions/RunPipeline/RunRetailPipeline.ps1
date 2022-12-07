Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "DynamicsVersion", Mandatory = $false)]
    [string] $DynamicsVersion,
    [Parameter(HelpMessage = "Environment name o deploy", Mandatory = $false)]
    [string] $EnvironmentName,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = ''
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)
    $LastExitCode = 0
    #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    OutputInfo "======================================== Use settings and secrets"

    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable | ConvertTo-OrderedDictionary
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $settingsHash = $settings #| ConvertTo-HashTable
    $settings.secretsList | ForEach-Object {
        $setValue = ""
        if($settingsHash.Contains($_))
        {
            $setValue = $settingsHash."$_"
        }
        if ($secrets.ContainsKey($setValue)) 
        {
            OutputInfo "Found $($_) variable in the settings file with value: ($setValue)"
            $value = $secrets."$setValue"
        }
        else {
            $value = ""
        }
        Set-Variable -Name $_ -Value $value
    }

    if($DynamicsVersion -eq "")
    {
        $DynamicsVersion = $settings.buildVersion
    }

    $version = Get-VersionData -sdkVersion $DynamicsVersion

    if($settings.sourceBranch -eq "")
    {
        $settings.sourceBranch = $settings.currentBranch
    }
    $settings
    $version

    #check nuget instalation
    installModules @("AZ","Azure.Storage","d365fo.tools")
    #SourceBranchToPascakCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    $PlatformVersion = $version.PlatformVersion
    $ApplicationVersion = $version.AppVersion

    $baseFolder = $ENV:GITHUB_WORKSPACE
    $workflowName = $env:GITHUB_WORKFLOW
    $sdkPath = ($settings.retailSDKZipPath)
    
    $buildPath = $settings.retailSDKBuildPath
    Write-Output "::endgroup::"

    Write-Output "::group::Cleanup folder"
    OutputInfo "======================================== Cleanup folders"
    #Cleanup Build folder
    Remove-Item $buildPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $sdkPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "::endgroup::"

    Write-Output "::group::Update RetailSDK"
    OutputInfo "======================================== Update RetailSDK"
    $sdkzipPath = Update-RetailSDK -sdkVersion $DynamicsVersion -sdkPath $sdkPath
    OutputInfo "SDK is located at $sdkzipPath"
    Expand-7zipArchive -Path $sdkzipPath -DestinationPath $buildPath
    OutputInfo "SDK archive was expanded to $buildPath"

    Remove-Item $buildPath\SampleExtensions -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "::endgroup::"

    Write-Output "::group::Copy branch files"
    OutputInfo "======================================== Copy branch files"
    #Copy branch files
    New-Item -ItemType Directory -Force -Path $buildPath; Copy-Item $ENV:GITHUB_WORKSPACE\* -Destination $buildPath -Recurse -Force
    Write-Output "::endgroup::"

    Write-Output "::group::Cleanup NuGet"
    OutputInfo "======================================== Cleanup NuGet"
    #Cleanup NuGet
    nuget sources remove -Name $settings.nugetFeedName -Source $settings.nugetSourcePath
    Write-Output "::endgroup::"

    Write-Output "::group::Nuget add source"
    OutputInfo "======================================== Nuget add source"
    #Nuget add source
    $nugetUserName = if($settings.nugetFeedUserName){$settings.nugetFeedUserName}else{$nugetFeedUserSecretName}
    nuget sources Add -Name $settings.nugetFeedName -Source $settings.nugetSourcePath -username $nugetUserName -password $nugetFeedPasswordSecretName
   
    Write-Output "::endgroup::"

    #Write-Output "::group::Nuget install packages"
    #OutputInfo "======================================== Nuget install packages"

    #cd $buildPath

    #Nuget install packages
    #nuget restore dirs.proj -PackagesDirectory $settings.nugetPackagesPath
    #Write-Output "::endgroup::"


    Write-Output "::group::Build solution"
    #Build solution
    OutputInfo "======================================== Build solution"
    cd $buildPath

    installModules "Invoke-MsBuild"
    #& msbuild
    $msbuildpath = & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -products * -requires Microsoft.Component.MSBuild -property installationPath  -version "[15.9,16.11)"
    if($msbuildpath -ne "")
    {
        $msbuildexepath = Join-Path $msbuildpath "MSBuild\15.0\Bin\MSBuild.exe"
        $msbuildresult = Invoke-MsBuild -Path dirs.proj -MsBuildFilePath "$msbuildexepath" -ShowBuildOutputInCurrentWindow -BypassVisualStudioDeveloperCommandPrompt
    }
    else
    {
        $msbuildresult = Invoke-MsBuild -Path dirs.proj -ShowBuildOutputInCurrentWindow 
    }
    if ($msbuildresult.BuildSucceeded -eq $true)
    {
      Write-Output ("Build completed successfully in {0:N1} seconds." -f $msbuildresult.BuildDuration.TotalSeconds)
    }
    elseif ($msbuildresult.BuildSucceeded -eq $false)
    {
      Write-Error ("Build failed after {0:N1} seconds. Check the build log file '$($msbuildresult.BuildLogFilePath)' for errors." -f $msbuildresult.BuildDuration.TotalSeconds)
    }
    elseif ($null -eq $msbuildresult.BuildSucceeded)
    {
      Write-Error "Unsure if build passed or failed: $($msbuildresult.Message)"
    }

    Write-Output "::endgroup::"

     #GeneratePackages
    if($settings.generatePackages)
    {
        $artifactDirectory = (Join-Path $buildPath $($settings.artifactsPath))
        Write-Output "Artifacts directory: $artifactDirectory" 
        if (!(Test-Path -Path $artifactDirectory))
        {
            # The reason to use System.IO.Directory.CreateDirectory is it creates any directories missing in the whole path
            # whereas New-Item would only create the top level directory
            [System.IO.Directory]::CreateDirectory($artifactDirectory)
        }

        Write-Output "::group::Generate packages"
        OutputInfo "======================================== Generate packages"

        $packageNamePattern = $settings.packageNamePattern;
        $packageNamePattern = $packageNamePattern.Replace("BRANCHNAME", $($settings.sourceBranch))

        if($settings.deploy)
        {
            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME", $EnvironmentName)
        }
        else
        {
            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME", $settings.packageName)
        }

        $packageNamePattern = $packageNamePattern.Replace("FNSCMVERSION", $DynamicsVersion)
        $packageNamePattern = $packageNamePattern.Replace("DATE", (Get-Date -Format "yyyyMMdd").ToString())
        $packageNamePattern = $packageNamePattern.Replace("RUNNUMBER", $ENV:GITHUB_RUN_NUMBER)
        $packageName = $packageNamePattern + ".zip"

        $packagePath = Join-Path $buildPath "\Packages\RetailDeployablePackage\"
        Rename-Item -Path (Join-Path $packagePath "RetailDeployablePackage.zip") -NewName $packageName

        $packagePath = Join-Path $packagePath $packageName
        Copy-Item $packagePath -Destination $artifactDirectory -Force

        Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_NAME=$packageName"
        Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_NAME=$packageName"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_PATH=$packagePath"
        Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_PATH=$packagePath"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_PATH=$artifactDirectory"
        Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_PATH=$artifactDirectory"
        
        $artifacts = Get-ChildItem $artifactDirectory
        $artifactsList = $artifacts.FullName -join ","

        if($artifactsList.Contains(','))
        {
            $artifacts = $artifactsList.Split(',') | ConvertTo-Json -compress
        }
        else
        {
            $artifacts = '["'+$($artifactsList).ToString()+'"]'

        }

        Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_LIST=$artifacts"
        Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_LIST=$artifacts"

        Write-Output "::endgroup::"

        #Upload to LCS
        $assetId = ""
        if($settings.uploadPackageToLCS)
        {
            Write-Output "::group::Upload artifact to the LCS"
            OutputInfo "======================================== Upload artifact to the LCS"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Get-D365LcsApiToken -ClientId $settings.lcsClientId -Username "$lcsUsernameSecretname" -Password "$lcsPasswordSecretName" -LcsApiUri "https://lcsapi.lcs.dynamics.com" -Verbose | Set-D365LcsApiConfig -ProjectId $settings.lcsProjectId
            $assetId = Invoke-D365LcsUpload -FilePath "$packagePath" -FileType "SoftwareDeployablePackage" -Name "$packageNamePattern" -Verbose
            Write-Output "::endgroup::"

            #Deploy asset to the LCS Environment
            if($settings.deploy)
            {
                Write-Output "::group::Deploy asset to the LCS Environment"
                OutputInfo "======================================== Deploy asset to the LCS Environment"
                #Check environment status
                OutputInfo "======================================== Check $($EnvironmentName) status"

                $azurePassword = ConvertTo-SecureString $azClientsecretSecretname -AsPlainText -Force
                $psCred = New-Object System.Management.Automation.PSCredential($settings.azClientId , $azurePassword)

                OutputInfo "Check az cli installation..."
                if(-not(Test-Path -Path "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\"))
                {
                    OutputInfo "az cli installing.."
                    $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi
                    OutputInfo "az cli installed.."
                }

                Set-Alias -Name az -Value "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
                $AzureRMAccount = az login --service-principal -u $settings.azClientId -p "$azClientsecretSecretname" --tenant $settings.azTenantId

                $PowerState = ""
                if ($AzureRMAccount) { 
                    #Do Logic
                    OutputInfo "== Logged in == $($settings.azTenantId) "

                    OutputInfo "Getting Azure VM State $($settings.azVmname)"
                    $PowerState = ([string](az vm list -d --query "[?name=='$($settings.azVmname)'].powerState").Trim().Trim("[").Trim("]").Trim('"').Trim("VM ")).Replace(' ','')
                    OutputInfo "....state is $($PowerState)"
                }

                OutputInfo "Getting LCS State $($settings.azVmname)"
                $status = Get-D365LcsEnvironmentMetadata -EnvironmentId $settings.lcsEnvironmentId
                if($status.DeploymentState -eq "Servicing")
                {
                    do {
                        Start-Sleep -Seconds 60
                        $status = Get-D365LcsEnvironmentMetadata -EnvironmentId $settings.lcsEnvironmentId
                    
                        OutputInfo "Waiting of previous deployment finish. Current status: $($status.DeploymentState)"
                    }
                    while ($status.DeploymentState -eq "Servicing")
                    
                    OutputInfo "Previous deployment status: $($status.DeploymentState)"
                    Start-Sleep -Seconds 120
                }

                if($status.DeploymentState -eq "Failed")
                {
                    OutputError -message "Previous deployment status is failed. Please ckeck the deployment logs in LCS."
                }

                #Startup environment
                #if($PowerState -ne "running")
                #{
                    OutputInfo "======================================== Start $($EnvironmentName)"
                    Invoke-D365LcsEnvironmentStart -EnvironmentId $settings.lcsEnvironmentId
                    Start-Sleep -Seconds 60
                #}

                #Deploy asset to the LCS Environment
                OutputInfo "======================================== Deploy asset to the LCS Environment"
                $WaitForCompletion = $true
                $PSFObject = Invoke-D365LcsDeployment -AssetId "$($assetId.AssetId)" -EnvironmentId "$($settings.lcsEnvironmentId)" -UpdateName "$packageNamePattern"
                $errorCnt = 0
                do {
                    Start-Sleep -Seconds 60
                    $deploymentStatus = Get-D365LcsDeploymentStatus -ActivityId $PSFObject.ActivityId -EnvironmentId $settings.lcsEnvironmentId -FailOnErrorMessage -SleepInSeconds 5

                    if (($deploymentStatus.ErrorMessage))
                    {
                        $errorCnt++
                    }

                    if($errorCnt -eq 3)
                    {
                        if (($deploymentStatus.ErrorMessage) -or ($deploymentStatus.OperationStatus -eq "PreparationFailed")) {
                            $errorMessagePayload = "`r`n$($deploymentStatus | ConvertTo-Json)"
                            OutputError -message $errorMessagePayload
                        }
                    }
                    #if deployment is failed throw anyway
                    if(($deploymentStatus.OperationStatus -eq "Failed"))
                    {
                        $errorMessagePayload = "`r`n$($deploymentStatus | ConvertTo-Json)"
                        OutputError -message $errorMessagePayload
                    }
                    OutputInfo "Deployment status: $($deploymentStatus.OperationStatus)"
                }
                while ((($deploymentStatus.OperationStatus -eq "InProgress") -or ($deploymentStatus.OperationStatus -eq "NotStarted") -or ($deploymentStatus.OperationStatus -eq "PreparingEnvironment")) -and $WaitForCompletion)
                        
                if($PowerState -ne "running")
                {
                    OutputInfo "======================================== Stop $($EnvironmentName)"
                    Invoke-D365LcsEnvironmentStop -EnvironmentId $settings.lcsEnvironmentId
                }
                Write-Output "::endgroup::"
            }
        }
    }
}
catch {
    OutputError -message $_.Exception.Message
}
finally
{
    OutputInfo "Execution is done."
}

