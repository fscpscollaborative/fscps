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
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSCM-PS-Helper.ps1" -Resolve)

    $github = (Get-ActionContext)
        Write-Host ($github | ConvertTo-Json)
       #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    OutputInfo "======================================== Use settings and secrets"

    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable | ConvertTo-OrderedDictionary

    #$settings = $settingsJson | ConvertFrom-Json 
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable

    $settingsHash = $settings #| ConvertTo-HashTable
    'nugetFeedPasswordSecretName','nugetFeedUserSecretName','lcsUsernameSecretname','lcsPasswordSecretname','azClientsecretSecretname','repoTokenSecretName' | ForEach-Object {
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

    $versions = Get-Versions

    $settings

    Write-Output "::endgroup::"


    #Cleanup failed/skiped workflow runs
    if($github.EventName -eq "schedule" -and $github.Workflow -match "DEPLOY" -and $remove)
    {
        #Cleanup failed/skiped workflow runs
        $githubRepository = $github.Repo
        $uriBase = "https://api.github.com"
        $baseHeader =  @{"Authorization" = "token $($repoTokenSecretName)"} 

        $runsActiveParams = @{
            Uri     = ("{0}/repos/{1}/actions/runs" -f $uriBase , $githubRepository)
            Method  = "Get"
            Headers = $baseHeader
        }
        Write-Host ($runsActiveParams | ConvertTo-Json)
        $runsActive = Invoke-RestMethod @runsActiveParams
        $actionsFailure = $runsActive.workflow_runs
        [array]$baseURIJobs = @()
        foreach ($actionFail in $actionsFailure) 
        {
            if($github.RunId -eq $actionFail.id)
            {
                continue;
            
            }
            #$timeDiff = NEW-TIMESPAN -Start $actionFail.run_started_at -End $actionFail.updated_at
            #if($timeDiff.TotalSeconds -le 120)
            #{
                if($actionFail.display_title -match "DEPLOY" -and ($actionFail.status -eq "completed"))
                {
                    #$actionFail
                    Write-Host "Found job $($actionFail.display_title)"
                    $baseURIJobs += ("/repos/{0}/actions/runs/{1}" -f $githubRepository, $actionFail.id)
                }
            #}
        }
        foreach ($baseURIJob in $baseURIJobs) {
            $delete = $false
            $getJobsParam = @{
                Uri     = ( "{0}{1}/jobs" -f $uriBase, $baseURIJob )
                Method  = "Get"
                Headers = $baseHeader
            } 

            $jobs = Invoke-RestMethod @getJobsParam
            foreach($job in $jobs.jobs){
                if($job.conclusion -eq "skipped"){$delete = $true}
            }

            $runsDeleteParam = @{
                Uri     = ( "{0}{1}" -f $uriBase, $baseURIJob )
                Method  = "Delete"
                Headers = $baseHeader
            } 
            if($delete)
            {
                Write-Host "Delete job $(($runsDeleteParam.Uri -split "/")[8])"
                Invoke-RestMethod @runsDeleteParam
            }
        }

    }

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
