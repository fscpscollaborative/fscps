Param(
    [Parameter(HelpMessage = "Remove current run", Mandatory = $false)]
    [switch] $remove,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = ''
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)

    $github = (Get-ActionContext)
    Write-Host ($github | ConvertTo-Json)
    #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    OutputInfo "======================================== Use settings and secrets"

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

    Write-Output "::endgroup::"

    #Cleanup workflow runs
    if($github.EventName -eq "schedule")
    {
        #Cleanup failed/skiped workflow runs
        $githubRepository = $github.Repo
        $uriBase = "https://api.github.com"
        $baseHeader =  @{"Authorization" = "token $($repoTokenSecretName)"} 

        $runsActiveParams = @{
            Uri     = ("{0}/repos/{1}/actions/runs?per_page=100" -f $uriBase , $githubRepository)
            Method  = "Get"
            Headers = $baseHeader
        }
        Write-Host ($runsActiveParams | ConvertTo-Json)
        $runsActive = Invoke-RestMethod @runsActiveParams
        $actions = $runsActive.workflow_runs
        [array]$deleteRuns = @()

        foreach ($action in $actions) {
            try {
                $del = $false
                #if run older than 7 days - delete
                $retentionHours = (7 * 24)
                $timeSpan = NEW-TIMESPAN -Start $action.created_at -End (Get-Date).ToString()
                if ($timeSpan.TotalHours -gt $retentionHours) {
                    $del = $true
                }
                #if it`s a clean deploy run - delete
           
                if($action.display_title -match "DEPLOY" -and ($action.status -eq "completed"))
                {
                    $getJobsParam = @{
                        Uri     = $action.jobs_url
                        Method  = "Get"
                        Headers = $baseHeader
                    } 
                    #Delete skipped actions
                    $jobs = Invoke-RestMethod @getJobsParam
                    foreach($job in $jobs.jobs){            
                        if($($job.name.StartsWith("Deploy")) -and $($job.conclusion -eq "skipped")){$del = $true}
                    }
                }
            
                if($del)
                {
                    Write-Host "Found job $($action.display_title)"
                    $deleteRuns += $action
                }
            }
            catch {
                <#Do this if a terminating exception happens#>
            }
           
        }
        foreach ($action in $deleteRuns) {
            try {
                $runsDeleteParam = @{
                    Uri     = $action.url
                    Method  = "Delete"
                    Headers = $baseHeader
                } 
                Write-Host "Delete job $(($runsDeleteParam.Uri -split "/")[8])"
                Invoke-RestMethod @runsDeleteParam
            }
            catch {
                <#Do this if a terminating exception happens#>
            }

        }
    }
    #Cleanup workspace folder
    $baseFolder = $ENV:GITHUB_WORKSPACE
    Remove-Item "$baseFolder/*" -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
