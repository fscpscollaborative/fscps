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
    $helperPath = Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve
    . ($helperPath)
    $LastExitCode = 0
    #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    OutputInfo "======================================== Use settings and secrets"
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $workflowName = $env:GITHUB_WORKFLOW

    $github = (Get-ActionContext)
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
    installModules @("Az.Storage","d365fo.tools")
    #SourceBranchToPascakCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    $PlatformVersion = $version.PlatformVersion
    $ApplicationVersion = $version.AppVersion

    $sdkPath = ($settings.retailSDKZipPath)
    if (!(Test-Path -Path $sdkPath))
        {
            # The reason to use System.IO.Directory.CreateDirectory is it creates any directories missing in the whole path
            # whereas New-Item would only create the top level directory
            [System.IO.Directory]::CreateDirectory($sdkPath)
        }
    $buildPath = $settings.retailSDKBuildPath
    Write-Output "::endgroup::"

    Write-Output "::group::Cleanup folder"
    OutputInfo "======================================== Cleanup folders"
    #Cleanup Build folder
    Remove-Item $buildPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $sdkPath -Recurse -Force -ErrorAction SilentlyContinue
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
<#
    Write-Output "::group::Nuget install packages"
    OutputInfo "======================================== Nuget install packages"
    $packagesFilePath = Join-Path $buildPath packages.config
    if(Test-Path $packagesFilePath)
    {
        OutputInfo "Found packages.config file at path: $packagesFilePath "
        nuget restore $packagesFilePath
    }
    else
    {
        OutputInfo "Not Found packages.config file at path: $packagesFilePath "
        nuget restore $settings.solutionName
    }
    
    #Nuget install packages
    
    Write-Output "::endgroup::"
#>
    Write-Output "::group::Build solution"

    #Build solution
    OutputInfo "======================================== Build solution"
    Set-Location $buildPath
    Get-ChildItem $buildPath | Format-Table

    ### Prebuild
    $prebuildCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\PreBuild.ps1'
    if(Test-Path $prebuildCustomScript)
    {
        & $prebuildCustomScript -settings $settings -githubContext $github -helperPath $helperPath
    }
    ### Prebuild

    if($workflowName -eq "(RELEASE)")
    {
        if($($github.Payload.inputs.versionNumber) -ne "")
        {
            $versionNumber = $($github.Payload.inputs.versionNumber)
            $propsFile = Join-Path $ENV:GITHUB_WORKSPACE "repo.props"
            if ($versionNumber -match "^\d+\.\d+\.\d+\.\d+$")
            {
                $versions = $versionNumber.Split('.')
            }
            else
            {
                throw "Version Number '$versionNumber' is not of format #.#.#.#"
            }
            [xml]$xml = Get-Content $propsFile -Encoding UTF8
            
            $modelInfo = $xml.SelectNodes("/Project")
            if ($modelInfo.Count -eq 1)
            {
                $version = $xml.SelectNodes("/Project/PropertyGroup/MajorVersion")[0]
                $version.InnerText = "$($versions[0]).$($versions[1])"
            
                $version = $xml.SelectNodes("/Project/PropertyGroup/BuildNumber")[0]
                $version.InnerText = "$($versions[2]).$($versions[3])"
            
                $xml.Save($propsFile)
            }
            else
            {
                Write-Host "::Error: - File '$propsFile' is not a valid props file"
            }
        }
    }
    #dotnet build $settings.solutionName /property:Configuration=Debug /property:NuGetInteractive=true
    
    #& msbuild




    installModules "Invoke-MsBuild"
    $msbuildpath = & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -products * -requires Microsoft.Component.MSBuild -property installationPath -latest
    if($msbuildpath -ne "")
    {
        $msbuildexepath = Join-Path $msbuildpath "MSBuild\Current\Bin\MSBuild.exe"
        $msbuildresult = Invoke-MsBuild -Path $settings.solutionName -MsBuildParameters "/t:restore,rebuild /property:Configuration=Release /property:NuGetInteractive=true /property:BuildingInsideVisualStudio=false" -MsBuildFilePath "$msbuildexepath" -ShowBuildOutputInCurrentWindow -BypassVisualStudioDeveloperCommandPrompt
    }
    else
    {
        $msbuildresult = Invoke-MsBuild -Path $settings.solutionName -MsBuildParameters "/t:restore,rebuild /property:Configuration=Release /property:NuGetInteractive=true /property:BuildingInsideVisualStudio=false" -ShowBuildOutputInCurrentWindow 
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
    

    ### Postbuild
    $postbuildCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\PostBuild.ps1'
    if(Test-Path $postbuildCustomScript)
    {
        & $postbuildCustomScript -settings $settings -githubContext $github -helperPath $helperPath
    }
    ### Postbuild

    Write-Output "::endgroup::"

    #GeneratePackages
    if($settings.generatePackages)
    {
        Write-Output "::group::Generate packages"
        OutputInfo "======================================== Generate packages"
        $artifactDirectory = (Join-Path $buildPath $($settings.artifactsPath))
        OutputInfo "Artifacts directory: $artifactDirectory" 
        if (!(Test-Path -Path $artifactDirectory))
        {
            [System.IO.Directory]::CreateDirectory($artifactDirectory)
        }
 
        <#
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
        #>
        $packageNamePattern = $settings.packageNamePattern;
        if($settings.deploy)
        {
            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME", $EnvironmentName)
        }
        else
        {
            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME-", ""<#$settings.packageName#>)
        }
        $packageNamePattern = $packageNamePattern.Replace("BRANCHNAME", $($settings.sourceBranch))
        $packageNamePattern = $packageNamePattern.Replace("FNSCMVERSION", $DynamicsVersion)
        $packageNamePattern = $packageNamePattern.Replace("DATE", (Get-Date -Format "yyyyMMdd").ToString())
        $packageName = $packageNamePattern.Replace("RUNNUMBER", $ENV:GITHUB_RUN_NUMBER)
        
        Set-Location $buildPath

        [System.IO.DirectoryInfo]$csuZipPackagePath = Get-ChildItem -Recurse | Where-Object {$_.FullName -match "bin.*.Release.*ScaleUnit.*.zip$"} | ForEach-Object {$_.FullName}
        [System.IO.DirectoryInfo]$hWSInstallerPath = Get-ChildItem -Recurse | Where-Object {$_.FullName -match "bin.*.Release.*HardwareStation.*.exe$"} | ForEach-Object {$_.FullName}
        [System.IO.DirectoryInfo]$sCInstallerPath = Get-ChildItem -Recurse | Where-Object {$_.FullName -match "bin.*.Release.*StoreCommerce.*.exe$"} | ForEach-Object {$_.FullName}
        [System.IO.DirectoryInfo]$sUInstallerPath = Get-ChildItem -Recurse | Where-Object {$_.FullName -match "bin.*.Release.*ScaleUnit.*.exe$"} | ForEach-Object {$_.FullName}
        if($csuZipPackagePath)
        {    
            [Reflection.Assembly]::LoadWithPartialName('System.IO.Compression')
            $zipfile = $csuZipPackagePath
            $stream = New-Object IO.FileStream($zipfile, [IO.FileMode]::Open)
            $mode   = [IO.Compression.ZipArchiveMode]::Update
            $zip    = New-Object IO.Compression.ZipArchive($stream, $mode)
            ($zip.Entries | Where-Object { $_.Name -match 'Azure' }) | ForEach-Object { $_.Delete() }
            ($zip.Entries | Where-Object { $_.Name -match 'Microsoft' }) | ForEach-Object { $_.Delete() }
            ($zip.Entries | Where-Object { $_.Name -match 'System'  -and $_.Name -notmatch 'System.Runtime.Caching' -and $_.Name -notmatch 'System.ServiceModel.Http' -and $_.Name -notmatch 'System.ServiceModel.Primitives' -and $_.Name -notmatch 'System.Private.ServiceModel' -and $_.Name -notmatch 'System.Configuration.ConfigurationManager' -and $_.Name -notmatch 'System.Security.Cryptography.ProtectedData' -and $_.Name -notmatch 'System.Security.Permissions' -and $_.Name -notmatch 'System.Security.Cryptography.Xml' -and $_.Name -notmatch 'System.Security.Cryptography.Pkcs' }) | ForEach-Object { $_.Delete() }
            ($zip.Entries | Where-Object { $_.Name -match 'Newtonsoft' }) | ForEach-Object { $_.Delete() }
            $zip.Dispose()
            $stream.Close()
            $stream.Dispose()
            Copy-ToDestination -RelativePath $csuZipPackagePath.Parent.FullName -File $csuZipPackagePath.BaseName -DestinationFullName "$($artifactDirectory)\$(ClearExtension($csuZipPackagePath)).$($packageName).zip"
        }
        if($hWSInstallerPath)
        {    
            Copy-ToDestination -RelativePath $hWSInstallerPath.Parent.FullName -File $hWSInstallerPath.BaseName -DestinationFullName "$($artifactDirectory)\$(ClearExtension($hWSInstallerPath)).$($packageName).exe"
        }
        if($sCInstallerPath)
        {    
            Copy-ToDestination -RelativePath $sCInstallerPath.Parent.FullName -File $sCInstallerPath.BaseName -DestinationFullName "$($artifactDirectory)\$(ClearExtension($sCInstallerPath)).$($packageName).exe"
        }
        if($sUInstallerPath)
        {    
            Copy-ToDestination -RelativePath $sUInstallerPath.Parent.FullName -File $sUInstallerPath.BaseName -DestinationFullName "$($artifactDirectory)\$(ClearExtension($sUInstallerPath)).$($packageName).exe"
        }


        #sign files
        Get-ChildItem $artifactDirectory | Where-Object{$_.Extension -like ".exe"} | ForEach-Object
        {          
            [string]$filePath = "$($_.FullName)"
            switch($settings.codeSignType)
            {
                "azure_sign_tool" {
                    dotnet tool install --global AzureSignTool
                    azuresigntool sign  -kvu "$($settings.codeSighKeyVaultUri)" `
                                        -kvt "$($settings.codeSignKeyVaultTenantId)" `
                                        -kvc "$($settings.codeSignKeyVaultCertificateName)" `
                                        -kvi "$($settings.codeSignKeyVaultAppId)" `
                                        -kvs "$($settings.codeSignKeyVaultClientSecretName)" `
                                        -tr "$($settings.codeSignKeyVaultTimestampServer)" `
                                        -td sha256 "$filePath"
                }
                "digicert_keystore" {
                    OutputInfo "File: '$($_.FullName)' signing..."
                    Sign-BinaryFile -SM_API_KEY "$codeSignDigiCertAPISecretName" `
                    -SM_CLIENT_CERT_FILE_URL "$codeSignDigiCertUrlSecretName" `
                    -SM_CLIENT_CERT_PASSWORD $(ConvertTo-SecureString $codeSignDigiCertPasswordSecretName -AsPlainText -Force) `
                    -SM_CODE_SIGNING_CERT_SHA1_HASH "$codeSignDigiCertHashSecretName" `
                    -FILE "$filePath"
                }
            }
        }

        Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_NAME=$packageName"
        Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_NAME=$packageName"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_PATH=$artifactDirectory"
        Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_PATH=$artifactDirectory"
        
        $artifacts = Get-ChildItem $artifactDirectory
        $artifacts | Format-Table
        $artifactsList = $artifacts.FullName -join ","

        if($artifactsList.Contains(','))
        {
            $artifacts = $artifactsList.Split(',') | ConvertTo-Json -compress
        }
        else
        {
            $artifacts = '["'+$($artifactsList).ToString()+'"]'

        }

        Write-Output "::endgroup::"

        Write-Output "::group::Export NuGets"

        Set-Location $buildPath
        Get-ChildItem -Recurse | Where-Object {$_.FullName -match "bin.*.Release.*.nupkg$"} | ForEach-Object {
            $_.FullName
            $zipfile = $_
            # Cleanup NuGet file
            [Reflection.Assembly]::LoadWithPartialName('System.IO.Compression')            
            $stream = New-Object IO.FileStream($zipfile.FullName, [IO.FileMode]::Open)
            $mode   = [IO.Compression.ZipArchiveMode]::Update
            $zip    = New-Object IO.Compression.ZipArchive($stream, $mode)
            ($zip.Entries | Where-Object { $_.Name -match 'Azure' }) | ForEach-Object { $_.Delete() }
            ($zip.Entries | Where-Object { $_.Name -match 'Microsoft' }) | ForEach-Object { $_.Delete() }
            ($zip.Entries | Where-Object { $_.Name -match 'System' }) | ForEach-Object { $_.Delete() }
            ($zip.Entries | Where-Object { $_.Name -match 'Newtonsoft' }) | ForEach-Object { $_.Delete() }
            $zip.Dispose()
            $stream.Close()
            $stream.Dispose()
            Copy-ToDestination -RelativePath $_.Directory -File $_.Name -DestinationFullName "$($artifactDirectory)\$($_.BaseName).nupkg"        
        }

        Write-Output "::endgroup::"

        Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_LIST=$artifacts"
        Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_LIST=$artifacts"
     
        #deploy
        if($settings.deploy)
        {
            Write-Output "::group::Deployment"
            OutputInfo "======================================== ScaleUnit extension deployment"

            Set-Location $($artifactDirectory)

            $baseProductInstallRoot = "${Env:Programfiles}\Microsoft Dynamics 365\10.0\Commerce Scale Unit"

            [System.IO.DirectoryInfo]$sUExtPath = Get-ChildItem -Recurse | Where-Object {$_.FullName -match ".*ScaleUnit.*.exe$" } | ForEach-Object {$_.FullName}
            if($sUExtPath)
            {    
                Write-Host "Installing the extension."
                & $sUExtPath install
                
                if ($LastExitCode -ne 0) {
                    Write-Host
                    Write-CustomError "The extension installation has failed with exit code $LastExitCode. Please examine the above logs to fix a problem and start again."
                    Write-Host
                    exit $LastExitCode
                }  
                Set-Location $baseProductInstallRoot
                $extensionInstallPath = Join-Path $baseProductInstallRoot "Extensions/$(ClearExtension($sUInstallerPath))"
                $extensionInstallPath
                if(Test-Path $extensionInstallPath){
                    Write-Host
                    Write-Host "Copy the binary and symbol files into extensions folder."
                    Set-Location $buildPath
                    Get-ChildItem -Recurse | Where-Object {$_.FullName -match ".*.Runtime.*.bin.*.Release.*.Vertex.*pdb$"} | ForEach-Object {
                        $_.FullName
                        Copy-ToDestination -RelativePath $_.Directory -File $_.Name -DestinationFullName "$($extensionInstallPath)\$($_.Name)"   
                    }
                }               
             }

             OutputInfo "======================================== Validation info"
             $MachineName = "vtx-nextgen-csu.eastus.cloudapp.azure.com"
             $port = "443"

             #if ($Env:baseProduct_UseSelfHost -ne "true") {
                # IIS deployment requires the additional actions to start debugging
            
            $RetailServerRoot = "https://$($MachineName):$port/RetailServer"
        
            # Open a default browser with a healthcheck page
            $RetailServerHealthCheckUri = "$RetailServerRoot/healthcheck?testname=ping"
            Write-Host "Open the IIS site at '$RetailServerHealthCheckUri' to start the process to attach debugger to."
            #}

            Write-Output "::endgroup::"
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
