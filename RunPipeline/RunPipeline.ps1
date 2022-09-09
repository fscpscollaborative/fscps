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

  

    $VersionsFile = Join-Path $ENV:GITHUB_WORKSPACE '.FnSCM-Go\versions.json'

    $versions = (Get-Content $VersionsFile) | ConvertFrom-Json

    Foreach($version in $versions)
    {
        if($version.version -eq $DynamicsVersion)
        {
            $PlatformVersion = $version.data.PlatformVersion
            $ApplicationVersion = $version.data.AppVersion
        }
    }


    $tools_package =  'Microsoft.Dynamics.AX.Platform.CompilerPackage.' + $PlatformVersion
    $plat_package =  'Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp.' + $PlatformVersion
    $app_package =  'Microsoft.Dynamics.AX.Application.DevALM.BuildXpp.' + $ApplicationVersion
    $appsuite_package =  'Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp.' + $ApplicationVersion


    $runAlPipelineParams = @{}
    $project = "" 
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $ENV:GITHUB_WORKSPACE
    }
    $workflowName = $env:GITHUB_WORKFLOW

    #Use settings and secrets
    Write-Host "======================================== Use settings and secrets"

    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'nugetFeedPasswordSecretName','nugetFeedUserSecretName' | ForEach-Object {
        $setValue = ""
        if($settings.ContainsKey($_))
        {
            $setValue = $settings."$_"
        }
        if ($secrets.ContainsKey($setValue)) {
            $value = $secrets."$setValue"
        }
        else {
            $value = "test"
        }
        Set-Variable -Name $_ -Value $value
    }

    #Generate solution folder
    Write-Host "======================================== Generate solution folder"
    GenerateSolution -ModelName $settings.models -NugetFeedName $settings.nugetFeedName -NugetSourcePath $settings.nugetSourcePath -DynamicsVersion $DynamicsVersion

    Write-Host "======================================== Cleanup Build folder"
    #Cleanup Build folder
    Remove-Item $settings.buildPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "======================================== Copy branch files"
    #Copy branch files
    New-Item -ItemType Directory -Force -Path $settings.buildPath; Copy-Item $ENV:GITHUB_WORKSPACE\* -Destination $settings.buildPath -Recurse -Force

    Write-Host "======================================== Copy solution folder"
    #Copy solution folder
    Copy-Item NewBuild -Destination $settings.buildPath -Recurse -Force

    Write-Host "======================================== Cleanup NuGet"
    #Cleanup NuGet
    nuget sources remove -Name $settings.nugetFeedName -Source $settings.nugetSourcePath

    Write-Host "======================================== Nuget add source"
    #Nuget add source
    nuget sources Add -Name $settings.nugetFeedName -Source $settings.nugetSourcePath -username $nugetFeedUserSecretName -password $nugetFeedPasswordSecretName
   
    $packagesFilePath = Join-Path $settings.buildPath NewBuild\packages.config
    
    Write-Host "======================================== Nuget install packages"

    if(Test-Path $packagesFilePath)
    {
        Write-Host "Found packages.config file at path: " $packagesFilePath
    }
    else
    {
        Write-Host "Not Found packages.config file at path:" $packagesFilePath
    }
    cd $settings.buildPath
    cd NewBuild
    #Nuget install packages
    nuget restore -PackagesDirectory ..\NuGets

    
    #Copy dll`s to build folder
    Write-Host "======================================== Copy dll`s to build folder"
    Copy-Filtered -Source $($settings.buildPath)\$($settings.metadataPath) -Target $($settings.buildPath)\bin -Filter *.dll

    #Build solution
    Write-Host "======================================== Build solution"
    cd $settings.buildPath


    $msBuilsReferences = "$($settings.buildPath)\$($settings.nugetPackagesPath)\$($app_package)\ref\net40%3B$($settings.buildPath)\$($settings.nugetPackagesPath)\$plat_package\ref\net40%3B$($settings.buildPath)\$($settings.nugetPackagesPath)\$appsuite_package\ref\net40%3B$($settings.buildPath)\$($settings.metadataPath)%3B$($settings.buildPath)\bin"
    msbuild NewBuild\Build\Build.sln  `
         /p:BuildTasksDirectory="$($settings.buildPath)\$($settings.nugetPackagesPath)\$tools_package\DevAlm" `
         /p:MetadataDirectory="$($settings.buildPath)\$($settings.metadataPath)" `
         /p:FrameworkDirectory="$($settings.buildPath)\$($settings.nugetPackagesPath)\$tools_package" `
         /p:ReferencePath="$($settings.buildPath)\$($settings.nugetPackagesPath)\$tools_package" `
         /p:OutputDirectory="$($settings.buildPath)\bin" `
         /p:ReferenceFolder="$msBuilsReferences"


}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
