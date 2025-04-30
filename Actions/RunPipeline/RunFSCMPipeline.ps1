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
    installModules @("fscps.tools", "fscps.ascii")
    $LastExitCode = 0
    $workflowName = $env:GITHUB_WORKFLOW
    $github = (Get-ActionContext)

    #Use settings and secrets
    Convert-FSCPSTextToAscii -Text "Use settings and secrets" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
    $settings = Get-FSCPSSettings -SettingsJsonString $settingsJson -OutputAsHashtable
    $settings

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
            $value = "test"
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

    $version

    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    $settings = Get-FSCPSSettings -SettingsJsonString ($settings | ConvertTo-Json) -OutputAsHashtable
    $buildPath = Join-Path "C:\Temp" $settings.buildPath

    $msMetadataDirectory = "$($buildPath)\$($settings.metadataPath)".Trim()

    $mainModel = Get-FSCModels -metadataPath $settings.metadataPath

    ### Init
    $initCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\Init.ps1'
    if(Test-Path $initCustomScript)
    {
        & $initCustomScript -settings $settings -githubContext $github -helperPath $helperPath -token $repoTokenSecretName
    }
    ### Init

    # GetModels
    if($($settings.specifyModelsManually) -eq "true")
    {
        $mtdtdPath = ("$($buildPath)\$($settings.metadataPath)".Trim())
        $mdls = $($settings.models).Split(",")
        if($($settings.includeTestModel) -eq "true")
        {
            $testModels = Get-AXReferencedTestModel -modelNames $($mdls -join ",") -metadataPath $mtdtdPath
            ($testModels.Split(",").ForEach({$mdls+=($_)}))
        }
        $models = $mdls -join ","
        $modelsToPackage = $models
    }
    else {
        $models = Get-FSCModels -metadataPath $settings.metadataPath -includeTest:($settings.includeTestModel -eq 'true')
        $modelsToPackage = Get-FSCModels -metadataPath $settings.metadataPath -includeTest:($settings.includeTestModel -eq 'true') -all
    }
   


    try
    {                  
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
                if($models.Split(","))
                {
                    if($mainModel.Split(","))
                    {
                        Update-FSCPSModelVersion -xppSourcePath $settings.metadataPath -xppLayer "ISV" -versionNumber $($github.Payload.inputs.versionNumber) -xppDescriptorSearch $($($mainModel.Split(",").Item(0))+"\Descriptor\*.xml")
                    }
                    else {
                        Update-FSCPSModelVersion -xppSourcePath $settings.metadataPath -xppLayer "ISV" -versionNumber $($github.Payload.inputs.versionNumber) -xppDescriptorSearch $($mainModel+"\Descriptor\*.xml")
                    }
                }
                else {
                    Update-FSCPSModelVersion -xppSourcePath $msMetadataDirectory -xppLayer "ISV" -versionNumber $($github.Payload.inputs.versionNumber) -xppDescriptorSearch $($models+"\Descriptor\*.xml")
                }
            }
        }
        
        $buildResult = Invoke-FSCPSCompile -SourcesPath $ENV:GITHUB_WORKSPACE 
        $buildResult
        ### Postbuild
        $postbuildCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\PostBuild.ps1'
        if(Test-Path $postbuildCustomScript)
        {
            & $postbuildCustomScript -settings $settings -githubContext $github -helperPath $helperPath
        }
        ### Postbuild

        if($settings.generatePackages)
        {
            $pname                  = $buildResult.PACKAGE_NAME
            $deployablePackagePath  = $buildResult.PACKAGE_PATH
            $artifactDirectory      = $buildResult.ARTIFACTS_PATH

            Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_NAME=$pname"
            Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_NAME=$pname"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_PATH=$deployablePackagePath"
            Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_PATH=$deployablePackagePath"
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

            #Upload to LCS
            $assetId = ""
            if($settings.uploadPackageToLCS)
            {
                Convert-FSCPSTextToAscii -Text "Upload artifact to the LCS" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Get-D365LcsApiToken -ClientId $settings.lcsClientId -Username "$lcsUsernameSecretname" -Password "$lcsPasswordSecretName" -LcsApiUri "https://lcsapi.lcs.dynamics.com" -Verbose | Set-D365LcsApiConfig -ProjectId $settings.lcsProjectId
                $assetId = Invoke-D365LcsUpload -FilePath "$deployablePackagePath" -FileType "SoftwareDeployablePackage" -Name "$pname" -Verbose -EnableException

                #Deploy asset to the LCS Environment
                if($settings.deploy)
                {
                    Convert-FSCPSTextToAscii -Text "Deploy asset to the LCS Environment" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
                
                    #Check environment status

                    Convert-FSCPSTextToAscii -Text "Che ck $($EnvironmentName) status" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
                
                    $azurePassword = ConvertTo-SecureString $azClientsecretSecretname -AsPlainText -Force
                    $psCred = New-Object System.Management.Automation.PSCredential($settings.azClientId , $azurePassword)

                    OutputInfo "Check az cli installation..."
                    if(-not(Test-Path -Path "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\"))
                    {
                        OutputInfo "az cli installing.."
                        $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; Remove-Item .\AzureCLI.msi
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
                        Convert-FSCPSTextToAscii -Text "Start $($EnvironmentName)" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
                
                        Invoke-D365LcsEnvironmentStart -EnvironmentId $settings.lcsEnvironmentId
                        Start-Sleep -Seconds 60
                    #}

                    #Deploy asset to the LCS Environment

                    Convert-FSCPSTextToAscii -Text "Deployment..." -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
                
                    $WaitForCompletion = $true
                    $PSFObject = Invoke-D365LcsDeployment -AssetId "$($assetId.AssetId)" -EnvironmentId "$($settings.lcsEnvironmentId)" -UpdateName "$pname"
                    $errorCnt = 0
                    $deploymentStatus = ""
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
                        if(($deploymentStatus.OperationStatus -eq "Failed") -or [string]::IsNullOrEmpty($deploymentStatus.OperationStatus))
                        {
                            $errorMessagePayload = "`r`n$($deploymentStatus | ConvertTo-Json)"
                            OutputError -message $errorMessagePayload
                        }

                        OutputInfo "Deployment status: $($deploymentStatus.OperationStatus)"
                    }
                    while ((($deploymentStatus.OperationStatus -eq "InProgress") -or ($deploymentStatus.OperationStatus -eq "NotStarted") -or ($deploymentStatus.OperationStatus -eq "PreparingEnvironment")) -and $WaitForCompletion)
                    
                    
                    if(($deploymentStatus.OperationStatus -eq "Completed"))
                    {
                        $lcsConfig = Get-D365LcsApiConfig
                        Remove-D365LcsAssetFile -ProjectId $lcsConfig.projectid -AssetId "$($assetId.AssetId)" -BearerToken $lcsConfig.bearertoken -LcsApiUri $lcsConfig.lcsapiuri -Verbose
                        
                    }

                    if($PowerState -ne "running")
                    {
                        Convert-FSCPSTextToAscii -Text "Stop $($EnvironmentName)" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
                
                        Invoke-D365LcsEnvironmentStop -EnvironmentId $settings.lcsEnvironmentId
                    }
                }
            }
        }
        Convert-FSCPSTextToAscii -Text "Done" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
    }
    finally
    {
    }
}
catch {
    OutputError -message $_.Exception.Message
}
finally
{
    OutputInfo "Execution is done."
}