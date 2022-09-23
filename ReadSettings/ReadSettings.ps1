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
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSCM-PS-Helper.ps1" -Resolve)

    $settings = ReadSettings -baseFolder $ENV:GITHUB_WORKSPACE -workflowName $env:GITHUB_WORKFLOW
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    $EnvironmentsFile = Join-Path $ENV:GITHUB_WORKSPACE '.FSCM-PS\environments.json'
    $envsFile = (Get-Content $EnvironmentsFile) | ConvertFrom-Json

    $github = (Get-ActionContext)

    if($dynamicsEnvironment -and $dynamicsEnvironment -ne "*")
    {
        #merge environment settings into current Settings
        ForEach($env in $envsFile)
        {
            if($env.name -eq $dynamicsEnvironment)
            {
                if($env.settings.PSobject.Properties.name -match "deploy")
                {
                    $env.settings.deploy = $true
                }
                MergeCustomObjectIntoOrderedDictionary -dst $settings -src $env.settings
                $settings
            }
        }
        if($settings.sourceBranch){
            $sourceBranch = $settings.sourceBranch;
        }
        else
        {
            $sourceBranch = $settings.currentBranch;
        }

        Write-Host "::set-output name=SOURCE_BRANCH::$sourceBranch"
        Write-Host "set-output name=SOURCE_BRANCH::$sourceBranch"
        Add-Content -Path $env:GITHUB_ENV -Value "SOURCE_BRANCH=$sourceBranch"

        $environmentsJson = '["'+$($dynamicsEnvironment).ToString()+'"]'
        Write-Host "::set-output name=EnvironmentsJson::$environmentsJson"
        Write-Host "set-output name=EnvironmentsJson::$environmentsJson"
        Add-Content -Path $env:GITHUB_ENV -Value "Environments=$environmentsJson"
    }
    else    
    {
        $environments = @($envsFile | ForEach-Object { 
            $check = $true
            if($_.settings.PSobject.Properties.name -match "deploy")
            {
                $check = $_.settings.deploy
            }
            
            if($check)
            {
                if($github.EventName -eq "schedule")
                {
                     $check = Test-CronExpression -Expression $_.settings.cron -DateTime ([DateTime]::Now) -WithDelayMinutes 29
                }
            }
            if($check)
            {
                $_.Name
            }
        })

        if($environments.Count -eq 1)
        {
            $environmentsJson = '["'+$($environments[0]).ToString()+'"]'
        }
        else
        {
            $environmentsJSon = $environments | ConvertTo-Json -compress
        }

        Write-Host "::set-output name=EnvironmentsJson::$environmentsJson"
        Write-Host "set-output name=EnvironmentsJson::$environmentsJson"
        Add-Content -Path $env:GITHUB_ENV -Value "Environments=$environmentsJson"
    }

    if($DynamicsVersion -ne "*" -and $DynamicsVersion)
    {
        $settings.buildVersion = $DynamicsVersion
    }

    $ver = Get-VersionData -sdkVersion $settings.buildVersion
    $settings.retailSDKVersion = $ver.retailSDKVersion
    $settings.retailSDKURL = $ver.retailSDKURL


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

    if($settings.buildVersion.Contains(','))
    {
        $versionsJSon = $settings.buildVersion.Split(',') | ConvertTo-Json -compress
        Write-Host "::set-output name=VersionsJson::$versionsJSon"
        Write-Host "set-output name=VersionsJson::$versionsJSon"
        Add-Content -Path $env:GITHUB_ENV -Value "Versions=$versionsJSon"
    }
    else
    {
        $versionsJSon = '["'+$($settings.buildVersion).ToString()+'"]'
        Write-Host "::set-output name=VersionsJson::$versionsJSon"
        Write-Host "set-output name=VersionsJson::$versionsJSon"
        Add-Content -Path $env:GITHUB_ENV -Value "Versions=$versionsJSon"
    }
}
catch {
    OutputError -message $_.Exception.Message
    exit
}
finally {
}
