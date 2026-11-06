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

function Merge-FinOpsApplicationPackage {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes only the requested output file.')]
    param(
        [string] $PartOnePath,
        [string] $PartTwoPath,
        [string] $OutputPath,
        [string] $PartOneId = 'Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp',
        [string] $CombinedId = 'Microsoft.Dynamics.AX.Application.DevALM.BuildXpp'
    )

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $isMetadata = { param([string] $name) $name -match '^(\[Content_Types\]\.xml|_rels/|package/)' -or $name -match '^[^/\\]+\.nuspec$' }
    $copy = {
        param($target, $source)
        $target.LastWriteTime = $source.LastWriteTime
        if (-not $source.FullName.EndsWith('/')) {
            $in = $source.Open(); $out = $target.Open()
            try { $in.CopyTo($out, 81920) } finally { $out.Dispose(); $in.Dispose() }
        }
    }
    $one = [IO.Compression.ZipFile]::OpenRead($PartOnePath)
    $two = $null; $output = $null
    try {
        $two = [IO.Compression.ZipFile]::OpenRead($PartTwoPath)
        if (@($one.Entries | Where-Object { $_.FullName -match '^[^/\\]+\.nuspec$' }).Count -ne 1) {
            throw 'The first package part must contain exactly one root nuspec.'
        }
        $output = [IO.Compression.ZipFile]::Open($OutputPath, [IO.Compression.ZipArchiveMode]::Create)
        $written = @{}
        foreach ($entry in $one.Entries) {
            if (& $isMetadata $entry.FullName) {
                # Package metadata names the first part; rewrite it so the result identifies as the combined package.
                $stream = $entry.Open(); $memory = [IO.MemoryStream]::new()
                try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
                $bytes = $memory.ToArray(); $memory.Dispose()
                $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
                $text = [Text.Encoding]::UTF8.GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))
                $text = $text.Replace($PartOneId, $CombinedId)
                $target = $output.CreateEntry($entry.FullName.Replace($PartOneId, $CombinedId), [IO.Compression.CompressionLevel]::Optimal)
                $target.LastWriteTime = $entry.LastWriteTime
                $out = $target.Open()
                try { $encoded = [Text.UTF8Encoding]::new($hasBom).GetBytes($text); if ($hasBom) { $out.Write([Text.UTF8Encoding]::new($true).GetPreamble(), 0, 3) }; $out.Write($encoded, 0, $encoded.Length) } finally { $out.Dispose() }
            }
            else {
                & $copy ($output.CreateEntry($entry.FullName, [IO.Compression.CompressionLevel]::Optimal)) $entry
                $written[$entry.FullName] = $entry.Length
            }
        }
        foreach ($entry in $two.Entries) {
            if (& $isMetadata $entry.FullName) { continue }
            if ($written.ContainsKey($entry.FullName)) {
                if ($written[$entry.FullName] -ne $entry.Length) { throw "The package parts disagree about '$($entry.FullName)'." }
                continue
            }
            & $copy ($output.CreateEntry($entry.FullName, [IO.Compression.CompressionLevel]::Optimal)) $entry
            $written[$entry.FullName] = $entry.Length
        }
    }
    finally {
        if ($output) { $output.Dispose() }
        if ($two) { $two.Dispose() }
        $one.Dispose()
    }
}

function Publish-FinOpsCombinedApplication {
    [CmdletBinding()]
    param([hashtable] $Session, [string] $AppBuild, [string] $WorkDirectory, [string[]] $StorageArguments)

    $combinedId = 'Microsoft.Dynamics.AX.Application.DevALM.BuildXpp'
    $blobName = "$combinedId.$AppBuild.nupkg"
    $exists = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'exists', '--name', $blobName) + $StorageArguments)
    if ($exists.exists -isnot [bool]) { throw "Invalid storage existence response for $blobName." }
    if ($exists.exists) {
        # A package published by Microsoft's own pipeline is authoritative; do not replace it.
        $blob = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'show', '--name', $blobName) + $StorageArguments)
        if ([long]$blob.properties.contentLength -gt 0) { return 'Present' }
    }

    $paths = @{}
    try {
        foreach ($partId in 'Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp', 'Microsoft.Dynamics.AX.Application2.DevALM.BuildXpp') {
            $paths[$partId] = Join-Path $WorkDirectory "$([guid]::NewGuid().ToString('N')).nupkg"
            $link = Get-FinOpsPackageLink $Session $partId $AppBuild
            $null = Invoke-FinOpsBlob -Uri $link -PackageName $partId -OutFile $paths[$partId]
            $identity = Read-FinOpsNuGetIdentity -Path $paths[$partId]
            if ($identity.Id -cne $partId -or $identity.Version -ne $AppBuild) {
                throw "Package identity mismatch for $partId while building $blobName."
            }
        }
        $merged = Join-Path $WorkDirectory "$([guid]::NewGuid().ToString('N')).nupkg"
        $paths['merged'] = $merged
        Merge-FinOpsApplicationPackage -PartOnePath $paths['Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp'] `
            -PartTwoPath $paths['Microsoft.Dynamics.AX.Application2.DevALM.BuildXpp'] -OutputPath $merged
        $identity = Read-FinOpsNuGetIdentity -Path $merged
        if ($identity.Id -cne $combinedId -or $identity.Version -ne $AppBuild) {
            throw "Merged package identity mismatch for $blobName; refusing publication."
        }
        $sha256 = (Get-FileHash -LiteralPath $merged -Algorithm SHA256).Hash.ToLowerInvariant()
        $null = Invoke-FinOpsAzure -Arguments (@(
            'storage', 'blob', 'upload', '--name', $blobName, '--file', $merged,
            '--overwrite', 'true', '--tier', 'Hot',
            '--metadata', "fscpssha256=$sha256", "fscpsversion=$AppBuild", 'fscpssource=Application1+Application2'
        ) + $StorageArguments)
        $published = Invoke-FinOpsAzure -Arguments (@('storage', 'blob', 'show', '--name', $blobName) + $StorageArguments)
        if ([long]$published.properties.contentLength -ne (Get-Item -LiteralPath $merged).Length -or
            $published.metadata.fscpssha256 -ne $sha256) {
            throw "Publication verification failed for $blobName."
        }
        'Published'
    }
    finally {
        foreach ($path in $paths.Values) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
    }
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
