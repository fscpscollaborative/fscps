#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [uri] $DataverseUrl,
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string] $StorageAccount = 'ciellosarchive',
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$')]
    [string] $Container = 'nuget',
    [string] $VersionsPath = (Join-Path $PSScriptRoot 'versions.default.json'),
    [Security.SecureString] $AccessToken,
    [hashtable] $BuildPrefixOverrides = @{},
    [object[]] $AdditionalReleases = @(),
    [switch] $DiscoverNextRelease,
    [ValidateRange(1, 1000)] [int] $DiscoveryPrefixSpan = 400,
    [ValidateRange(1, 32)] [int] $DiscoveryThrottleLimit = 16,
    [switch] $AllBuilds,
    [switch] $ListOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'FinOps-NuGet.ps1')
. (Join-Path $PSScriptRoot 'FinOps-Sync.ps1')

$VersionsPath = [IO.Path]::GetFullPath($VersionsPath)
$versions = @(Get-Content -LiteralPath $VersionsPath -Raw | ConvertFrom-Json -AsHashtable)
if ($versions.Count -eq 0) { throw 'The versions file is empty.' }
$session = Get-FinOpsSession $DataverseUrl $AccessToken
$releases = @(Get-FinOpsRelease $session)
# Preview releases can have downloadable builds before the service lists them in its catalog.
foreach ($extra in $AdditionalReleases) {
    $appVersion = [string]$extra.appVersion
    $appBuild = [string]$extra.appBuild
    $platVersion = [string]$extra.platVersion
    if ($appVersion -notmatch '^\d+\.\d+\.\d+$' -or $appBuild -notmatch '^\d+\.\d+\.\d+$' -or $platVersion -notmatch '^PU\d+$') {
        throw 'AdditionalReleases entries require appVersion (10.0.50), appBuild (10.0.2919) and platVersion (PU74).'
    }
    if ($appVersion -in $releases.appVersion) { continue }
    Write-Warning "Using configured release $appVersion ($appBuild) that is not advertised by the service catalog."
    $releases += [pscustomobject]@{ appVersion = $appVersion; appBuild = $appBuild; platVersion = $platVersion }
}
$releases = @($releases | Sort-Object { [version]$_.appVersion })
if ($DiscoverNextRelease) {
    $last = $releases[-1]
    $next = Find-FinOpsNextRelease -Session $session -LastAppBuild $last.appBuild -LastAppVersion $last.appVersion `
        -LastPlatVersion $last.platVersion -PrefixSpan $DiscoveryPrefixSpan -ThrottleLimit $DiscoveryThrottleLimit
    if ($next) {
        Write-Warning "Discovered unlisted release $($next.appVersion) ($($next.appBuild), $($next.platVersion)) by probing build prefixes."
        $releases += $next
    }
}
$plan = @(
    foreach ($release in $releases) {
        $prefix = $release.appBuild
        if ($BuildPrefixOverrides.ContainsKey($release.appVersion)) {
            $prefix = [string]$BuildPrefixOverrides[$release.appVersion]
            Write-Warning "Using configured build prefix $prefix instead of $($release.appBuild) for $($release.appVersion)."
        }
        $builds = @(Get-FinOpsBuild $session $prefix)
        if (-not $AllBuilds) { $builds = @($builds[-1]) }
        foreach ($build in $builds) {
            [pscustomobject]@{
                Release = $release.appVersion
                AppBuild = $build
                PlatformUpdate = $release.platVersion
            }
        }
    }
)
if ($ListOnly) {
    $plan
    return
}

$storage = @('--account-name', $StorageAccount, '--container-name', $Container)
if (-not $env:AZURE_STORAGE_SAS_TOKEN) { $storage += @('--auth-mode', 'login') }
$workDirectory = Join-Path ([IO.Path]::GetTempPath()) "fscps-nuget-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $workDirectory
$originalJson = Get-Content -LiteralPath $VersionsPath -Raw
try {
    foreach ($item in $plan) {
        # Refresh Azure CLI tokens between builds during long backfills.
        if (-not $AccessToken) { $session = Get-FinOpsSession $DataverseUrl }
        $platformBuild = Get-FinOpsPlatformBuild $session $item.AppBuild
        $packageVersions = @{}
        foreach ($packageName in Get-FinOpsPackageName) {
            $expectedVersion = if ($packageName -like 'Microsoft.Dynamics.AX.Platform.*') { $platformBuild } else { $item.AppBuild }
            $blobName = "$packageName.$expectedVersion.nupkg"
            $exists = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'exists', '--name', $blobName) + $storage)
            if ($exists.exists -isnot [bool]) { throw "Invalid storage existence response for $blobName." }
            if ($exists.exists) {
                $blob = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'show', '--name', $blobName) + $storage)
                if ($blob.metadata -and $blob.metadata.Contains('fscpssha256') -and
                    $blob.metadata.fscpssha256 -match '^[a-f0-9]{64}$' -and
                    $blob.metadata.Contains('fscpsversion') -and $blob.metadata.fscpsversion -eq $expectedVersion -and
                    [long]$blob.properties.contentLength -gt 0) {
                    Write-Information "Already published: $blobName" -InformationAction Continue
                    $packageVersions[$packageName] = $expectedVersion
                    continue
                }
            }

            $packagePath = Join-Path $workDirectory $blobName
            try {
                $link = Get-FinOpsPackageLink $session $packageName $item.AppBuild
                $null = Invoke-FinOpsBlob -Uri $link -PackageName $packageName -OutFile $packagePath
                $identity = Read-FinOpsNuGetIdentity -Path $packagePath
                if ($identity.Id -cne $packageName -or $identity.Version -ne $expectedVersion) {
                    throw "Package identity mismatch for $packageName. Expected version $expectedVersion; refusing publication."
                }
                $sha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
                $null = Invoke-FinOpsAzure -Arguments (@(
                    'storage', 'blob', 'upload', '--name', $blobName, '--file', $packagePath,
                    '--overwrite', 'true', '--tier', 'Hot',
                    '--metadata', "fscpssha256=$sha256", "fscpsversion=$expectedVersion"
                ) + $storage)
                $published = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'show', '--name', $blobName) + $storage)
                if ([long]$published.properties.contentLength -ne (Get-Item -LiteralPath $packagePath).Length -or
                    $published.metadata.fscpssha256 -ne $sha256) {
                    throw "Publication verification failed for $blobName."
                }
                $packageVersions[$packageName] = $identity.Version
                Write-Information "Published: $blobName" -InformationAction Continue
            }
            finally {
                if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
            }
        }
        Update-FinOpsVersionRecord -Versions ([ref]$versions) -Release $item.Release `
            -AppBuild $item.AppBuild -PlatformBuild $platformBuild -PlatformUpdate $item.PlatformUpdate
        [pscustomobject]@{
            Release = $item.Release
            AppBuild = $item.AppBuild
            PlatformBuild = $platformBuild
            PackagesPublished = $packageVersions.Count
        }
    }
    $json = ConvertTo-Json -InputObject @($versions | Sort-Object { [version]$_.version }) -Depth 20
    # Avoid rewriting a repository file solely because of whitespace or property ordering.
    $before = ConvertTo-Json -InputObject @($originalJson | ConvertFrom-Json -AsHashtable) -Depth 20 -Compress
    $after = ConvertTo-Json -InputObject @($versions | Sort-Object { [version]$_.version }) -Depth 20 -Compress
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
