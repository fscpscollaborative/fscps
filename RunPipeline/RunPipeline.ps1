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
        Set-Variable -Name $_ -Value $value
    }

    #Generate solution folder
    GenerateSolution -ModelName $settings.models -NugetFeedName $settings.nugetFeedName -NugetSourcePath $settings.nugetSourcePath -DynamicsVersion $DynamicsVersion


    #Cleanup Build folder
    Remove-Item ${{ env.build_path }} -Recurse -Force

    #Copy branch files
    New-Item -ItemType Directory -Force -Path $settings.buildPath; Copy-Item ${{ github.workspace }}\* -Destination $settings.buildPath -Recurse -Force

    #Copy solution folder
    Copy-Item ..\NewBuild -Destination $settings.buildPath

    #Cleanup NuGet
    nuget sources remove -Name $settings.nugetFeedName -Source $settings.nugetSourcePath

    #Nuget add source
    nuget sources Add -Name $settings.nugetFeedName -Source $settings.nugetSourcePath -username $AF_CONNECTORS_CICD_USER -password $AF_CONNECTORS_CICD_PASS
   
    #Nuget install packages
    nuget restore $settings.buildPath\NewBuild\${{ env.fno_version }}\packages.config -PackagesDirectory $settings.buildPath\NuGets





}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
