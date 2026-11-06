BeforeAll {
    . (Join-Path $PSScriptRoot 'FinOps-Sync.ps1')
    . (Join-Path $PSScriptRoot 'FinOps-NuGet.ps1')
    $script:syncPath = Join-Path $PSScriptRoot 'Sync-FinOpsNuGets.ps1'
    $script:token = ConvertTo-SecureString 'test-only' -AsPlainText -Force
    function az { param([Parameter(ValueFromRemainingArguments)] $Arguments) }

    function New-TestPackage {
        param([string] $Path, [string] $Id, [string] $Version)
        $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $zip.CreateEntry('package.nuspec')
            $writer = [IO.StreamWriter]::new($entry.Open())
            try {
                $writer.Write("<package xmlns='http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd'><metadata><id>$Id</id><version>$Version</version></metadata></package>")
            }
            finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
    }

    function New-TestPackageWithFiles {
        param([string] $Path, [string] $Id, [string] $Version, [hashtable] $Files)
        $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $write = {
                param($name, $text)
                $entry = $zip.CreateEntry($name)
                $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
                try { $writer.Write($text) } finally { $writer.Dispose() }
            }
            & $write "$Id.nuspec" "<package xmlns='http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd'><metadata><id>$Id</id><version>$Version</version></metadata></package>"
            & $write '_rels/.rels' "<Relationships><Relationship Target=`"/$Id.nuspec`" Id=`"R1`" /></Relationships>"
            & $write '[Content_Types].xml' '<Types />'
            & $write 'package/services/metadata/core-properties/abc.psmdcp' "<cp><identifier>$Id</identifier></cp>"
            foreach ($name in $Files.Keys) { & $write $name $Files[$name] }
        }
        finally { $zip.Dispose() }
    }
}

Describe 'Combined Application package' {
    BeforeAll {
        $script:one = 'Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp'
        $script:two = 'Microsoft.Dynamics.AX.Application2.DevALM.BuildXpp'
        $script:combined = 'Microsoft.Dynamics.AX.Application.DevALM.BuildXpp'
    }

    It 'merges both parts into a package that identifies as the combined one' {
        $a = Join-Path $TestDrive 'a.nupkg'; $b = Join-Path $TestDrive 'b.nupkg'; $out = Join-Path $TestDrive 'out.nupkg'
        New-TestPackageWithFiles $a $one '10.0.2790.113' @{ 'ref/net40/A.dll' = 'aaa'; 'ref/net40/Shared.dll' = 'same' }
        New-TestPackageWithFiles $b $two '10.0.2790.113' @{ 'ref/net40/B.dll' = 'bbbb'; 'ref/net40/Shared.dll' = 'same' }
        Merge-FinOpsApplicationPackage -PartOnePath $a -PartTwoPath $b -OutputPath $out
        $identity = Read-FinOpsNuGetIdentity $out
        $identity.Id | Should -BeExactly $combined
        $identity.Version | Should -Be '10.0.2790.113'
        $zip = [IO.Compression.ZipFile]::OpenRead($out)
        try {
            $names = @($zip.Entries.FullName)
            $names | Should -Contain 'ref/net40/A.dll'
            $names | Should -Contain 'ref/net40/B.dll'
            @($names | Where-Object { $_ -eq 'ref/net40/Shared.dll' }).Count | Should -Be 1
            $names | Should -Contain "$combined.nuspec"
            $names | Should -Not -Contain "$one.nuspec"
            $names | Should -Not -Contain "$two.nuspec"
            $rels = [IO.StreamReader]::new(($zip.Entries | Where-Object FullName -eq '_rels/.rels').Open()); $relText = $rels.ReadToEnd(); $rels.Dispose()
            $relText | Should -Match "/$([regex]::Escape($combined))\.nuspec"
            $relText | Should -Not -Match 'Application1'
        }
        finally { $zip.Dispose() }
    }

    It 'refuses parts that disagree about a shared file' {
        $a = Join-Path $TestDrive 'a2.nupkg'; $b = Join-Path $TestDrive 'b2.nupkg'; $out = Join-Path $TestDrive 'out2.nupkg'
        New-TestPackageWithFiles $a $one '10.0.2790.113' @{ 'ref/Shared.dll' = 'one' }
        New-TestPackageWithFiles $b $two '10.0.2790.113' @{ 'ref/Shared.dll' = 'different' }
        { Merge-FinOpsApplicationPackage -PartOnePath $a -PartTwoPath $b -OutputPath $out } | Should -Throw '*disagree*'
    }
}

Describe 'NuGet identity validation' {
    It 'reads a namespaced nuspec without extracting the archive' {
        $path = Join-Path $TestDrive 'valid.nupkg'
        New-TestPackage $path 'Test.Package' '10.0.2000.10'
        $identity = Read-FinOpsNuGetIdentity $path
        $identity.Id | Should -Be 'Test.Package'
        $identity.Version | Should -Be '10.0.2000.10'
    }

    It 'rejects malformed or missing versions' {
        $path = Join-Path $TestDrive 'invalid.nupkg'
        New-TestPackage $path 'Test.Package' 'invalid'
        { Read-FinOpsNuGetIdentity $path } | Should -Throw '*no valid NuGet ID*'
    }
}

Describe 'Version metadata merge' {
    It 'preserves GA, asset IDs, custom fields and does not downgrade latest versions' {
        $versions = @(@{
            version = '10.0.49'
            data = [ordered]@{
                AppVersionGA = '10.0.2790.1'; PlatformVersionGA = '7.0.8199.1'
                AppVersionLatest = '10.0.2790.120'; PlatformVersionLatest = '7.0.8199.80'
                FSCServiseUpdatePackageId = 'existing-id'; Custom = 'keep'; PlatformUpdate = 73
            }
        })
        Update-FinOpsVersionRecord ([ref]$versions) '10.0.49' '10.0.2790.111' '7.0.8199.70' 'PU73'
        $versions[0].data.AppVersionLatest | Should -Be '10.0.2790.120'
        $versions[0].data.PlatformVersionLatest | Should -Be '7.0.8199.80'
        $versions[0].data.AppVersionGA | Should -Be '10.0.2790.1'
        $versions[0].data.PlatformVersionGA | Should -Be '7.0.8199.1'
        $versions[0].data.FSCServiseUpdatePackageId | Should -Be 'existing-id'
        $versions[0].data.Custom | Should -Be 'keep'
    }

    It 'adds a release without inventing GA or LCS asset IDs' {
        $versions = @()
        Update-FinOpsVersionRecord ([ref]$versions) '10.0.49' '10.0.2790.111' '7.0.8199.70' 'PU73'
        $versions.Count | Should -Be 1
        $versions[0].version | Should -Be '10.0.49'
        $versions[0].data.AppVersionLatest | Should -Be '10.0.2790.111'
        $versions[0].data.PlatformVersionLatest | Should -Be '7.0.8199.70'
        $versions[0].data.PlatformUpdate | Should -Be 73
        $versions[0].data.AppVersionGA | Should -Be ''
        $versions[0].data.FSCServiseUpdatePackageId | Should -Be ''
    }
}

Describe 'End-to-end synchronization with HTTP and Azure CLI mocks' {
    BeforeEach {
        $script:versionsPath = Join-Path $TestDrive 'versions.json'
        $script:initialJson = '[{"version":"10.0.48","data":{"AppVersionLatest":"10.0.2645.37","PlatformVersionLatest":"7.0.7996.39","Custom":"keep"}}]'
        Set-Content $versionsPath $initialJson
        $global:FscpsSyncTestState = @{
            Blobs = @{}
            Uploads = 0
            VersionsPath = $versionsPath
            InitialJson = $initialJson
            JsonDuringLastUpload = $null
        }
        Mock az {
            $global:LASTEXITCODE = 0
            $nameIndex = [array]::IndexOf($Arguments, '--name')
            $name = $Arguments[$nameIndex + 1]
            switch ($Arguments[2]) {
                'exists' { return (@{ exists = $global:FscpsSyncTestState.Blobs.ContainsKey($name) } | ConvertTo-Json -Compress) }
                'show' { return ($global:FscpsSyncTestState.Blobs[$name] | ConvertTo-Json -Depth 10 -Compress) }
                'upload' {
                    $global:FscpsSyncTestState.Uploads++
                    if ($global:FscpsSyncTestState.Uploads -eq 6) {
                        $global:FscpsSyncTestState.JsonDuringLastUpload = Get-Content -LiteralPath $global:FscpsSyncTestState.VersionsPath -Raw
                    }
                    $file = $Arguments[[array]::IndexOf($Arguments, '--file') + 1]
                    $sha = ($Arguments | Where-Object { $_ -like 'fscpssha256=*' }) -replace '^fscpssha256=', ''
                    $version = ($Arguments | Where-Object { $_ -like 'fscpsversion=*' }) -replace '^fscpsversion=', ''
                    $global:FscpsSyncTestState.Blobs[$name] = @{
                        metadata = @{ fscpssha256 = $sha; fscpsversion = $version }
                        properties = @{ contentLength = (Get-Item $file).Length }
                    }
                    return '{}'
                }
                default { throw 'Unexpected Azure CLI call.' }
            }
        }
        Mock Invoke-WebRequest {
            if ($OutFile) {
                $package = [IO.Path]::GetFileNameWithoutExtension(([uri]$Uri).AbsolutePath)
                $version = if ($package -like '*.Platform.*') { '7.0.8199.70' } else { '10.0.2790.111' }
                New-TestPackage $OutFile $package $version
                return @{ StatusCode = 200; Headers = @{ 'Content-Length' = [string](Get-Item $OutFile).Length } }
            }
            $content = switch -Wildcard ($Uri) {
                '*/finopsversions' { '[{"appVersion":"10.0.49","appBuild":"10.0.2790","platVersion":"PU73"}]' }
                '*/finopsbuilds?*' { '["10.0.2790.110","10.0.2790.111"]' }
                '*/finopsplatbuild?*' { '"7.0.8199.70"' }
                '*/nugetpackage?*' { '"https://teststorage.blob.core.windows.net/packages/' + [regex]::Match($Uri, 'packageName=([^&]+)').Groups[1].Value + '.nupkg?sig=test"' }
                default { throw 'Unexpected HTTP call.' }
            }
            @{ StatusCode = 200; Content = $content; Headers = @{ 'Content-Type' = 'application/json' } }
        }
    }

    It 'lists latest builds without changing JSON or using storage' {
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly)
        $result.Count | Should -Be 1
        $result[0].AppBuild | Should -Be '10.0.2790.111'
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
        Should -Invoke az -Times 0 -Exactly
    }

    It 'lists all builds when backfill is explicitly requested' {
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -AllBuilds)
        $result.Count | Should -Be 2
    }

    It 'uploads six validated canonical packages, merges JSON and skips them on rerun' {
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath)
        $result[0].PackagesPublished | Should -Be 6
        $global:FscpsSyncTestState.Uploads | Should -Be 6
        $global:FscpsSyncTestState.JsonDuringLastUpload.Trim() | Should -Be $initialJson
        $global:FscpsSyncTestState.Blobs.ContainsKey('Microsoft.Dynamics.AX.Platform.CompilerPackage.7.0.8199.70.nupkg') | Should -BeTrue
        $versions = @(Get-Content $versionsPath -Raw | ConvertFrom-Json)
        $versions.Count | Should -Be 2
        $versions[0].data.Custom | Should -Be 'keep'
        $versions[1].data.AppVersionLatest | Should -Be '10.0.2790.111'
        $firstJson = Get-Content $versionsPath -Raw
        $null = & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath
        $global:FscpsSyncTestState.Uploads | Should -Be 6
        (Get-Content $versionsPath -Raw) | Should -BeExactly $firstJson
        Should -Invoke Invoke-WebRequest -Times 7 -Exactly -ParameterFilter { $OutFile }
    }

    It 'does not modify JSON on an upload failure and reports an error' {
        Mock az { $global:LASTEXITCODE = 1 } -ParameterFilter { $Arguments[2] -eq 'upload' }
        { & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath } |
            Should -Throw '*Storage operation*failed*'
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'does not update JSON or upload anything when package download fails' {
        Mock Invoke-WebRequest {
            throw 'Download interrupted.'
        } -ParameterFilter { $OutFile }
        { & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath } |
            Should -Throw '*Blob access failed*'
        $global:FscpsSyncTestState.Uploads | Should -Be 0
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'leaves JSON untouched after partial publication and reuses successful uploads on retry' {
        $global:FscpsSyncTestState.FailUpload = $true
        Mock az { $global:LASTEXITCODE = 1 } -ParameterFilter {
            $global:FscpsSyncTestState.FailUpload -and $Arguments[2] -eq 'upload' -and
            $Arguments -contains 'Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp.10.0.2790.111.nupkg'
        }
        { & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath } |
            Should -Throw '*Storage operation*failed*'
        $global:FscpsSyncTestState.Uploads | Should -Be 2
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
        $global:FscpsSyncTestState.FailUpload = $false
        $null = & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath
        $global:FscpsSyncTestState.Uploads | Should -Be 6
        @(Get-Content $versionsPath -Raw | ConvertFrom-Json).Count | Should -Be 2
    }

    It 'fails verification if the uploaded size is wrong' {
        Mock az {
            $global:LASTEXITCODE = 0
            '{"metadata":{"fscpssha256":"wrong"},"properties":{"contentLength":1}}'
        } -ParameterFilter { $Arguments[2] -eq 'show' }
        { & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath } |
            Should -Throw '*Publication verification failed*'
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'does not publish packages with incorrect nuspec identity' {
        Mock Invoke-WebRequest {
            New-TestPackage $OutFile 'Wrong.Package' '7.0.8199.70'
            @{ StatusCode = 200; Headers = @{ 'Content-Length' = [string](Get-Item $OutFile).Length } }
        } -ParameterFilter { $OutFile }
        { & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath } |
            Should -Throw '*identity mismatch*'
        $global:FscpsSyncTestState.Uploads | Should -Be 0
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'adds a release that the catalog does not advertise, warning about it' {
        Mock Invoke-WebRequest {
            $content = switch -Wildcard ($Uri) {
                '*/finopsversions' { '[{"appVersion":"10.0.49","appBuild":"10.0.2790","platVersion":"PU73"}]'; break }
                '*/finopsbuilds?version=10-0-2919' { '["10.0.2919.27","10.0.2919.28"]'; break }
                '*/finopsbuilds?*' { '["10.0.2790.111"]'; break }
                default { throw 'Unexpected HTTP call.' }
            }
            @{ StatusCode = 200; Content = $content; Headers = @{ 'Content-Type' = 'application/json' } }
        }
        $extra = @([pscustomobject]@{ appVersion = '10.0.50'; appBuild = '10.0.2919'; platVersion = 'PU74' })
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -AdditionalReleases $extra -WarningVariable warnings)
        $result.Count | Should -Be 2
        $result[1].Release | Should -Be '10.0.50'
        $result[1].AppBuild | Should -Be '10.0.2919.28'
        $result[1].PlatformUpdate | Should -Be 'PU74'
        $warnings | Should -Match 'not advertised'
    }

    It 'does not duplicate an additional release once the catalog lists it' {
        $extra = @([pscustomobject]@{ appVersion = '10.0.49'; appBuild = '10.0.2790'; platVersion = 'PU73' })
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -AdditionalReleases $extra)
        $result.Count | Should -Be 1
    }

    It 'rejects malformed additional releases' {
        $extra = @([pscustomobject]@{ appVersion = '10.0.50'; appBuild = 'oops'; platVersion = 'PU74' })
        { & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -AdditionalReleases $extra } |
            Should -Throw '*AdditionalReleases*'
    }

    It 'discovers the next unlisted release by probing build prefixes' {
        Mock Invoke-WebRequest {
            $content = switch -Wildcard ($Uri) {
                '*/finopsversions' { '[{"appVersion":"10.0.49","appBuild":"10.0.2790","platVersion":"PU73"}]'; break }
                '*/finopsbuilds?version=10-0-2790' { '["10.0.2790.111"]'; break }
                '*/finopsbuilds?version=10-0-2793' { '["10.0.2793.4","10.0.2793.5"]'; break }
                '*/finopsbuilds?*' { '[]'; break }
                default { throw 'Unexpected HTTP call.' }
            }
            @{ StatusCode = 200; Content = $content; Headers = @{ 'Content-Type' = 'application/json' } }
        }
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -DiscoverNextRelease -DiscoveryPrefixSpan 6 -DiscoveryThrottleLimit 1 -WarningVariable warnings)
        $result.Count | Should -Be 2
        $result[1].Release | Should -Be '10.0.50'
        $result[1].AppBuild | Should -Be '10.0.2793.5'
        $result[1].PlatformUpdate | Should -Be 'PU74'
        $warnings | Should -Match 'Discovered unlisted release 10.0.50'
    }

    It 'adds nothing when no later build prefix exists' {
        Mock Invoke-WebRequest {
            $content = switch -Wildcard ($Uri) {
                '*/finopsversions' { '[{"appVersion":"10.0.49","appBuild":"10.0.2790","platVersion":"PU73"}]'; break }
                '*/finopsbuilds?version=10-0-2790' { '["10.0.2790.111"]'; break }
                '*/finopsbuilds?*' { '[]'; break }
                default { throw 'Unexpected HTTP call.' }
            }
            @{ StatusCode = 200; Content = $content; Headers = @{ 'Content-Type' = 'application/json' } }
        }
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -DiscoverNextRelease -DiscoveryPrefixSpan 6 -DiscoveryThrottleLimit 1)
        $result.Count | Should -Be 1
    }

    It 'does not trust a hit when an earlier probe failed' {
        Mock Invoke-WebRequest {
            if ($Uri -like '*/finopsbuilds?version=10-0-2791') { return @{ StatusCode = 500; Content = ''; Headers = @{} } }
            $content = switch -Wildcard ($Uri) {
                '*/finopsversions' { '[{"appVersion":"10.0.49","appBuild":"10.0.2790","platVersion":"PU73"}]'; break }
                '*/finopsbuilds?version=10-0-2790' { '["10.0.2790.111"]'; break }
                '*/finopsbuilds?version=10-0-2793' { '["10.0.2793.5"]'; break }
                '*/finopsbuilds?*' { '[]'; break }
                default { throw 'Unexpected HTTP call.' }
            }
            @{ StatusCode = 200; Content = $content; Headers = @{ 'Content-Type' = 'application/json' } }
        }
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -DiscoverNextRelease -DiscoveryPrefixSpan 6 -DiscoveryThrottleLimit 1 -WarningVariable warnings)
        $result.Count | Should -Be 1
        $warnings | Should -Match 'probes failed'
    }

    It 'keeps an existing combined package instead of replacing it' {
        $global:FscpsSyncTestState.Blobs['Microsoft.Dynamics.AX.Application.DevALM.BuildXpp.10.0.2790.111.nupkg'] = @{ metadata = @{}; properties = @{ contentLength = 5 } }
        $result = @(& $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath)
        $result[0].PackagesPublished | Should -Be 6
        $global:FscpsSyncTestState.Uploads | Should -Be 5
        Should -Invoke Invoke-WebRequest -Times 5 -Exactly -ParameterFilter { $OutFile }
    }

    It 'publishes the combined package under the canonical name with merge metadata' {
        $null = & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath
        $blob = $global:FscpsSyncTestState.Blobs['Microsoft.Dynamics.AX.Application.DevALM.BuildXpp.10.0.2790.111.nupkg']
        $blob | Should -Not -BeNullOrEmpty
        $blob.metadata.fscpsversion | Should -Be '10.0.2790.111'
        $blob.metadata.fscpssha256 | Should -Match '^[a-f0-9]{64}$'
    }

    It 'does not update JSON when the combined package cannot be built' {
        Mock Invoke-WebRequest {
            $package = [IO.Path]::GetFileNameWithoutExtension(([uri]$Uri).AbsolutePath)
            $id = if ($package -eq 'Microsoft.Dynamics.AX.Application2.DevALM.BuildXpp') { 'Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp' } else { $package }
            New-TestPackage $OutFile $id $(if ($package -like '*.Platform.*') { '7.0.8199.70' } else { '10.0.2790.111' })
            @{ StatusCode = 200; Headers = @{ 'Content-Length' = [string](Get-Item $OutFile).Length } }
        } -ParameterFilter { $OutFile }
        { & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath } |
            Should -Throw '*identity mismatch*'
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'applies explicit prefix overrides and never silently falls back' {
        $null = & $syncPath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token -VersionsPath $versionsPath -ListOnly -BuildPrefixOverrides @{ '10.0.49' = '10.0.2790' } -WarningVariable warnings
        $warnings | Should -Match 'Using configured build prefix'
    }

    AfterAll {
        Remove-Variable -Name FscpsSyncTestState -Scope Global -ErrorAction SilentlyContinue
    }
}
