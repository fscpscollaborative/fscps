Param(
    [Parameter(HelpMessage = "DynamicsVersion", Mandatory = $true)]
    [string] $DynamicsVersion,
    [Parameter(HelpMessage = "PackagesDirectory", Mandatory = $true)]
    [string] $PackagesDirectory
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
# IMPORTANT: No code that can fail should be outside the try/catch

try {
    $helperPath = Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve
    . $helperPath

    installModules @("fscps.tools", "fscps.ascii")

    Convert-FSCPSTextToAscii -Text "Gather version info" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
    $versionData = Get-FSCPSVersionInfo -Version $DynamicsVersion
    $PlatformVersion = $versionData.data.PlatformVersion
    $ApplicationVersion = $versionData.data.AppVersion

    Convert-FSCPSTextToAscii -Text "Download NuGet packages" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
    Get-FSCPSNuget -Version $PlatformVersion -Type PlatformCompilerPackage -Path $PackagesDirectory -Force
    Get-FSCPSNuget -Version $PlatformVersion -Type PlatformDevALM -Path $PackagesDirectory
    Get-FSCPSNuget -Version $ApplicationVersion -Type ApplicationDevALM -Path $PackagesDirectory
    Get-FSCPSNuget -Version $ApplicationVersion -Type ApplicationSuiteDevALM -Path $PackagesDirectory

    Convert-FSCPSTextToAscii -Text "Nuget install packages" -Font "Term" -BorderType DoubleDots -HorizontalLayout ControlledSmushing -ScreenWigth 110 -Padding 2
    $PackagesDirectoryFullPath = Get-Item -Path $PackagesDirectory
    GeneratePackagesConfig -DynamicsVersion $DynamicsVersion -NugetFeedName "local" -NugetSourcePath $PackagesDirectoryFullPath.FullName
    Set-Location NewBuild

    nuget restore -PackagesDirectory $PackagesDirectory
}
catch {
  OutputError -message $_.Exception.Message
}
finally
{
  OutputInfo "Execution is done."
}