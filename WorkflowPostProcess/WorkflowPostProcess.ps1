Param(
    [Parameter(HelpMessage = "Remove current run", Mandatory = $false)]
    [switch] $remove
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSCM-PS-Helper.ps1" -Resolve)

    $github = (Get-ActionContext)

    if($github.EventName -eq "schedule" -and $github.Workflow -contains "DEPLOY" -and $remove)
    {
        #Cleanup failed/skiped workflow runs
        $actionToRemove= $github.RunId
        $githubRepository = $github.Repo
        $uriBase = "https://api.github.com"
        $baseHeader =  @{"Authorization" = "token $($Env:GITHUB_TOKEN)" ; "Content-Type" = "application/json" } 

        $baseURIJob = ("/repos/{0}/actions/runs/{1}" -f $githubRepository, $actionToRemove)
        $runsDeleteParam = @{
            Uri     = ( "{0}{1}" -f $uriBase,$baseURIJob )
            Method  = "Delete"
            Headers = $baseHeader
        }
        Invoke-RestMethod @runsDeleteParam
    }


}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
