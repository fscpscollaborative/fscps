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

    $settings = ReadSettings -baseFolder $ENV:GITHUB_WORKSPACE -workflowName $env:GITHUB_WORKFLOW
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
        }
    }


    @($envsFile | ForEach-Object { 
        try {
            $latestCommitId = invoke-git rev-parse --short "origin/$($_.settings.sourceBranch)" -returnValue
            OutputInfo "Environment $($_.Name). Latest branch commit is: $($latestCommitId)"
            $result = Get-LatestDeployedCommit -token $token -environmentName $_.Name
            OutputInfo "Environment $($_.Name). Latest deployed commit is: $($result)"
        }
        catch { 
            OutputInfo $_.Exception.ToString()
        }
    })


    $repoType = $settings.type
    if($dynamicsEnvironment -and $dynamicsEnvironment -ne "*")
    {
        #merge environment settings into current Settings
        $dEnvCount = $dynamicsEnvironment.Split(",").Count
        $deployEns = @()
        ForEach($env in $envsFile)
        {
            $check = $false
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

            if($settings.deployOnlyNew)
            {
                try {
                    $result = Get-LatestDeployedCommit -token $token -environmentName $env.Name
                
                    $latestCommitId = invoke-git rev-parse --short $env.settings.sourceBranch -returnValue
                    
                    if($result)
                    {
                        $check = $latestCommitId -eq $result.Value
                    }
                }
                catch { }
            }
            if($check) {$deployEns.Add($env.Name)}
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
            $environmentsJSon = $($deployEns.Split(",")  | ConvertTo-Json -compress)
        }
        else
        {
            $environmentsJson = '["'+$($deployEns).ToString()+'"]'
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
                if($github.EventName -eq "schedule")
                {
                     $check = Test-CronExpression -Expression $_.settings.cron -DateTime ([DateTime]::Now) -WithDelayMinutes 29
                }
            }
            if($settings.deployOnlyNew)
            {
                try {
                    $latestCommitId = invoke-git rev-parse --short $_.settings.sourceBranch -returnValue
                    $result = Get-LatestDeployedCommit -token $token -environmentName $_.Name
                    if($result)
                    {
                        $check = $latestCommitId -ne $result.Value
                    }
                }
                catch { }
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

        Add-Content -Path $env:GITHUB_OUTPUT -Value "Environments=$environmentsJson"
        Add-Content -Path $env:GITHUB_ENV -Value "Environments=$environmentsJson"
    }

    if($DynamicsVersion -ne "*" -and $DynamicsVersion)
    {
        $settings.buildVersion = $DynamicsVersion
        
        $ver = Get-VersionData -sdkVersion $settings.buildVersion
        $settings.retailSDKVersion = $ver.retailSDKVersion
        $settings.retailSDKURL = $ver.retailSDKURL
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
