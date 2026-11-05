#requires -Version 7.0
function Get-FinOpsSession {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Convert the transient Azure CLI token immediately for SecureString HTTP authentication.')]
    param([uri] $DataverseUrl, [Security.SecureString] $AccessToken)

    if ($DataverseUrl.Scheme -ne 'https' -or
        $DataverseUrl.AbsolutePath -ne '/' -or
        $DataverseUrl.Query -or $DataverseUrl.Fragment -or $DataverseUrl.UserInfo -or
        -not $DataverseUrl.IsDefaultPort -or
        $DataverseUrl.DnsSafeHost -notmatch '^[a-z0-9-]+\.crm\d*\.dynamics\.com$') {
        throw 'DataverseUrl must be a public-cloud organization root URL, such as https://contoso.crm.dynamics.com/.'
    }
    if (-not $AccessToken) {
        if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
            throw 'Azure CLI is required unless AccessToken is supplied as a SecureString.'
        }
        $tokenJson = & az account get-access-token --resource $DataverseUrl.GetLeftPart([UriPartial]::Authority) --output json --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not acquire a Dataverse token. Sign in to the correct tenant with Azure CLI, or supply AccessToken as a SecureString.'
        }
        try {
            $tokenResponse = ($tokenJson -join "`n") | ConvertFrom-Json
            if (-not $tokenResponse.accessToken) { throw 'Empty token.' }
            $AccessToken = ConvertTo-SecureString $tokenResponse.accessToken -AsPlainText -Force
        }
        catch {
            throw 'Azure CLI did not return a valid access token.'
        }
        finally {
            $tokenJson = $null
            $tokenResponse = $null
        }
    }
    @{
        Token = $AccessToken
        Headers = @{
            dataverseEnvironmentUri = $DataverseUrl.AbsoluteUri
            CorrelationId = [guid]::NewGuid().ToString()
            Accept = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version' = '4.0'
        }
    }
}

function Invoke-FinOpsMetadata {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Metadata is a mass noun describing the service API.')]
    param([hashtable] $Session, [string] $Path)

    try {
        $response = Invoke-WebRequest -Uri "https://developertools.powerplatform.microsoft.com/api/clientmetadata/$Path" `
            -Headers $Session.Headers -Authentication Bearer -Token $Session.Token -TimeoutSec 120 `
            -MaximumRedirection 0 -SkipHttpErrorCheck
    }
    catch {
        throw "Developer Tools request failed (transport or redirect). CorrelationId: $($Session.Headers.CorrelationId). No response body or credentials were logged."
    }
    if ([int]$response.StatusCode -ne 200) {
        throw "Developer Tools returned HTTP $([int]$response.StatusCode). CorrelationId: $($Session.Headers.CorrelationId). Verify token audience, tenant, Dataverse access and whether this service accepts the authentication mode."
    }
    $contentType = [string]($response.Headers['Content-Type'] -join ';')
    if ($contentType -notmatch '(?i)^application/(?:json|[a-z0-9.+-]+\+json)(?:;|$)') {
        throw "Developer Tools returned a non-JSON response. CorrelationId: $($Session.Headers.CorrelationId)."
    }
    try {
        $result = ConvertFrom-Json -InputObject $response.Content -NoEnumerate
    }
    catch {
        throw "Developer Tools returned invalid JSON. CorrelationId: $($Session.Headers.CorrelationId)."
    }
    return ,$result
}

function Get-FinOpsRelease {
    param([hashtable] $Session)

    $releases = Invoke-FinOpsMetadata $Session 'finopsversions'
    if ($releases -isnot [array] -or $releases.Count -eq 0) {
        throw 'The service did not return a non-empty release array.'
    }
    foreach ($release in $releases) {
        if (-not $release.PSObject.Properties['appVersion'] -or
            [string]$release.appVersion -notmatch '^\d+\.\d+\.\d+$' -or
            -not $release.PSObject.Properties['appBuild'] -or
            [string]$release.appBuild -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') {
            throw 'The release response contains an invalid appVersion or appBuild.'
        }
    }
    $releases | Sort-Object { [version]$_.appVersion }
}

function Get-FinOpsBuild {
    param([hashtable] $Session, [string] $Prefix)

    if ($Prefix -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') { throw 'Invalid build prefix.' }
    $builds = Invoke-FinOpsMetadata $Session "finopsbuilds?version=$($Prefix.Replace('.', '-'))"
    if ($builds -isnot [array] -or $builds.Count -eq 0) {
        throw 'The service did not return a non-empty build array.'
    }
    foreach ($build in $builds) {
        if ($build -isnot [string] -or $build -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
            -not ($build -eq $Prefix -or $build.StartsWith("$Prefix."))) {
            throw 'The build response contains an invalid application build.'
        }
    }
    $builds | Sort-Object { [version]$_ } -Unique
}

function Get-FinOpsPlatformBuild {
    param([hashtable] $Session, [string] $AppBuild)

    if ($AppBuild -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid application build.' }
    $build = Invoke-FinOpsMetadata $Session "finopsplatbuild?version=$($AppBuild.Replace('.', '-'))"
    if ($build -isnot [string] -or $build -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw 'The service did not return a valid platform build.'
    }
    $build
}

function Get-FinOpsPackageName {
    @(
        'Microsoft.Dynamics.AX.Platform.CompilerPackage'
        'Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp'
        'Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp'
        'Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp'
        'Microsoft.Dynamics.AX.Application2.DevALM.BuildXpp'
    )
}

function Get-FinOpsPackageLink {
    param([hashtable] $Session, [string] $PackageName, [string] $AppBuild)

    if ($PackageName -notin (Get-FinOpsPackageName) -or $AppBuild -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw 'Invalid package name or application build.'
    }
    $link = Invoke-FinOpsMetadata $Session "nugetpackage?packageName=$PackageName&version=$($AppBuild.Replace('.', '-'))"
    $blobUri = $null
    if ($link -isnot [string] -or -not [uri]::TryCreate($link, [UriKind]::Absolute, [ref]$blobUri) -or
        $blobUri.Scheme -ne 'https' -or $blobUri.UserInfo -or $blobUri.Fragment -or
        -not $blobUri.IsDefaultPort -or
        $blobUri.DnsSafeHost -notmatch '^[a-z0-9]+\.blob\.core\.windows\.net$' -or
        $blobUri.AbsolutePath -notmatch '(?i)\.nupkg$' -or -not $blobUri.Query) {
        throw "The service returned an unexpected download URL for $PackageName. The URL was not logged or requested."
    }
    return $blobUri
}

function Invoke-FinOpsBlob {
    param([uri] $Uri, [string] $PackageName, [string] $OutFile)

    try {
        # Never forward the Dataverse token to blob storage or log the SAS URL.
        if ($OutFile) {
            $response = Invoke-WebRequest -Uri $Uri -OutFile $OutFile -PassThru -TimeoutSec 3600 `
                -MaximumRedirection 0 -SkipHttpErrorCheck
        }
        else {
            $response = Invoke-WebRequest -Uri $Uri -Method Head -TimeoutSec 120 `
                -MaximumRedirection 0 -SkipHttpErrorCheck
        }
    }
    catch {
        throw "Blob access failed for $PackageName (transport or redirect). The SAS URL was not logged."
    }
    if ([int]$response.StatusCode -ne 200) {
        throw "Blob access returned HTTP $([int]$response.StatusCode) for $PackageName."
    }
    $size = 0L
    if (-not [long]::TryParse([string]($response.Headers['Content-Length'] -join ''), [ref]$size) -or $size -le 0) {
        throw "Blob storage returned an invalid package size for $PackageName."
    }
    if ($OutFile -and (Get-Item -LiteralPath $OutFile).Length -ne $size) {
        throw "Downloaded size does not match Content-Length for $PackageName."
    }
    $size
}
