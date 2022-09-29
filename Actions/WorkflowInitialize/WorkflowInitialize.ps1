Param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
. (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)
# IMPORTANT: No code that can fail should be outside the try/catch
try {

    $github = (Get-ActionContext)
    Write-Host ($github | ConvertTo-Json)

    $ap = "$ENV:GITHUB_ACTION_PATH".Split('\')
    $branch = $ap[$ap.Count-2]
    $owner = $ap[$ap.Count-4]

    if ($owner -ne "microsoft") {
        $verstr = "d"
    }
    elseif ($branch -eq "preview") {
        $verstr = "p"
    }
    else {
        $verstr = $branch
    }

    Write-Big -str "a$verstr"

    #Test-ALGoRepository -baseFolder $ENV:GITHUB_WORKSPACE
    $Az = Get-InstalledModule -Name AZ -ErrorAction SilentlyContinue
    $DfoTools = Get-InstalledModule -Name d365fo.tools -ErrorAction SilentlyContinue

    if([string]::IsNullOrEmpty($Az))
    {
        Install-Module -Name AZ -AllowClobber -Scope CurrentUser -Force -Confirm:$False -SkipPublisherCheck
    }
    if([string]::IsNullOrEmpty($DfoTools))
    {
        Install-Module -Name d365fo.tools -AllowClobber -Scope CurrentUser -Force -Confirm:$false
    }
}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
