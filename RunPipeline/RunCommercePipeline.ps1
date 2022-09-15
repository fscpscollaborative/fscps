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
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSCM-PS-Helper.ps1" -Resolve)
    $LastExitCode = 0
    #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    OutputInfo "======================================== Use settings and secrets"

    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable | ConvertTo-OrderedDictionary

    #$settings = $settingsJson | ConvertFrom-Json 
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable

    $settingsHash = $settings #| ConvertTo-HashTable
    'nugetFeedPasswordSecretName','nugetFeedUserSecretName','lcsUsernameSecretname','lcsPasswordSecretname','azClientsecretSecretname' | ForEach-Object {
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
    

    $versions = Get-Versions | ConvertFrom-Json

    if($DynamicsVersion -eq "")
    {
        $DynamicsVersion = $settings.buildVersion
    }

    if($settings.sourceBranch -eq "")
    {
        $settings.sourceBranch = $settings.currentBranch
    }
    $settings
    #SourceBranchToPascakCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })
    
    Foreach($version in $versions)
    {
        if($version.version -eq $DynamicsVersion)
        {
            $PlatformVersion = $version.data.PlatformVersion
            $ApplicationVersion = $version.data.AppVersion
        }
    }

    $project = "" 
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $ENV:GITHUB_WORKSPACE
    }
    $workflowName = $env:GITHUB_WORKFLOW

    
    $buildPath = $settings.retailSDKBuildPath
    Write-Output "::endgroup::"

    Write-Output "::group::Cleanup folder"
    OutputInfo "======================================== Cleanup folders"
    #Cleanup Build folder
    Remove-Item $buildPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "::endgroup::"

    Write-Output "::group::Expand RetailSDK"
    OutputInfo "======================================== Cleanup folders"
    $sdkzipPath = Update-RetailSDK -sdkVersion $DynamicsVersion -sdkPath
    Expand-7zipArchive -Path $sdkzipPath -DestinationPath $buildPath

    Remove-Item $buildPath\SampleExtensions -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "::endgroup::"

    Write-Output "::group::Copy branch files"
    OutputInfo "======================================== Copy branch files"
    #Copy branch files
    New-Item -ItemType Directory -Force -Path $buildPath; Copy-Item $ENV:GITHUB_WORKSPACE\* -Destination $buildPath -Recurse -Force
    Write-Output "::endgroup::"

    Write-Output "::group::Copy solution folder"
    OutputInfo "======================================== Copy solution folder"
    #Copy solution folder
    Copy-Item NewBuild -Destination $buildPath -Recurse -Force
    Write-Output "::endgroup::"

    Write-Output "::group::Cleanup NuGet"
    OutputInfo "======================================== Cleanup NuGet"
    #Cleanup NuGet
    nuget sources remove -Name $settings.nugetFeedName -Source $settings.nugetSourcePath
    Write-Output "::endgroup::"

    Write-Output "::group::Nuget add source"
    OutputInfo "======================================== Nuget add source"
    #Nuget add source
    $nugetUserName = if($nugetFeedUserName){$settings.nugetFeedUserName}else{$nugetFeedUserSecretName}
    nuget sources Add -Name $settings.nugetFeedName -Source $settings.nugetSourcePath -username $nugetUserName -password $nugetFeedPasswordSecretName
   
    $packagesFilePath = Join-Path $buildPath NewBuild\packages.config
    Write-Output "::endgroup::"

    Write-Output "::group::Nuget install packages"
    OutputInfo "======================================== Nuget install packages"

    cd $buildPath

    #Nuget install packages
    nuget restore -PackagesDirectory $settings.nugetPackagesPath
    Write-Output "::endgroup::"


    Write-Output "::group::Build solution"
    #Build solution
    OutputInfo "======================================== Build solution"
    cd $buildPath

    Install-Module -Name Invoke-MsBuild

    $msbuildresult = Invoke-MsBuild -Path dirs.proj -ShowBuildOutputInCurrentWindow

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


}
catch {
    OutputError -message $_.Exception.Message
}

