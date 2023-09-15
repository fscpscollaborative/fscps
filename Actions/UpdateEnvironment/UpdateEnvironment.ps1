Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '',
    [Parameter(HelpMessage = "targetVersion", Mandatory = $false)]
    [string] $targetVersion = '',
    [Parameter(HelpMessage = "updatePackageType", Mandatory = $false)]
    [string] $updatePackageType = '',
    [Parameter(HelpMessage = "environmentName", Mandatory = $false)]
    [string] $environmentName = '',
    [Parameter(HelpMessage = "skipWaiting", Mandatory = $false)]
    [string] $skipWaiting = '',
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

    $EnvironmentsFile = Join-Path $baseFolder '.FSC-PS\environments.json'
    $environments = @((Get-Content $EnvironmentsFile) | ConvertFrom-Json | ForEach-Object {$_.Name})

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

    $versions = Get-Versions

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

    # Clone URL
    invoke-git clone $url 
    $archivePath = "$baseFolder\temp.zip"
    Invoke-WebRequest -Uri $artifactsPath -OutFile $archivePath
    Set-Location -Path $baseFolder
    Import-D365FSCSource -archivePath $archivePath -targetPath $baseFolder

    Remove-Item $archivePath -Force

    invoke-git status

    invoke-git add *
    $message = "DevOps - import source code"

    invoke-git commit --allow-empty -m "'$message'"

    invoke-git push $url

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    OutputInfo "Execution is done."
}
