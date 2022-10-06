Param(

    [Parameter(HelpMessage = "Settings from template repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = ''
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)

    Import-Module (Join-Path $PSScriptRoot ".\ReadSecretsHelper.psm1")

    $outSecrets = [ordered]@{}
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $outSettings = $settings


    #Load secrets from github
    $ghToken = GetSecret -secret "REPO_TOKEN"
    Add-Content -Path $env:GITHUB_ENV -Value "GH_TOKEN=$ghToken"
    "GH_TOKEN=$ghToken" >> $env:GITHUB_ENV

    $github = (Get-ActionContext)
    $ghSecrets = (invoke-gh secret list --repo "$($github.Repo)") | ForEach-Object { $_.ToString().Substring(0, $($_.ToString().Length - 11)).Trim()}


    $secrets = $settings.githubSecrets

    [System.Collections.ArrayList]$secretsCollection = @()
    $secrets.Split(',') | ForEach-Object {
        $secret = $_
        $secretNameProperty = "$($secret)SecretName"
        if ($settings.containsKey($secretNameProperty)) {
            $secret = "$($secret)=$($settings."$secretNameProperty")"
        }
        $secretsCollection += $secret
    }

    @($secretsCollection) | ForEach-Object {
        $secretSplit = $_.Split('=')
        $envVar = $secretSplit[0]
        $secret = $envVar
        if ($secretSplit.Count -gt 1) {
            $secret = $secretSplit[1]
        }

        if ($secret) {
            $value = GetSecret -secret $secret 
            if ($value) {
                Add-Content -Path $env:GITHUB_ENV -Value "$envVar=$value"
                $outSecrets += @{ "$envVar" = $value }
                Write-Host "$envVar successfully read from secret $secret"
                $secretsCollection.Remove($_)
            }
        }
    }

    if ($outSettings.ContainsKey('appDependencyProbingPaths')) {
        $outSettings.appDependencyProbingPaths | ForEach-Object {
            if ($_.PsObject.Properties.name -eq "AuthTokenSecret") {
                $_.authTokenSecret = GetSecret -secret $_.authTokenSecret -keyVaultName $keyVaultName
            } 
        }
    }

    if ($secretsCollection) {
        Write-Host "The following secrets was not found: $(($secretsCollection | ForEach-Object { 
            $secretSplit = @($_.Split('='))
            if ($secretSplit.Count -eq 1) {
                $secretSplit[0]
            }
            else {
                "$($secretSplit[0]) (Secret $($secretSplit[1]))"
            }
            $outSecrets += @{ ""$($secretSplit[0])"" = """" }
        }) -join ', ')"
    }

    $outSecretsJson = $outSecrets | ConvertTo-Json -Compress
    Add-Content -Path $env:GITHUB_ENV -Value "RepoSecrets=$outSecretsJson"

    $outSettingsJson = $outSettings | ConvertTo-Json -Compress
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"

}
catch {
    OutputError -message $_.Exception.Message
    exit
}
finally {

}
