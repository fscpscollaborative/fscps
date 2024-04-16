Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '',
    [Parameter(HelpMessage = "artifactsPath", Mandatory = $false)]
    [string] $artifactsPath = '',
    [Parameter(HelpMessage = "The environment type FSCM/Commerce", Mandatory = $false)]
    [string] $type = "FSCM"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)
    $workflowName = $env:GITHUB_WORKFLOW
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $github = (Get-ActionContext)

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
    
    $settings.buildVersion

    if($settings.sourceBranch -eq "")
    {
        $settings.sourceBranch = $settings.currentBranch
    }

    #SourceBranchToPascakCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    $buildPath = Join-Path "C:\Temp" $settings.buildPath
    Write-Output "::endgroup::"

    # Environment variables for hub commands
    $env:GITHUB_USER = $actor
    $env:GITHUB_TOKEN = $token
    $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
    $url = "$($serverUri.Scheme)://$($actor):$($token)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"
    # Configure git username and email
    invoke-git config --global user.email "$actor@users.noreply.github.com"
    invoke-git config --global user.name "$actor"

    # Configure hub to use https
    invoke-git config --global hub.protocol https
    invoke-git config --global core.autocrlf true

    # Clone URL
    # invoke-git clone $url 
    $archivePath = "$baseFolder\temp.zip"
    Invoke-WebRequest -Uri $artifactsPath -OutFile $archivePath
    Unblock-File -Path $archivePath
    Set-Location -Path $baseFolder

    $branch = [System.IO.Path]::GetRandomFileName()
    invoke-git checkout -b $branch $($env:GITHUB_REF_NAME)

    Update-D365FSCISVSource -archivePath $archivePath -targetPath $baseFolder
    Get-ChildItem $baseFolder

    Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    Remove-Item /$github.Payload.repository.name -Force -ErrorAction SilentlyContinue

    Get-ChildItem $baseFolder
    invoke-git status
    invoke-git add *
    $message = "DevOps - update ISV models"
    invoke-git commit --allow-empty -m "'$message'"
    invoke-git push -u origin $branch
    Write-Output "Create PR to the $($env:GITHUB_REF_NAME)"
    invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY --base $env:GITHUB_REF_NAME

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    OutputInfo "Execution is done."
}
