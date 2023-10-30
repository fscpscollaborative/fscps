Param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch
try {
    Import-Module (Join-Path $PSScriptRoot "..\FSC-PS-Helper.ps1")
    Import-Module (Join-Path $PSScriptRoot "..\Helpers\ReadSecretsHelper.psm1")
    OutputInfo "Getting GitHub Context ..."
    $github = (Get-ActionContext)
    Write-Host ($github | ConvertTo-Json)

    $ap = "$ENV:GITHUB_ACTION_PATH".Split('\')
    $branch = $ap[$ap.Count-2]

    OutputInfo "Installing PSSodium..."
    Install-Module -Name PSSodium -Force

    try {
        Write-Big -str "$branch"
    }
    catch {
        OutputInfo "Write-Big Issue $($_.Exception.Message)"
    }
    

    #Load REPO_TOKEN secret from github
    OutputInfo "Load REPO_TOKEN secret from GitHub..."
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
