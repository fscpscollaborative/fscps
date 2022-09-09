Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "DynamicsVersion", Mandatory = $false)]
    [string] $DynamicsVersion,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"AppBuild":"", "AppRevision":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePassword":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePassword":"","KeyVaultClientId":"","StorageContext":"","ApplicationInsightsConnectionString":""}'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FnSCM-Go-Helper.ps1" -Resolve)

  
    $runAlPipelineParams = @{}
    $project = "" 
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $ENV:GITHUB_WORKSPACE
    }
    $workflowName = $env:GITHUB_WORKFLOW

    Write-Host "use settings and secrets"
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    $secrets | ForEach-Object {
        if ($secrets.ContainsKey($_)) {
            $value = $secrets."$_"
        }
        else {
            $value = ""
        }
        Write-Host "Create local Secret variable: " $_
        Set-Variable -Name $_ -Value $value
    }

    #Generate solution folder
    Write-Host "========Generate solution folder"
    GenerateSolution -ModelName $settings.models -NugetFeedName $settings.nugetFeedName -NugetSourcePath $settings.nugetSourcePath -DynamicsVersion $DynamicsVersion

    Write-Host "========Cleanup Build folder"
    #Cleanup Build folder
    Remove-Item $settings.buildPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "========Copy branch files"
    #Copy branch files
    New-Item -ItemType Directory -Force -Path $settings.buildPath; Copy-Item $ENV:GITHUB_WORKSPACE\* -Destination $settings.buildPath -Recurse -Force

    Write-Host "========Copy solution folder"
    #Copy solution folder
    Copy-Item NewBuild -Destination $settings.buildPath

    Write-Host "========Cleanup NuGet"
    #Cleanup NuGet
    nuget sources remove -Name $settings.nugetFeedName -Source $settings.nugetSourcePath

    Write-Host "========Nuget add source"
    #Nuget add source
    nuget sources Add -Name $settings.nugetFeedName -Source $settings.nugetSourcePath -username $secrets.AF_CONNECTORS_CICD_USER -password $secrets.AF_CONNECTORS_CICD_PASS
   


    Write-Host "Found packages.config file" $settings.buildPath\NewBuild\packages.config
    Write-Host "========Nuget install packages"
    #Nuget install packages
    nuget restore $settings.buildPath\NewBuild\packages.config -PackagesDirectory $settings.buildPath\NuGets





}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
