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
    
    installModules @("fscps.tools")
    $LastExitCode = 0
    $workflowName = $env:GITHUB_WORKFLOW
    $github = (Get-ActionContext)

    #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    Convert-FSCPSTextToAscii -Text "Use settings and secrets" -Font "Standard" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110
    

    $settings = Get-FSCPSSettings -SettingsJsonString $settingsJson -OutputAsHashtable    

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

    if($settings.sourceBranch -eq "")
    {
        $settings.sourceBranch = $settings.currentBranch
    }

    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    $settings = Get-FSCPSSettings -SettingsJsonString ($settings | ConvertTo-Json) -OutputAsHashtable
    $settings

    Write-Output "::endgroup::"

    Write-Output "::group::Build solution"
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
            $manifestFilePath = '.\POS\manifest.json'

            if(Test-Path $manifestFilePath)
            {
                $manifestFileContent = (Get-Content $manifestFilePath)
                $curNumber = $manifestFileContent -match '.*"version": "(\d*).*'
                $newNumber = ""
                if ($curNumber) {
                    $newNumber = $curNumber -replace '\d.*\d.*\d.*\d', "$($versions[0]).$($versions[1]).$($versions[2]).$($versions[3])"
                    $manifestFileContent.Replace($curNumber, $newNumber) | Set-Content $manifestFilePath
                }              
            }
        }
    }

    $buildResult = Invoke-FSCPSCompile -SourcesPath $ENV:GITHUB_WORKSPACE
        

    ### Postbuild
    $postbuildCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\PostBuild.ps1'
    if(Test-Path $postbuildCustomScript)
    {
        & $postbuildCustomScript -settings $settings -githubContext $github -helperPath $helperPath
    }
    ### Postbuild
    Write-Output "::endgroup::"


    ### UnitTesting
    $unitTestingCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\UnitTesting.ps1'
    if(Test-Path $unitTestingCustomScript)
    {
        & $unitTestingCustomScript -settings $settings -githubContext $github -helperPath $helperPath
    }
    ### UnitTesting

    #GeneratePackages
    if($settings.generatePackages)
    {
        $buildResult

       
        $PACKAGE_NAME = $buildResult.PACKAGE_NAME
        $ARTIFACTS_PATH = $buildResult.ARTIFACTS_PATH
        $ARTIFACTS_LIST = $buildResult.ARTIFACTS_LIST
        $SU_INSTALLER_PATH = $buildResult.SU_INSTALLER_PATH
        $BUILD_FOLDER_PATH = $buildResult.BUILD_FOLDER_PATH
        
        Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_NAME=$PACKAGE_NAME"
        Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_NAME=$PACKAGE_NAME"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_PATH=$ARTIFACTS_PATH"
        Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_PATH=$ARTIFACTS_PATH"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_LIST=$ARTIFACTS_LIST"
        Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_LIST=$ARTIFACTS_LIST"

        if($settings.signArtifacts)
        {
            Write-Output "::group::Sign packages"
            #sign files
            
            Get-ChildItem $ARTIFACTS_PATH | Where-Object {$_.Extension -like ".exe"} | ForEach-Object{          
                Write-Output "Signing File: '$($_.FullName)' ..."
                [string]$filePath = "$($_.FullName)"
                try {
                    if(!$codeSignKeyVaultClientSecretName){throw "GitHub secret SIGN_KV_CLIENTSECRET not found. Please, create it."}
                }
                catch {
                    OutputError $_.Exception.Message
                }
                switch ( $settings.codeSignType )
                {
                    "azure_sign_tool" {
                        try {
                            & dotnet tool install --global AzureSignTool;
                        }
                        catch {
                            OutputInfo "$($_.Exception.Message)"
                        }
                        try {
                            & azuresigntool sign -kvu "$($settings.codeSighKeyVaultUri)" -kvt "$($settings.codeSignKeyVaultTenantId)" -kvc "$($settings.codeSignKeyVaultCertificateName)" -kvi "$($settings.codeSignKeyVaultAppId)" -kvs "$($codeSignKeyVaultClientSecretName)" -tr "$($settings.codeSignKeyVaultTimestampServer)" -td sha256 "$filePath"
                        }                     
                        catch {
                            OutputInfo "$($_.Exception.Message)"
                        }
                        break;
                    }
                    "digicert_keystore" {                    
                        Invoke-FSCPSDigiCertSignFile -SM_API_KEY "$codeSignDigiCertAPISecretName" `
                        -SM_CLIENT_CERT_FILE_URL "$codeSignDigiCertUrlSecretName" `
                        -SM_CLIENT_CERT_PASSWORD $(ConvertTo-SecureString $codeSignDigiCertPasswordSecretName -AsPlainText -Force) `
                        -SM_CODE_SIGNING_CERT_SHA1_HASH "$codeSignDigiCertHashSecretName" `
                        -FILE "$filePath"
                        break;
                    }
                }
            }
            Write-Output "::endgroup::"
        }        

     
        #deploy
        if($settings.deploy)
        {
            Write-Output "::group::Deployment"
            Convert-FSCPSTextToAscii -Text "ScaleUnit extension deployment" -Font "Standard" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 105

            $baseProductInstallRoot = "${Env:Programfiles}\Microsoft Dynamics 365\10.0\Commerce Scale Unit"

            if($SU_INSTALLER_PATH)
            {    
                Write-Host "Installing the extension."
                & $SU_INSTALLER_PATH install
                
                if ($LastExitCode -ne 0) {
                    Write-CustomError "The extension installation has failed with exit code $LastExitCode. Please examine the above logs to fix a problem and start again."
                    exit $LastExitCode
                }  
                $extensionInstallPath = Join-Path $baseProductInstallRoot "Extensions/$(ClearExtension($SU_INSTALLER_PATH))"
                $extensionInstallPath
                if(Test-Path $extensionInstallPath){

                    Write-Host "Copy the binary and symbol files into extensions folder."
                    Set-Location $BUILD_FOLDER_PATH
                    Get-ChildItem -Path $BUILD_FOLDER_PATH -Recurse | Where-Object {$_.FullName -match ".*.Runtime.*.bin.*.Release.*.Vertex.*pdb$"} | ForEach-Object {
                        $_.FullName
                        Copy-ToDestination -RelativePath $_.Directory -File $_.Name -DestinationFullName "$($extensionInstallPath)\$($_.Name)"
                    }
                }
            }

            <#  OutputInfo "======================================== Validation info"
            $MachineName = "*-nextgen-csu.eastus.cloudapp.azure.com"
            $port = "443"

            #if ($Env:baseProduct_UseSelfHost -ne "true") {
            # IIS deployment requires the additional actions to start debugging
            
            $RetailServerRoot = "https://$($MachineName):$port/RetailServer"
        
            # Open a default browser with a healthcheck page
            $RetailServerHealthCheckUri = "$RetailServerRoot/healthcheck?testname=ping"
            Write-Host "Open the IIS site at '$RetailServerHealthCheckUri' to start the process to attach debugger to."
            #}

            Write-Output "::endgroup::"
            #>

            ### PostDeploy
            $postdeployCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\PostDeploy.ps1'
            if(Test-Path $postdeployCustomScript)
            {
                & $postdeployCustomScript -settings $settings -githubContext $github -helperPath $helperPath
            }
            ### PostDeploy
        }
        Convert-FSCPSTextToAscii -Text "Done" -Font "Standard" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 105 -Padding 2

    }

}
catch {
    OutputError -message $_.Exception.Message
}
finally
{
    OutputInfo "Execution is done."
}
