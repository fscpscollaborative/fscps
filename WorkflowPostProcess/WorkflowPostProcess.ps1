Param(
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSCM-PS-Helper.ps1" -Resolve)


    $githubUser = 'youruser'
    $githubRepository = 'yourRepo'
    $uriBase = "https://api.github.com"
    $baseHeader =  @{"Authorization" = "token $(Get-Secret -Name KeyGitHub -AsPlainText)" ; "Content-Type" = "application/json" } 
    $runsActiveParams = @{
        Uri     = ("{0}/repos/{1}/{2}/actions/runs" -f $uriBase ,$githubUser, $githubRepository)
        Method  = "Get"
        Headers = $baseHeader
    }
    $runsActive = Invoke-RestMethod @runsActiveParams
    $actionsFailure = $runsActive.workflow_runs | Where-Object { ($_.conclusion -eq "failure")}
    [array]$baseURIJobs = @()
    foreach ($actionFail in $actionsFailure.id) {
        $baseURIJobs += ("/repos/{0}/{1}/actions/runs/{2}" -f $githubUser, $githubRepository, $actionFail)
    }
    foreach ($baseURIJob in $baseURIJobs) {
        $runsDeleteParam = @{
            Uri     = ( "{0}{1}" -f $uriBase,$baseURIJob )
            Method  = "Delete"
            Headers = $baseHeader
        }
        Write-Host "Delete job $(($runsDeleteParam.Uri -split "/")[8])"
        Invoke-RestMethod @runsDeleteParam
    }



}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
