#requires -Version 7.0
function Get-LcsAccessToken {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '', Justification = 'The LCS API only accepts the OAuth password grant; values come from workflow secrets.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'The OAuth password grant body requires the plaintext value; it is never logged.')]
    param([string] $ClientId, [string] $UserName, [string] $Password)

    if (-not $ClientId -or -not $UserName -or -not $Password) {
        throw 'LCS_CLIENT_ID, LCS_USERNAME and LCS_USER_PASSWORD are required.'
    }
    $body = @{
        grant_type = 'password'; client_id = $ClientId; username = $UserName; password = $Password
        resource = 'https://lcsapi.lcs.dynamics.com'; scope = 'openid'
    }
    try {
        $response = Invoke-RestMethod -Method Post -Uri 'https://login.microsoftonline.com/common/oauth2/token' -Body $body -TimeoutSec 60
    }
    catch {
        $codes = @([regex]::Matches([string]$_.ErrorDetails.Message, 'AADSTS\d+') | ForEach-Object { $_.Value } | Select-Object -Unique)
        throw "LCS token request failed. $($codes -join ', ') Credential details were not logged."
    }
    if (-not $response.access_token) { throw 'LCS token response did not contain an access token.' }
    [string]$response.access_token
}

function ConvertTo-LcsDate {
    [CmdletBinding()]
    param($Value)

    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
        return $Value.ToUniversalTime()
    }
    $parsed = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $formats = 'MM/dd/yyyy HH:mm:ss', 'M/d/yyyy H:mm:ss', 'M/d/yyyy h:mm:ss tt', 'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-ddTHH:mm:ssZ'
    if ([datetime]::TryParseExact([string]$Value, [string[]]$formats, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    throw 'An LCS asset has an unrecognized date format.'
}

function Get-LcsSharedAsset {
    [CmdletBinding()]
    param([string] $Token, [int] $FileType = 10)

    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    $uri = "https://lcsapi.lcs.dynamics.com/box/fileasset/GetSharedAssets?fileType=$FileType"
    $response = $null
    foreach ($attempt in 1..3) {
        try {
            $response = Invoke-WebRequest -Uri $uri -Headers $headers -TimeoutSec 360 -MaximumRedirection 0 -SkipHttpErrorCheck
            if ([int]$response.StatusCode -eq 200) { break }
        }
        catch { $response = $null }
        if ($attempt -lt 3) { Start-Sleep -Seconds (5 * $attempt) }
    }
    if (-not $response) { throw 'The LCS shared asset request failed (transport).' }
    if ([int]$response.StatusCode -ne 200) { throw "The LCS shared asset request returned HTTP $([int]$response.StatusCode)." }
    if ([string]($response.Headers['Content-Type'] -join ';') -notmatch '(?i)json') {
        throw 'The LCS shared asset request returned a non-JSON response; the token may not be accepted.'
    }
    try { $assets = @($response.Content | ConvertFrom-Json) }
    catch { throw 'The LCS shared asset response was not valid JSON.' }
    foreach ($asset in $assets) {
        $id = [guid]::Empty
        if (-not $asset.PSObject.Properties['Id'] -or -not [guid]::TryParse([string]$asset.Id, [ref]$id) -or
            -not $asset.PSObject.Properties['Name'] -or [string]::IsNullOrWhiteSpace([string]$asset.Name) -or
            -not $asset.PSObject.Properties['CreatedDate']) {
            throw 'The LCS shared asset response has an unexpected shape.'
        }
    }
    $assets
}

function Get-LcsAssetDownloadUri {
    [CmdletBinding()]
    param([string] $Token, [string] $ProjectId, [string] $AssetId)

    if ($ProjectId -notmatch '^\d+$' -or $AssetId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Invalid LCS project or asset identifier.' }
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    try {
        $detail = Invoke-RestMethod -Uri "https://lcsapi.lcs.dynamics.com/box/fileasset/GetFileAsset/$($ProjectId)?assetId=$($AssetId)" `
            -Headers $headers -TimeoutSec 120 -MaximumRedirection 0
    }
    catch { throw 'The LCS file asset request failed.' }
    $blobUri = $null
    if (-not $detail.PSObject.Properties['FileLocation'] -or
        -not [uri]::TryCreate([string]$detail.FileLocation, [UriKind]::Absolute, [ref]$blobUri) -or
        $blobUri.Scheme -ne 'https' -or $blobUri.UserInfo -or $blobUri.Fragment -or -not $blobUri.IsDefaultPort -or
        $blobUri.DnsSafeHost -notmatch '^[a-z0-9]+\.blob\.core\.windows\.net$' -or -not $blobUri.Query) {
        throw 'LCS returned an unexpected download location. It was not logged or requested.'
    }
    $blobUri
}

function Save-LcsAsset {
    [CmdletBinding()]
    param([uri] $Uri, [string] $Path, [string] $Name)

    $hide = {
        param([string] $text)
        $text = $text.Replace($Uri.AbsoluteUri, '<url>') -replace 'https?://\S+', '<url>' -replace '(?i)sig=[^&\s"]+', 'sig=<redacted>'
        $text.Substring(0, [Math]::Min(300, $text.Length))
    }
    $azcopy = Get-Command azcopy -ErrorAction SilentlyContinue
    if ($azcopy) {
        # AzCopy copes with multi-gigabyte files; the SAS URL and tool output are never logged unredacted.
        $output = & $azcopy.Source copy $Uri.AbsoluteUri $Path --output-level essential 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path)) {
            $tail = (@($output | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\S' } | Select-Object -Last 4) -join ' | ')
            throw "AzCopy download failed for '$Name' (exit code $LASTEXITCODE): $(& $hide $tail)"
        }
        return (Get-Item -LiteralPath $Path).Length
    }
    try {
        # Never forward the LCS token to blob storage.
        $response = Invoke-WebRequest -Uri $Uri -OutFile $Path -PassThru -TimeoutSec 7200 -MaximumRedirection 0 -SkipHttpErrorCheck
    }
    catch {
        throw "Download failed for '$Name': $(& $hide "$($_.Exception.GetType().Name): $($_.Exception.Message)")"
    }
    if ([int]$response.StatusCode -ne 200) { throw "Download returned HTTP $([int]$response.StatusCode) for '$Name'." }
    $length = (Get-Item -LiteralPath $Path).Length
    $expected = 0L
    if (-not [long]::TryParse([string]($response.Headers['Content-Length'] -join ''), [ref]$expected) -or $expected -le 0 -or $length -ne $expected) {
        throw "Downloaded size does not match Content-Length for '$Name'."
    }
    $length
}

function Get-LcsSdpClassification {
    [CmdletBinding()]
    param([string] $Name)

    $type = switch -Regex ($Name) {
        '(?i)^First Release Service Update' { 'Service'; break }
        '(?i)^Service Update' { 'Service'; break }
        '(?i)^Preview Version' { 'Preview'; break }
        '(?i)^Proactive Quality Update' { 'Proactive'; break }
        '(?i)^Final Quality Update' { 'Final'; break }
        default { return $null }
    }
    $match = [regex]::Match($Name, '\b(\d+\.\d+\.\d+)\b')
    if (-not $match.Success) { return $null }
    [pscustomobject]@{ Type = $type; Version = $match.Groups[1].Value }
}

function Get-LcsSdpSelection {
    [CmdletBinding()]
    param([object[]] $Assets, [version] $MinimumExclusive)

    $entries = foreach ($asset in $Assets) {
        $class = Get-LcsSdpClassification ([string]$asset.Name)
        if ($class -and [version]$class.Version -gt $MinimumExclusive) {
            [pscustomobject]@{
                Id = [string]$asset.Id; Name = [string]$asset.Name; Type = $class.Type; Version = $class.Version
                Created = ConvertTo-LcsDate $asset.CreatedDate; Size = if ($asset.PSObject.Properties['SizeByte']) { [long]$asset.SizeByte } else { 0L }
            }
        }
    }
    $selection = @{}
    foreach ($entry in @($entries | Sort-Object { $_.Created }, { $_.Id })) {
        if (-not $selection.ContainsKey($entry.Version)) {
            $selection[$entry.Version] = [pscustomobject]@{ Version = $entry.Version; Service = $null; Preview = $null; Latest = $null; Final = $null }
        }
        $record = $selection[$entry.Version]
        # Later assets win; this mirrors the legacy "newer platform build replaces older" rule without platform metadata.
        switch ($entry.Type) {
            'Service' { $record.Service = $entry; $record.Latest = $entry }
            'Preview' { $record.Preview = $entry; $record.Latest = $entry }
            'Proactive' { $record.Latest = $entry }
            'Final' { $record.Latest = $entry; $record.Final = $entry }
        }
    }
    $selection
}

function Update-LcsSdpVersionRecord {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only merges in-memory data; the caller controls persistence.')]
    param([ref] $Versions, [object] $Selection)

    $records = @($Versions.Value | Where-Object { $_.version -eq $Selection.Version })
    if ($records.Count -gt 1) { throw "Duplicate version records for $($Selection.Version)." }
    if ($records.Count -eq 0) {
        $platformUpdate = if ($Selection.Version -match '^10\.0\.(\d+)$') { [int]$Matches[1] + 24 } else { 0 }
        $record = [ordered]@{
            version = $Selection.Version
            data = [ordered]@{
                PlatformVersionGA = ''; AppVersionGA = ''; PlatformVersionLatest = ''; AppVersionLatest = ''
                PlatformUpdate = $platformUpdate; EcommerceMicrosoftRepoBranch = ''
                FSCServiseUpdatePackageId = ''; FSCPreviewVersionPackageId = ''
                FSCFinalQualityUpdatePackageId = ''; FSCLatestQualityUpdatePackageId = ''
            }
        }
        $Versions.Value = @($Versions.Value) + @($record)
    }
    else { $record = $records[0] }

    $map = [ordered]@{
        FSCServiseUpdatePackageId = $Selection.Service
        FSCPreviewVersionPackageId = $Selection.Preview
        FSCLatestQualityUpdatePackageId = $Selection.Latest
        FSCFinalQualityUpdatePackageId = $Selection.Final
    }
    foreach ($field in $map.Keys) {
        if ($map[$field]) { $record.data[$field] = $map[$field].Id }
    }
}
