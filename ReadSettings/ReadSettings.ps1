Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "DynamicsVersion", Mandatory = $false)]
    [string] $dynamicsVersion = "",
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = "",
    [Parameter(HelpMessage = "Merge settings from specific environment", Mandatory = $false)]
    [string] $dynamicsEnvironment = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FnSCM-Go-Helper.ps1" -Resolve)

    $settings = ReadSettings -baseFolder $ENV:GITHUB_WORKSPACE -workflowName $env:GITHUB_WORKFLOW
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    if($DynamicsVersion -ne "*")
    {
        $settings.buildVersions = $DynamicsVersion
    }
        
    if ($ENV:GITHUB_EVENT_NAME -eq "pull_request") {
        $settings.doNotSignApps = $true
    }

    $outSettings = @{}
    $getSettings | ForEach-Object {
        $setting = $_.Trim()
        $outSettings += @{ "$setting" = $settings."$setting" }
        Add-Content -Path $env:GITHUB_ENV -Value "$setting=$($settings."$setting")"
    }

    $outSettingsJson = $outSettings | ConvertTo-Json -Compress
    Write-Host "::set-output name=SettingsJson::$outSettingsJson"
    Write-Host "set-output name=SettingsJson::$outSettingsJson"
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"

    $gitHubRunner = $settings.githubRunner.Split(',') | ConvertTo-Json -compress
    Write-Host "::set-output name=GitHubRunnerJson::$githubRunner"
    Write-Host "set-output name=GitHubRunnerJson::$githubRunner"



    if($settings.buildVersions.Contains(','))
    {
        $versionsJSon = $settings.buildVersions.Split(',') | ConvertTo-Json -compress
        Write-Host "::set-output name=VersionsJson::$versionsJSon"
        Write-Host "set-output name=VersionsJson::$versionsJSon"
        Add-Content -Path $env:GITHUB_ENV -Value "Versions=$versionsJSon"
    }
    else
    {
        $versionsJSon = '["'+$($settings.buildVersions).ToString()+'"]'
        Write-Host "::set-output name=VersionsJson::$versionsJSon"
        Write-Host "set-output name=VersionsJson::$versionsJSon"
        Add-Content -Path $env:GITHUB_ENV -Value "Versions=$versionsJSon"
    }

    if ($dynamicsEnvironment -ne "") {

        $EnvironmentsFile = Join-Path $ENV:GITHUB_WORKSPACE '.FnSCM-Go\environments.json'
        $envsFile = (Get-Content $EnvironmentsFile) | ConvertFrom-Json

        Write-Host "lcsEnvironmentId: "$settings.lcsEnvironmentId
        #merge environment settings into current Settings
        if($dynamicsEnvironment )
        {
            $envsFile | ForEach-Object
            {
                if($_.name -eq $EnvironmentName)
                {
                    MergeCustomObjectIntoOrderedDictionary -dst $settings -src $_.settings
                }
            }
        }

        Write-Host "lcsEnvironmentId: "$settings.lcsEnvironmentId

        $environments = @($envsFile | ForEach-Object { $_.Name })
        $environmentsJSon = $environments | ConvertTo-Json -compress
        Write-Host "::set-output name=EnvironmentsJson::$environmentsJson"
        Write-Host "set-output name=EnvironmentsJson::$environmentsJson"
        Add-Content -Path $env:GITHUB_ENV -Value "Environments=$environmentsJson"
    }
}
catch {
    OutputError -message $_.Exception.Message
    exit
}
finally {
}
