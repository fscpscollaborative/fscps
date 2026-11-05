BeforeAll {
    . (Join-Path $PSScriptRoot 'LCS-Api.ps1')
    . (Join-Path $PSScriptRoot 'FinOps-Sync.ps1')
    $script:syncPath = Join-Path $PSScriptRoot 'Sync-LcsDeployablePackages.ps1'
    function az { param([Parameter(ValueFromRemainingArguments)] $Arguments) }
    $script:ids = @{
        PreviewOld = '10000000-0000-0000-0000-000000000001'
        PreviewNew = '10000000-0000-0000-0000-000000000002'
        QualityOld = '20000000-0000-0000-0000-000000000001'
        QualityNew = '20000000-0000-0000-0000-000000000002'
        Service = '30000000-0000-0000-0000-000000000001'
    }
    $script:listJson = @"
[
 {"Id":"$($ids.PreviewOld)","Name":"Preview Version - 10.0.50","CreatedDate":"11/01/2026 10:00:00","SizeByte":16},
 {"Id":"$($ids.PreviewNew)","Name":"Preview Version - 10.0.50","CreatedDate":"11/02/2026 18:51:22","SizeByte":16},
 {"Id":"$($ids.QualityOld)","Name":"Proactive Quality Update - 10.0.49","CreatedDate":"10/31/2026 19:53:29","SizeByte":16},
 {"Id":"$($ids.QualityNew)","Name":"Proactive Quality Update - 10.0.49","CreatedDate":"11/03/2026 08:00:00","SizeByte":16},
 {"Id":"$($ids.Service)","Name":"Service Update - 10.0.49","CreatedDate":"10/01/2026 08:00:00","SizeByte":16},
 {"Id":"40000000-0000-0000-0000-000000000001","Name":"AX2012DataUpgrade-10.0.49","CreatedDate":"11/04/2026 08:00:00","SizeByte":16},
 {"Id":"40000000-0000-0000-0000-000000000002","Name":"DataUpgrade-10-0-10","CreatedDate":"11/04/2026 08:00:00","SizeByte":16},
 {"Id":"40000000-0000-0000-0000-000000000003","Name":"Service Update - 10.0.20, Build 10.0.886.114","CreatedDate":"11/04/2026 08:00:00","SizeByte":16},
 {"Id":"40000000-0000-0000-0000-000000000004","Name":"Disable Maintenance Mode","CreatedDate":"11/04/2026 08:00:00","SizeByte":16}
]
"@
}

Describe 'LCS classification and selection' {
    It 'recognizes package types and versions and ignores unrelated assets' {
        (Get-LcsSdpClassification 'Preview Version - 10.0.50').Type | Should -Be 'Preview'
        (Get-LcsSdpClassification 'First Release Service Update - 10.0.44').Type | Should -Be 'Service'
        (Get-LcsSdpClassification 'Proactive Quality Update - 10.0.49').Version | Should -Be '10.0.49'
        (Get-LcsSdpClassification 'Final Quality Update - 10.0.38').Type | Should -Be 'Final'
        Get-LcsSdpClassification 'AX2012DataUpgrade-10.0.49' | Should -BeNullOrEmpty
        Get-LcsSdpClassification 'DataUpgrade-10-0-10' | Should -BeNullOrEmpty
        Get-LcsSdpClassification 'Disable Maintenance Mode' | Should -BeNullOrEmpty
    }

    It 'lets the newest asset win per role and handles both date shapes' {
        $assets = $listJson | ConvertFrom-Json
        $selection = Get-LcsSdpSelection -Assets $assets -MinimumExclusive ([version]'10.0.39')
        $selection.Keys | Sort-Object | Should -Be @('10.0.49', '10.0.50')
        $selection['10.0.50'].Preview.Id | Should -Be $ids.PreviewNew
        $selection['10.0.49'].Service.Id | Should -Be $ids.Service
        $selection['10.0.49'].Latest.Id | Should -Be $ids.QualityNew
        (ConvertTo-LcsDate '11/02/2026 18:51:22').Hour | Should -Be 18
        (ConvertTo-LcsDate ([datetime]::SpecifyKind([datetime]'2026-11-02T18:00:00', 'Utc'))).Hour | Should -Be 18
        { ConvertTo-LcsDate 'not a date' } | Should -Throw '*unrecognized date*'
    }

    It 'preserves other fields and creates unknown releases with the platform update offset' {
        $versions = @([ordered]@{ version = '10.0.49'; data = [ordered]@{ FSCServiseUpdatePackageId = 'old'; Custom = 'keep'; PlatformUpdate = 73 } })
        $selection = Get-LcsSdpSelection -Assets ($listJson | ConvertFrom-Json) -MinimumExclusive ([version]'10.0.39')
        foreach ($record in $selection.Values) { Update-LcsSdpVersionRecord -Versions ([ref]$versions) -Selection $record }
        $versions.Count | Should -Be 2
        $v49 = $versions | Where-Object { $_.version -eq '10.0.49' }
        $v49.data.Custom | Should -Be 'keep'
        $v49.data.PlatformUpdate | Should -Be 73
        $v49.data.FSCServiseUpdatePackageId | Should -Be $ids.Service
        $v50 = $versions | Where-Object { $_.version -eq '10.0.50' }
        $v50.data.PlatformUpdate | Should -Be 74
        $v50.data.FSCPreviewVersionPackageId | Should -Be $ids.PreviewNew
        $v50.data.FSCServiseUpdatePackageId | Should -Be ''
    }
}

Describe 'Deployable package synchronization' {
    BeforeEach {
        $script:versionsPath = Join-Path $TestDrive 'versions.json'
        $script:initialJson = '[{"version":"10.0.49","data":{"FSCServiseUpdatePackageId":"old","Custom":"keep","PlatformUpdate":73}}]'
        Set-Content $versionsPath $initialJson
        $env:LCS_CLIENT_ID = 'client-id'; $env:LCS_USERNAME = 'svc@example.test'; $env:LCS_USER_PASSWORD = 'test-secret-pass'
        $global:FscpsSdpState = @{ Blobs = @{}; Uploads = 0; VersionsPath = $versionsPath; JsonAtLastUpload = $null }
        Mock Start-Sleep {}
        Mock Invoke-RestMethod {
            if ($Uri -like '*login.microsoftonline.com*') { return @{ access_token = 'test-token' } }
            [pscustomobject]@{ FileLocation = 'https://teststorage.blob.core.windows.net/files/asset?sig=test-sas' }
        }
        Mock Invoke-WebRequest {
            if ($OutFile) {
                [IO.File]::WriteAllBytes($OutFile, [byte[]](1..16))
                return @{ StatusCode = 200; Headers = @{ 'Content-Length' = '16' } }
            }
            @{ StatusCode = 200; Content = $listJson; Headers = @{ 'Content-Type' = 'application/json; charset=utf-8' } }
        }
        Mock az {
            $global:LASTEXITCODE = 0
            $name = $Arguments[[array]::IndexOf($Arguments, '--name') + 1]
            $state = $global:FscpsSdpState
            switch ($Arguments[2]) {
                'exists' { return (@{ exists = $state.Blobs.ContainsKey($name) } | ConvertTo-Json -Compress) }
                'show' { return ($state.Blobs[$name] | ConvertTo-Json -Depth 10 -Compress) }
                'upload' {
                    $state.Uploads++
                    $state.JsonAtLastUpload = Get-Content -LiteralPath $state.VersionsPath -Raw
                    $assetId = ($Arguments | Where-Object { $_ -like 'lcsassetid=*' }) -replace '^lcsassetid=', ''
                    $file = $Arguments[[array]::IndexOf($Arguments, '--file') + 1]
                    $state.Blobs[$name] = @{ metadata = @{ lcsassetid = $assetId }; properties = @{ contentLength = (Get-Item $file).Length; lastModified = '2026-11-05T10:00:00+00:00' } }
                    return '{}'
                }
                default { throw 'Unexpected Azure CLI call.' }
            }
        }
    }

    AfterEach { Remove-Item Env:\LCS_CLIENT_ID, Env:\LCS_USERNAME, Env:\LCS_USER_PASSWORD -ErrorAction SilentlyContinue }
    AfterAll { Remove-Variable -Name FscpsSdpState -Scope Global -ErrorAction SilentlyContinue }

    It 'lists the plan without touching storage or the versions file' {
        $result = @(& $syncPath -ProjectId 1630335 -VersionsPath $versionsPath -ListOnly)
        $result.Count | Should -Be 3
        ($result.Action | Select-Object -Unique) | Should -Be 'Planned'
        Should -Invoke az -Times 0 -Exactly
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'publishes each selected asset once, updates JSON only afterwards and is idempotent' {
        $result = @(& $syncPath -ProjectId 1630335 -VersionsPath $versionsPath)
        ($result | Where-Object Action -eq 'Published').Count | Should -Be 3
        $global:FscpsSdpState.Blobs.ContainsKey('Preview Version - 10.0.50') | Should -BeTrue
        $global:FscpsSdpState.Blobs['Preview Version - 10.0.50'].metadata.lcsassetid | Should -Be $ids.PreviewNew
        $global:FscpsSdpState.JsonAtLastUpload.Trim() | Should -Be $initialJson
        $versions = @(Get-Content $versionsPath -Raw | ConvertFrom-Json)
        ($versions | Where-Object version -eq '10.0.49').data.FSCLatestQualityUpdatePackageId | Should -Be $ids.QualityNew
        ($versions | Where-Object version -eq '10.0.49').data.Custom | Should -Be 'keep'
        ($versions | Where-Object version -eq '10.0.50').data.FSCPreviewVersionPackageId | Should -Be $ids.PreviewNew
        $firstJson = Get-Content $versionsPath -Raw
        $second = @(& $syncPath -ProjectId 1630335 -VersionsPath $versionsPath)
        ($second | Where-Object Action -eq 'Present').Count | Should -Be 3
        $global:FscpsSdpState.Uploads | Should -Be 3
        (Get-Content $versionsPath -Raw) | Should -BeExactly $firstJson
        Should -Invoke Invoke-WebRequest -Times 3 -Exactly -ParameterFilter { $OutFile }
    }

    It 'trusts a legacy blob uploaded after the asset was created and replaces an older one' {
        $global:FscpsSdpState.Blobs['Service Update - 10.0.49'] = @{ metadata = @{}; properties = @{ contentLength = 16; lastModified = '2026-11-10T00:00:00+00:00' } }
        $global:FscpsSdpState.Blobs['Preview Version - 10.0.50'] = @{ metadata = @{}; properties = @{ contentLength = 16; lastModified = '2026-10-01T00:00:00+00:00' } }
        $result = @(& $syncPath -ProjectId 1630335 -VersionsPath $versionsPath)
        ($result | Where-Object Package -eq 'Service Update - 10.0.49').Action | Should -Be 'Present'
        ($result | Where-Object Package -eq 'Preview Version - 10.0.50').Action | Should -Be 'Published'
    }

    It 'replaces a blob that belongs to a different LCS asset' {
        $global:FscpsSdpState.Blobs['Service Update - 10.0.49'] = @{ metadata = @{ lcsassetid = 'other' }; properties = @{ contentLength = 16; lastModified = '2026-11-10T00:00:00+00:00' } }
        $result = @(& $syncPath -ProjectId 1630335 -VersionsPath $versionsPath)
        ($result | Where-Object Package -eq 'Service Update - 10.0.49').Action | Should -Be 'Published'
    }

    It 'leaves JSON and storage untouched when a download fails' {
        Mock Invoke-WebRequest { throw 'https://teststorage.blob.core.windows.net/x?sig=private' } -ParameterFilter { $OutFile }
        $message = $null
        try { & $syncPath -ProjectId 1630335 -VersionsPath $versionsPath } catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*Download failed*'
        $message | Should -Not -Match 'sig=|private'
        $global:FscpsSdpState.Uploads | Should -Be 0
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'rejects a download whose size does not match' {
        Mock Invoke-WebRequest {
            [IO.File]::WriteAllBytes($OutFile, [byte[]](1..8))
            @{ StatusCode = 200; Headers = @{ 'Content-Length' = '16' } }
        } -ParameterFilter { $OutFile }
        { & $syncPath -ProjectId 1630335 -VersionsPath $versionsPath } | Should -Throw '*Content-Length*'
        $global:FscpsSdpState.Uploads | Should -Be 0
        (Get-Content $versionsPath -Raw).Trim() | Should -Be $initialJson
    }

    It 'refuses an unexpected download host without requesting it' {
        Mock Invoke-RestMethod {
            if ($Uri -like '*login.microsoftonline.com*') { return @{ access_token = 'test-token' } }
            [pscustomobject]@{ FileLocation = 'https://evil.example/files/asset?sig=private' }
        }
        { & $syncPath -ProjectId 1630335 -VersionsPath $versionsPath } | Should -Throw '*unexpected download location*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $OutFile }
    }

    It 'reports only AADSTS codes when the token request fails' {
        Mock Invoke-RestMethod {
            $record = [Management.Automation.ErrorRecord]::new([Exception]::new('bad'), 'x', 'NotSpecified', $null)
            $record.ErrorDetails = '{"error_description":"AADSTS50076: strong authentication required test-secret-pass"}'
            throw $record
        }
        $message = $null
        try { & $syncPath -ProjectId 1630335 -VersionsPath $versionsPath } catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*AADSTS50076*'
        $message | Should -Not -Match 'test-secret-pass|svc@example'
    }

    It 'rejects an HTML response instead of parsing it' {
        Mock Invoke-WebRequest {
            @{ StatusCode = 200; Content = '<html>Sign in</html>'; Headers = @{ 'Content-Type' = 'text/html' } }
        } -ParameterFilter { -not $OutFile }
        { & $syncPath -ProjectId 1630335 -VersionsPath $versionsPath } | Should -Throw '*non-JSON*'
    }

    It 'refuses to continue when nothing matches' {
        Mock Invoke-WebRequest {
            @{ StatusCode = 200; Content = '[{"Id":"50000000-0000-0000-0000-000000000001","Name":"Disable Maintenance Mode","CreatedDate":"11/04/2026 08:00:00"}]'; Headers = @{ 'Content-Type' = 'application/json' } }
        } -ParameterFilter { -not $OutFile }
        { & $syncPath -ProjectId 1630335 -VersionsPath $versionsPath } | Should -Throw '*No deployable packages matched*'
    }
}
