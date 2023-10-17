Param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch
try {
    Import-Module (Join-Path $PSScriptRoot "..\FSC-PS-Helper.ps1")
    Import-Module (Join-Path $PSScriptRoot "..\Helpers\ReadSecretsHelper.psm1")
    $github = (Get-ActionContext)
    Write-Host ($github | ConvertTo-Json)

    $ap = "$ENV:GITHUB_ACTION_PATH".Split('\')
    $branch = $ap[$ap.Count-2]

    Install-Module -Name PSSodium -Force
    Write-Big -str "$branch"

    #Load REPO_TOKEN secret from github
    $github = (Get-ActionContext)
    try {
        $ghToken = GetSecret -secret "REPO_TOKEN"
        if(!$ghToken){throw "GitHub secret REPO_TOKEN not found. Please, create it."}
    }
    catch {
        Write-Warning $_.Exception.Message
    }

    #Test-ALGoRepository -baseFolder $ENV:GITHUB_WORKSPACE
    #installModules @("AZ.Storage","d365fo.tools")
}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
