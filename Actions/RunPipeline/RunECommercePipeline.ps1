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
    $github = (Get-ActionContext)
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable | ConvertTo-OrderedDictionary
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $settingsHash = $settings 
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
    #SourceBranchToPascalCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    $PlatformVersion = $version.PlatformVersion
    $ApplicationVersion = $version.AppVersion
    $workflowName = $env:GITHUB_WORKFLOW

    $tempPath = "C:\Temp"
    $buildPath = Join-Path $tempPath "Msdyn365.Commerce.Online"
    Write-Output "::endgroup::"

    Write-Output "::group::Cleanup folder"
    OutputInfo "======================================== Cleanup folders"
    #Cleanup Build folder
    Remove-Item $buildPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "::endgroup::"

    Write-Output "::group::Build solution"
    #Build solution
    OutputInfo "======================================== Build solution"

    ### Prebuild
    $prebuildCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\PreBuild.ps1'
    if(Test-Path $prebuildCustomScript)
    {
        & $prebuildCustomScript -settings $settings -githubContext $github -helperPath $helperPath
    }
    ### Prebuild

    ### install python
    Set-Location $tempPath
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.7.0/python-3.7.0.exe" -OutFile "$tempPath\python-3.7.0.exe"
    .\python-3.7.0.exe /quiet InstallAllUsers=0 PrependPath=1 Include_test=0

    ###install yarn 
    npm install --global yarn

    $settings.ecommerceMicrosoftRepoUrl
    $settings.ecommerceMicrosoftRepoBranch
    Set-Location $tempPath

    ### clone msdyn365 repo
    New-Item -ItemType Directory -Force -Path $buildPath
    OutputInfo "Git clone"
    invoke-git clone --quiet $settings.ecommerceMicrosoftRepoUrl
    OutputInfo "Set location $buildPath" 
    Set-Location $buildPath
    invoke-git fetch --all
    invoke-git checkout "$($settings.ecommerceMicrosoftRepoBranch)"

    #remove git folder
    Remove-Item $buildPath\.git -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $buildPath\src -Recurse -Force -ErrorAction SilentlyContinue
    #Copy branch files
    Copy-Item $ENV:GITHUB_WORKSPACE\* -Destination $buildPath -Recurse -Force

    ### yarn load dependencies
    yarn msdyn365 update-versions sdk
    yarn msdyn365 update-versions module-library
    yarn msdyn365 update-versions retail-proxy

    yarn

    ### generate package
    yarn msdyn365 pack

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
        
        $packageConfig = (Get-Content "$buildPath\package.json") | ConvertFrom-Json | ConvertTo-HashTable | ConvertTo-OrderedDictionary
        OutputInfo "Parsed package.json file"

        $ecommPackageName = "$($packageConfig.name)-$($packageConfig.version).zip"
        $packageNamePattern = $settings.packageNamePattern;
        $packageNamePattern = $packageNamePattern.Replace("BRANCHNAME", $($settings.sourceBranch))

        if($settings.deploy)
        {
            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME", $EnvironmentName)
        }
        else
        {
            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME", "$($settings.packageName)-$($packageConfig.version)")
        }

        $packageNamePattern = $packageNamePattern.Replace("FNSCMVERSION", $DynamicsVersion)
        $packageNamePattern = $packageNamePattern.Replace("DATE", (Get-Date -Format "yyyyMMdd").ToString())
        $packageNamePattern = $packageNamePattern.Replace("RUNNUMBER", $ENV:GITHUB_RUN_NUMBER)
        $packageName = $packageNamePattern + ".zip"
        OutputInfo "Package name generated"

        Rename-Item -Path (Join-Path $buildPath $ecommPackageName) -NewName $packageName
        OutputInfo "Package renamed"
        $buildPath
        $packageName
        $packagePath = Join-Path "$buildPath" "$packageName"

        OutputInfo "Package name: $packageName"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_NAME=$packageName"
        Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_NAME=$packageName"
        OutputInfo "Package name: $packagePath"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_PATH=$packagePath"
        Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_PATH=$packagePath"


        Write-Output "::endgroup::"

        #Upload to LCS
        $assetId = ""
        if($settings.uploadPackageToLCS)
        {
            Write-Output "::group::Upload artifact to the LCS"
            OutputInfo "======================================== Upload artifact to the LCS"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Get-D365LcsApiToken -ClientId $settings.lcsClientId -Username "$lcsUsernameSecretname" -Password "$lcsPasswordSecretName" -LcsApiUri "https://lcsapi.lcs.dynamics.com" -Verbose | Set-D365LcsApiConfig -ProjectId $settings.lcsProjectId
            $assetId = Invoke-D365LcsUpload -FilePath "$packagePath" -FileType "ECommercePackage" -Name "$packageName" -Verbose
            Write-Output "::endgroup::"
        }
    }
}
catch {
    OutputError -message $_.Exception.Message
}

