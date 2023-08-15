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
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)
    $workflowName = $env:GITHUB_WORKFLOW
    $settings = ReadSettings -baseFolder $ENV:GITHUB_WORKSPACE -workflowName $workflowName
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    $EnvironmentsFile = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\environments.json'
    $envsFile = (Get-Content $EnvironmentsFile) | ConvertFrom-Json

    $github = (Get-ActionContext)


    if($github.Payload.PSObject.Properties.Name -eq "inputs")
    {
        if($github.Payload.inputs)
        {
            if($github.Payload.inputs.PSObject.Properties.Name -eq "includeTestModels")
            {
                $settings.includeTestModel = ($github.Payload.inputs.includeTestModels -eq "True")
            }
            if($github.Payload.inputs.PSObject.Properties.Name -eq "customFileUrl")
            {
                if($github.Payload.inputs.customFileUrl -ne "" -and $github.Payload.inputs.customFileName -eq "")
                {
                    OutputError "Custom file name with extension should be provided!"
                }
            }
        }
    }

    if($workflowName -eq "(DEPLOY)")
    {
        invoke-git fetch --all -silent
        @($envsFile | ForEach-Object { 
            try {
                [DateTime]$lastCommitedDate = ((Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($(git log -1 --format=%ct "origin/$($_.settings.sourceBranch)")))).ToUniversalTime()
                OutputInfo "Environment $($_.Name). Latest branch commit at: $($lastCommitedDate)"
                [DateTime]$deployedDate = (Get-LatestDeployedDate -token $token -environmentName $_.Name -repoName "$($github.Payload.repository.name)").ToUniversalTime()
                OutputInfo "Environment $($_.Name). Latest deployed commit at: $($deployedDate)"
                if((New-TimeSpan -Start $($deployedDate) -End $($lastCommitedDate)).Ticks -gt 0)
                {
                    OutputInfo "Deploy $($_.Name)"
                }
                else {
                    OutputInfo "Do not deploy $($_.Name)"
                }
            }
            catch { 
                OutputInfo $_.Exception.ToString()
            }
        })
    }

    $repoType = $settings.type
    if($dynamicsEnvironment -and $dynamicsEnvironment -ne "*")
    {
        #merge environment settings into current Settings
        $dEnvCount = $dynamicsEnvironment.Split(",").Count
        ForEach($env in $envsFile)
        {
            if($dEnvCount -gt 1)
            {
                $dynamicsEnvironment.Split(",") | ForEach-Object {
                    if($env.name -eq $_)
                    {
                        if($env.settings.PSobject.Properties.name -match "deploy")
                        {
                            $env.settings.deploy = $true
                        }
                        MergeCustomObjectIntoOrderedDictionary -dst $settings -src $env.settings
                    }
                }
            }
            else {
                if($env.name -eq $dynamicsEnvironment)
                {
                    if($env.settings.PSobject.Properties.name -match "deploy")
                    {
                        $env.settings.deploy = $true
                    }
                    MergeCustomObjectIntoOrderedDictionary -dst $settings -src $env.settings
                }
            }
        }
        if($settings.sourceBranch){
            $sourceBranch = $settings.sourceBranch;
        }
        else
        {
            $sourceBranch = $settings.currentBranch;
        }

        if($dEnvCount -gt 1)
        {
            $environmentsJSon = $($dynamicsEnvironment.Split(",")  | ConvertTo-Json -compress)
        }
        else
        {
            $environmentsJson = '["'+$($dynamicsEnvironment).ToString()+'"]'
        }


        Add-Content -Path $env:GITHUB_OUTPUT -Value "SOURCE_BRANCH=$sourceBranch"
        Add-Content -Path $env:GITHUB_ENV -Value "SOURCE_BRANCH=$sourceBranch"

        Add-Content -Path $env:GITHUB_OUTPUT -Value "Environments=$environmentsJson"
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
                if($settings.deployOnlyNew)
                {
                    try {
                        $lastCommitedDate = (Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($(git log -1 --format=%ct "origin/$($_.settings.sourceBranch)")))
                        $deployedDate = Get-LatestDeployedDate -token $token -environmentName $_.Name -repoName "$($github.Payload.repository.name)"
                        if((New-TimeSpan -Start $deployedDate -End $lastCommitedDate).Ticks -gt 0)
                        {
                            $check = $true
                        }
                        else {
                            if(($github.EventName -eq "schedule") -or ($dynamicsEnvironment -eq "*"))
                            {
                                $check = $false
                            }
                        }
                    }
                    catch { 
                        OutputInfo -message "Environment history check issue: $($_.Exception.Message)"
                    }
                }
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
                $currentGitHubStatus = Get-LatestDeploymentState -token $token -repoName "$($github.Payload.repository.name)" -environmentName $_.Name
                if(-not ($currentGitHubStatus -eq "PENDING" -or $currentGitHubStatus -eq "IN_PROGRESS"))
                {
                    $_.Name
                }
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

        Add-Content -Path $env:GITHUB_OUTPUT -Value "Environments=$environmentsJson"
        Add-Content -Path $env:GITHUB_ENV -Value "Environments=$environmentsJson"
    }

    if($DynamicsVersion -ne "*" -and $DynamicsVersion)
    {
        $settings.buildVersion = $DynamicsVersion
        
        $ver = Get-VersionData -sdkVersion $settings.buildVersion
        $settings.retailSDKVersion = $ver.retailSDKVersion
        $settings.retailSDKURL = $ver.retailSDKURL
        $settings.ecommerceMicrosoftRepoBranch = $ver.ecommerceMicrosoftRepoBranch
    }

    $outSettings = @{}
    $getSettings | ForEach-Object {
        $setting = $_.Trim()
        $outSettings += @{ "$setting" = $settings."$setting" }
        Add-Content -Path $env:GITHUB_ENV -Value "$setting=$($settings."$setting")"
    }

    $outSettingsJson = $outSettings | ConvertTo-Json -Compress

    Add-Content -Path $env:GITHUB_OUTPUT -Value "Settings=$OutSettingsJson"
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"

    $gitHubRunner = $settings.githubRunner.Split(',') | ConvertTo-Json -compress
    Add-Content -Path $env:GITHUB_OUTPUT -Value "GitHubRunner=$githubRunner"

    if($settings.buildVersion.Contains(','))
    {
        $versionsJSon = $settings.buildVersion.Split(',') | ConvertTo-Json -compress

        Add-Content -Path $env:GITHUB_OUTPUT -Value "Versions=$versionsJSon"
        Add-Content -Path $env:GITHUB_ENV -Value "Versions=$versionsJSon"
    }
    else
    {
        $versionsJSon = '["'+$($settings.buildVersion).ToString()+'"]'

        Add-Content -Path $env:GITHUB_OUTPUT -Value "Versions=$versionsJSon"
        Add-Content -Path $env:GITHUB_ENV -Value "Versions=$versionsJSon"
    }

    Add-Content -Path $env:GITHUB_OUTPUT -Value "type=$repoType"
    Add-Content -Path $env:GITHUB_ENV -Value "type=$repoType"

}
catch {
    OutputError -message $_.Exception.Message
    exit
}
finally {
}
