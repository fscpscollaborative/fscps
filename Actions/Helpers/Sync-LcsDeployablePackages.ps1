#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ProjectId = $env:LCS_PROJECT_ID,
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string] $StorageAccount = 'ciellosarchive',
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$')]
    [string] $Container = 'deployablepackages',
    [string] $VersionsPath = (Join-Path $PSScriptRoot 'versions.default.json'),
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $MinimumVersion = '10.0.39',
    [switch] $ListOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'LCS-Api.ps1')
. (Join-Path $PSScriptRoot 'FinOps-Sync.ps1')

$VersionsPath = [IO.Path]::GetFullPath($VersionsPath)
$originalJson = Get-Content -LiteralPath $VersionsPath -Raw
$versions = @($originalJson | ConvertFrom-Json -AsHashtable)
if ($versions.Count -eq 0) { throw 'The versions file is empty.' }

$token = Get-LcsAccessToken -ClientId $env:LCS_CLIENT_ID -UserName $env:LCS_USERNAME -Password $env:LCS_USER_PASSWORD
$assets = @(Get-LcsSharedAsset -Token $token -FileType 10)
$selection = Get-LcsSdpSelection -Assets $assets -MinimumExclusive ([version]$MinimumVersion)
if ($selection.Count -eq 0) { throw 'No deployable packages matched; refusing to continue with an empty selection.' }

# Several selected roles can point to the same asset; publish each asset once under its LCS name.
$required = @{}
foreach ($record in $selection.Values) {
    foreach ($entry in $record.Service, $record.Preview, $record.Latest, $record.Final) {
        if (-not $entry) { continue }
        if ($required.ContainsKey($entry.Name) -and $required[$entry.Name].Id -ne $entry.Id) {
            throw "Two different selected assets share the name '$($entry.Name)'; cannot publish them under one blob name."
        }
        $required[$entry.Name] = $entry
    }
}
$ordered = @($required.Values | Sort-Object { [version]$_.Version }, { $_.Name })

if ($ListOnly) {
    foreach ($entry in $ordered) { [pscustomobject]@{ Release = $entry.Version; Package = $entry.Name; Created = $entry.Created; Action = 'Planned' } }
    return
}

if ($ProjectId -notmatch '^\d+$') { throw 'LCS_PROJECT_ID must be numeric.' }
$storage = @('--account-name', $StorageAccount, '--container-name', $Container)
if (-not $env:AZURE_STORAGE_SAS_TOKEN) { $storage += @('--auth-mode', 'login') }
$workDirectory = Join-Path ([IO.Path]::GetTempPath()) "fscps-sdp-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $workDirectory
try {
    foreach ($entry in $ordered) {
        $exists = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'exists', '--name', $entry.Name) + $storage)
        if ($exists.exists -isnot [bool]) { throw "Invalid storage existence response for '$($entry.Name)'." }
        if ($exists.exists) {
            $blob = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'show', '--name', $entry.Name) + $storage)
            $metadata = $blob.metadata
            $current = $false
            if ($metadata -and $metadata.Contains('lcsassetid')) { $current = ($metadata.lcsassetid -eq $entry.Id) }
            elseif ($blob.properties.lastModified) {
                # Blobs from the legacy pipeline carry no metadata: trust them only if uploaded after the asset was created.
                $current = ([datetimeoffset]::Parse([string]$blob.properties.lastModified, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime -gt $entry.Created)
            }
            if ($current -and [long]$blob.properties.contentLength -gt 0) {
                [pscustomobject]@{ Release = $entry.Version; Package = $entry.Name; Created = $entry.Created; Action = 'Present' }
                continue
            }
        }

        $path = Join-Path $workDirectory "$([guid]::NewGuid().ToString('N')).bin"
        try {
            $freeBytes = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($workDirectory))).AvailableFreeSpace
            if ($entry.Size -gt 0 -and $freeBytes -lt ($entry.Size * 1.2)) {
                throw "Not enough free disk space to download '$($entry.Name)'."
            }
            $link = Get-LcsAssetDownloadUri -Token $token -ProjectId $ProjectId -AssetId $entry.Id
            try {
                # Never forward the LCS token to blob storage or log the SAS URL.
                $response = Invoke-WebRequest -Uri $link -OutFile $path -PassThru -TimeoutSec 7200 -MaximumRedirection 0 -SkipHttpErrorCheck
            }
            catch { throw "Download failed for '$($entry.Name)' (transport or redirect). The SAS URL was not logged." }
            if ([int]$response.StatusCode -ne 200) { throw "Download returned HTTP $([int]$response.StatusCode) for '$($entry.Name)'." }
            $length = (Get-Item -LiteralPath $path).Length
            $expected = 0L
            if (-not [long]::TryParse([string]($response.Headers['Content-Length'] -join ''), [ref]$expected) -or $expected -le 0 -or $length -ne $expected) {
                throw "Downloaded size does not match Content-Length for '$($entry.Name)'."
            }
            if ($entry.Size -gt 0 -and $length -ne $entry.Size) {
                throw "Downloaded size does not match the LCS asset size for '$($entry.Name)'."
            }
            $null = Invoke-FinOpsAzure -Arguments (@(
                'storage', 'blob', 'upload', '--name', $entry.Name, '--file', $path,
                '--overwrite', 'true', '--tier', 'Hot', '--metadata', "lcsassetid=$($entry.Id)"
            ) + $storage)
            $published = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'show', '--name', $entry.Name) + $storage)
            if ([long]$published.properties.contentLength -ne $length -or $published.metadata.lcsassetid -ne $entry.Id) {
                throw "Publication verification failed for '$($entry.Name)'."
            }
            [pscustomobject]@{ Release = $entry.Version; Package = $entry.Name; Created = $entry.Created; Action = 'Published' }
        }
        finally {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }

    foreach ($record in $selection.Values) {
        Update-LcsSdpVersionRecord -Versions ([ref]$versions) -Selection $record
    }
    $sorted = @($versions | Sort-Object { [version]$_.version })
    $json = ConvertTo-Json -InputObject $sorted -Depth 20
    $before = ConvertTo-Json -InputObject @($originalJson | ConvertFrom-Json -AsHashtable) -Depth 20 -Compress
    $after = ConvertTo-Json -InputObject $sorted -Depth 20 -Compress
    if ($before -cne $after) {
        $temporaryVersions = Join-Path (Split-Path -Parent $VersionsPath) "versions.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            Set-Content -LiteralPath $temporaryVersions -Value $json -Encoding utf8
            Move-Item -LiteralPath $temporaryVersions -Destination $VersionsPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryVersions) { Remove-Item -LiteralPath $temporaryVersions -Force }
        }
    }
}
finally {
    Remove-Item -LiteralPath $workDirectory -Recurse -Force
}
