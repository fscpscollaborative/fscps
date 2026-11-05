#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [uri] $DataverseUrl,
    [Security.SecureString] $AccessToken,
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string] $AppBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'FinOps-NuGet.ps1')

$session = Get-FinOpsSession $DataverseUrl $AccessToken
$correlationId = $session.Headers.CorrelationId
Write-Information "Checking Developer Tools access. CorrelationId: $correlationId" -InformationAction Continue
$releases = @(Get-FinOpsRelease $session)
if (-not $AppBuild) {
    $latestRelease = $releases | Select-Object -Last 1
    $AppBuild = Get-FinOpsBuild $session $latestRelease.appBuild | Select-Object -Last 1
}
$platformBuild = Get-FinOpsPlatformBuild $session $AppBuild
foreach ($packageName in Get-FinOpsPackageName) {
    $link = Get-FinOpsPackageLink $session $packageName $AppBuild
    $size = Invoke-FinOpsBlob -Uri $link -PackageName $packageName
    [pscustomobject]@{
        PackageName = $packageName
        AppBuild = $AppBuild
        PlatformBuild = $platformBuild
        SizeBytes = $size
        BlobAccessible = $true
        CorrelationId = $correlationId
    }
}
