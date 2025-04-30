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
    Import-Module (Join-Path $PSScriptRoot "..\FSC-PS-Helper.ps1")
    installModules @("fscps.tools", "fscps.ascii")
    $workflowName = $env:GITHUB_WORKFLOW
    $Script:IsOnGitHub = $true
    Set-FSCPSSettings -Verbose

    $settings = Get-FSCPSSettings -OutputAsHashtable
    #$settings
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    $EnvironmentsFile = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\environments.json'
    $envsFile = (Get-Content $EnvironmentsFile) | ConvertFrom-Json

    $github = (Get-ActionContext)
    $environmentsJSon = ''

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
                $orTime = $(git log -1 --format=%ct "origin/$($_.settings.sourceBranch)")
            }
            catch {
                $orTime = $(git log -1 --format=%ct "$($_.settings.sourceBranch)")
            }
            try {

                Convert-FSCPSTextToAscii -Text "Environment = $($_.Name)." -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2 -Timestamp
                $check = $true
                if($github.EventName -eq "schedule")
                {
                     $check = Test-CronExpression -Expression $_.settings.cron -DateTime ([DateTime]::Now) -WithDelayMinutes 29
                     OutputInfo "Schedule time: $check"
                }
                if($check)
                {                
                    if($settings.deployOnlyNew)
                    {
                        [DateTime]$lastCommitedDate = ((Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($orTime))).ToUniversalTime()
                        OutputInfo "Latest branch commit at: $($lastCommitedDate)"
                        $lddDate = Get-LatestDeployedDate -token $token -environmentName $_.Name -repoName "$($github.Payload.repository.name)"
                        if($lddDate -eq "")
                        {
                            [DateTime]$deployedDate = $(Get-Date -Date "01-01-1970").ToUniversalTime()
                        }
                        else {
                            [DateTime]$deployedDate = $(Get-Date ($lddDate)).ToUniversalTime()
                        }
                        
                        OutputInfo "Latest deployed commit at: $($deployedDate)"
                        if((New-TimeSpan -Start $($deployedDate) -End $($lastCommitedDate)).Ticks -gt 0)
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
                }

                OutputInfo "Deploy: $check"
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
                #$check = $_.settings.deploy
            }
            if($check)
            {                
                if($settings.deployOnlyNew)
                {
                    try {
                        $orTime = $(git log -1 --format=%ct "origin/$($_.settings.sourceBranch)")
                    }
                    catch {
                        $orTime = $(git log -1 --format=%ct "$($_.settings.sourceBranch)")
                    }
                    try {
                        [DateTime]$lastCommitedDate = ((Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($orTime))).ToUniversalTime()
                        [DateTime]$deployedDate = $(Get-Date (Get-LatestDeployedDate -token $token -environmentName $_.Name -repoName "$($github.Payload.repository.name)")).ToUniversalTime()
                        if((New-TimeSpan -Start $($deployedDate) -End $($lastCommitedDate)).Ticks -gt 0)
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
                        $check = $false
                        #OutputInfo -message "Environment history check issue: $($_.Exception.Message)"
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
        Write-Host "Envs: $environments"
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
        $settings.EcommerceMicrosoftRepoBranch = $ver.EcommerceMicrosoftRepoBranch
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

    $gitHubRunner = $settings.githubRunner.Trim().Split(',') | ConvertTo-Json -compress
    Add-Content -Path $env:GITHUB_OUTPUT -Value "GitHubRunner=$githubRunner"

    $runsOn = $settings.'runs-on'.Trim().Split(',') | ConvertTo-Json -compress
    Add-Content -Path $env:GITHUB_OUTPUT -Value "RunsOn=$runsOn"

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


    if($workflowName -eq "(DEPLOY)")
    {
        if($settings.type -eq "Commerce" -and $github.Job -eq "Initialization")
        {
            function GetEnvironment {
                param(
                    [string]$envName
                )
                begin
                {
                    $envsJson = (Get-Content (Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\environments.json')) | ConvertFrom-Json
                }
                process{
                    @($envsJson | ForEach-Object { 
                        if($_.name -eq $envName) 
                        {
                            return $_
                        }
                    })
                }
                
            }
            Import-Module (Join-Path $PSScriptRoot "..\Helpers\ReadSecretsHelper.psm1")
            $selectedEnvironments = $environmentsJson | ConvertFrom-Json
            $startEnvironments = @()
            try {
                $azClientSecret = GetSecret -secret "AZ_CLIENTSECRET"
                if(!$azClientSecret){throw "GitHub secret AZ_CLIENTSECRET not found. Please, create it."}

                if($dynamicsEnvironment -and $dynamicsEnvironment -ne "*")
                {
                    $selectedEnvironments | ForEach-Object { 
                        $sEnv = GetEnvironment -envName $_
                        $dEnvCount = $dynamicsEnvironment.Split(",").Count
                        if($dEnvCount -gt 1)
                        {
                            foreach ($dName in $dynamicsEnvironment.Split(",")) 
                            {
                                if($sEnv.settings.azVmname -eq $dName)
                                {
                                    $PowerState = Check-AzureVMState -VMName $sEnv.settings.azVmname -VMGroup $sEnv.settings.azVmrg -ClientId "$($settings.azClientId)" -ClientSecret "$azClientSecret" -TenantId $($settings.azTenantId)
                                    if($PowerState -ne "running")
                                    {
                                        $startEnvironments += $sEnv.settings.azVmname
                                    }
                                }
                            }
                        }
                        else 
                        {
                            if($sEnv.name -eq $dynamicsEnvironment)
                            {
                                $PowerState = Check-AzureVMState -VMName $sEnv.settings.azVmname -VMGroup $sEnv.settings.azVmrg -ClientId "$($settings.azClientId)" -ClientSecret "$azClientSecret" -TenantId $($settings.azTenantId)
                                OutputInfo -message "Environment check: $($sEnv.settings.azVmname) $PowerState"
                                if($PowerState -ne "running")
                                {
                                    $startEnvironments += $sEnv.settings.azVmname
                                }
                            }
                        }
                    }
                }
                else {
                    $selectedEnvironments | ForEach-Object { 
                        $sEnv = GetEnvironment -envName $_
                        $PowerState = Check-AzureVMState -VMName $sEnv.settings.azVmname -VMGroup $sEnv.settings.azVmrg -ClientId "$($settings.azClientId)" -ClientSecret "$azClientSecret" -TenantId $($settings.azTenantId)
                        if($PowerState -ne "running")
                        {
                            $startEnvironments += $sEnv.settings.azVmname
                        }
                    }                   
                }

                Write-Host "Envs to start: $startEnvironments"
                if($startEnvironments.Count -eq 1)
                {
                    $startEnvironmentsJson = '["'+$($startEnvironments[0]).ToString()+'"]'
                }
                else
                {
                    $startEnvironmentsJson = $startEnvironments | ConvertTo-Json -compress
                }
                $startEnvironmentsJson
                if($environmentsJSon)
                {
                    Add-Content -Path $env:GITHUB_OUTPUT -Value "StartEnvironments=$startEnvironmentsJson"
                    Add-Content -Path $env:GITHUB_ENV -Value "StartEnvironments=$startEnvironmentsJson"
                }
            }
            catch {
                OutputWarning $_.Exception.Message
            }
        }
    }
    $settings = Get-FSCPSSettings -SettingsJsonString ($settings | ConvertTo-Json) -OutputAsHashtable
}
catch {
    Write-Error $_.Exception.Message
    exit
}
finally {
}
