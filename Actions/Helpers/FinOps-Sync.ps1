function Invoke-FinOpsAzure {
    param([string[]] $Arguments)

    $output = & az @Arguments --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure Storage operation '$($Arguments[2])' failed. Check account, container and SAS permissions or Storage Blob Data Contributor role."
    }
    try {
        return ($output -join "`n") | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Azure Storage operation '$($Arguments[2])' returned invalid JSON."
    }
}

function Read-FinOpsNuGetIdentity {
    param([string] $Path)

    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $specs = @($archive.Entries | Where-Object { $_.FullName -match '^[^/\\]+\.nuspec$' })
        if ($specs.Count -ne 1 -or $specs[0].Length -gt 1MB) { throw 'Package must contain exactly one root nuspec no larger than 1 MB.' }
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $stream = $specs[0].Open()
        $reader = [Xml.XmlReader]::Create($stream, $settings)
        try {
            $document = [Xml.XmlDocument]::new()
            $document.XmlResolver = $null
            $document.Load($reader)
            $id = $document.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='id']")
            $version = $document.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='version']")
            if (-not $id -or -not $version -or $version.InnerText -notmatch '^\d+\.\d+\.\d+\.\d+$') {
                throw 'Package has no valid NuGet ID and four-part version.'
            }
            @{ Id = $id.InnerText; Version = $version.InnerText }
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
    finally { $archive.Dispose() }
}

function Update-FinOpsVersionRecord {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only merges in-memory data; the caller controls persistence.')]
    param([ref] $Versions, [string] $Release, [string] $AppBuild, [string] $PlatformBuild, [string] $PlatformUpdate)

    if ($PlatformUpdate -notmatch '^PU(\d+)$') { throw "Invalid platform update for $Release." }
    $update = [int]$Matches[1]
    $records = @($Versions.Value | Where-Object { $_.version -eq $Release })
    if ($records.Count -gt 1) { throw "Duplicate version records for $Release." }
    if ($records.Count -eq 0) {
        $record = [ordered]@{
            version = $Release
            data = [ordered]@{
                PlatformVersionGA = ''
                AppVersionGA = ''
                PlatformVersionLatest = ''
                AppVersionLatest = ''
                PlatformUpdate = $update
                EcommerceMicrosoftRepoBranch = ''
                FSCServiseUpdatePackageId = ''
                FSCPreviewVersionPackageId = ''
                FSCFinalQualityUpdatePackageId = ''
                FSCLatestQualityUpdatePackageId = ''
            }
        }
        $Versions.Value = @($Versions.Value) + @($record)
    }
    else { $record = $records[0] }

    $data = $record.data
    # This API does not identify GA releases or LCS asset IDs.
    foreach ($field in @('AppVersionLatest', 'PlatformVersionLatest')) {
        $candidate = if ($field -eq 'AppVersionLatest') { $AppBuild } else { $PlatformBuild }
        if (-not $data.Contains($field) -or -not $data[$field] -or [version]$candidate -gt [version]$data[$field]) {
            $data[$field] = $candidate
        }
    }
    $data['PlatformUpdate'] = $update
}
