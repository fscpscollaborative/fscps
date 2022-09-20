Param(
    [Parameter(HelpMessage = "Remove current run", Mandatory = $false)]
    [switch] $remove,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSCM-PS-Helper.ps1" -Resolve)

    $github = (Get-ActionContext)
        Write-Host ($github | ConvertTo-Json)
    Write-Host "EventName: " $github.EventName "; WorkflowName: " $github.Workflow "Contains: " ($github.Workflow -match "DEPLOY") "; Remove: " $remove


    if($github.EventName -eq "schedule" -and $github.Workflow -match "DEPLOY" -and $remove)
    {
        #Cleanup failed/skiped workflow runs
        $githubRepository = $github.Repo
        $uriBase = "https://api.github.com"
        $baseHeader =  @{"Authorization" = "token $($token)"} 

        $runsActiveParams = @{
            Uri     = ("{0}/repos/{1}/actions/runs" -f $uriBase , $githubRepository)
            Method  = "Get"
            Headers = $baseHeader
        }
        $runsActive = Invoke-RestMethod @runsActiveParams
        $actionsFailure = $runsActive.workflow_runs
        [array]$baseURIJobs = @()
        foreach ($actionFail in $actionsFailure) 
        {
            if($github.RunId -eq $actionFail.id)
            {
                continue;
            }
            $timeDiff = NEW-TIMESPAN –Start $actionFail.run_started_at –End $actionFail.updated_at
            if($timeDiff.TotalSeconds -le 45)
            {
                Write-Host "Found job $($actionFail.display_title)"
                $baseURIJobs += ("/repos/{0}/actions/runs/{1}" -f $githubRepository, $actionFail.id)
            }
        }
        foreach ($baseURIJob in $baseURIJobs) {
            $runsDeleteParam = @{
                Uri     = ( "{0}{1}" -f $uriBase, $baseURIJob )
                Method  = "Delete"
                Headers = $baseHeader
            } 
            Write-Host "Delete job $(($runsDeleteParam.Uri -split "/")[8])"
            Invoke-RestMethod @runsDeleteParam
        }

    }


}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
