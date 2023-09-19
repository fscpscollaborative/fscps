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

    Write-Output "::group::Nuget install packages"
    OutputInfo "======================================== Nuget install packages"
    $packagesFilePath = Join-Path $buildPath packages.config
    if(Test-Path $packagesFilePath)
    {
        OutputInfo "Found packages.config file at path: $packagesFilePath "
    }
    else
    {
        OutputInfo "Not Found packages.config file at path: $packagesFilePath "
    }
    
    Set-Location $buildPath
    Get-ChildItem $buildPath
    #Nuget install packages
    nuget restore $packagesFilePath
    Write-Output "::endgroup::"

    Write-Output "::group::Build solution"
    #Build solution
    OutputInfo "======================================== Build solution"
    Set-Location $buildPath

    ### Prebuild
    $prebuildCustomScript = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\CustomScripts\PreBuild.ps1'
    if(Test-Path $prebuildCustomScript)
    {
        & $prebuildCustomScript -settings $settings -githubContext $github -helperPath $helperPath
    }
    ### Prebuild

    #dotnet build /property:Configuration=Debug /property:NuGetInteractive=true
    
    #& msbuild
    installModules "Invoke-MsBuild"
    $msbuildpath = & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -products * -requires Microsoft.Component.MSBuild -property installationPath -version "[16.12,17.11)"
    if($msbuildpath -ne "")
    {
        $msbuildexepath = Join-Path $msbuildpath "MSBuild\Current\Bin\MSBuild.exe"
        $msbuildresult = Invoke-MsBuild -Path $settings.solutionName -MsBuildParameters "/property:Configuration=Debug /property:NuGetInteractive=true" -MsBuildFilePath "$msbuildexepath" -ShowBuildOutputInCurrentWindow -BypassVisualStudioDeveloperCommandPrompt
    }
    else
    {
        $msbuildresult = Invoke-MsBuild -Path $settings.solutionName -MsBuildParameters "/property:Configuration=Debug /property:NuGetInteractive=true" -ShowBuildOutputInCurrentWindow 
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

}
catch {
    OutputError -message $_.Exception.Message
}
finally
{
    OutputInfo "Execution is done."
}

