BeforeAll {
    $script:probePath = Join-Path $PSScriptRoot 'Test-FinOpsNuGetAccess.ps1'
    $script:token = ConvertTo-SecureString 'test-token-not-a-credential' -AsPlainText -Force
    function az { param([Parameter(ValueFromRemainingArguments)] $Arguments) }
}

Describe 'FinOps NuGet access probe' {
    BeforeEach {
        Mock Invoke-WebRequest {
            if ($Method -eq 'Head') {
                return @{ StatusCode = 200; Headers = @{ 'Content-Length' = '12345' } }
            }
            $content = switch -Wildcard ($Uri) {
                '*/finopsversions' { '[{"appBuild":"10.0.2000","appVersion":"10.0.40"}]' }
                '*/finopsbuilds?*' { '["10.0.2000.9","10.0.2000.10"]' }
                '*/finopsplatbuild?*' { '"7.0.7000.10"' }
                '*/nugetpackage?*' { '"https://teststorage.blob.core.windows.net/packages/test.nupkg?sig=test-sas"' }
                default { throw 'Unexpected request.' }
            }
            return @{ StatusCode = 200; Content = $content; Headers = @{ 'Content-Type' = 'application/json; charset=utf-8' } }
        }
    }

    It 'checks all five blobs without downloading packages or forwarding the bearer token' {
        $result = @(& $probePath -DataverseUrl 'https://contoso.crm.dynamics.com' -AccessToken $token)
        $result.Count | Should -Be 5
        $result[0].AppBuild | Should -Be '10.0.2000.10'
        $result[0].PlatformBuild | Should -Be '7.0.7000.10'
        $result[0].SizeBytes | Should -Be 12345
        $result | ConvertTo-Json | Should -Not -Match 'test-sas|test-token|blob.core'
        Should -Invoke Invoke-WebRequest -Times 5 -Exactly -ParameterFilter {
            $Method -eq 'Head' -and
            -not $PesterBoundParameters.ContainsKey('Token') -and
            -not $PesterBoundParameters.ContainsKey('Headers')
        }
        Should -Invoke Invoke-WebRequest -Times 8 -Exactly -ParameterFilter {
            $Authentication -eq 'Bearer' -and
            $Headers.dataverseEnvironmentUri -eq 'https://contoso.crm.dynamics.com/' -and
            $MaximumRedirection -eq 0
        }
    }

    It 'uses the application build for platform packages and supports explicit build selection' {
        $result = @(& $probePath -DataverseUrl 'https://contoso.crm4.dynamics.com/' -AccessToken $token -AppBuild '10.0.2000.7')
        $result.Count | Should -Be 5
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*/finopsbuilds?*' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*/nugetpackage?packageName=Microsoft.Dynamics.AX.Platform.CompilerPackage&version=10-0-2000-7'
        }
    }

    It 'reports HTTP authorization failures without the response body' {
        Mock Invoke-WebRequest { @{ StatusCode = 403; Content = 'private response'; Headers = @{} } }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token } |
            Should -Throw '*HTTP 403*'
    }

    It 'rejects HTML instead of attempting JSON deserialization' {
        Mock Invoke-WebRequest { @{ StatusCode = 200; Content = '<html>login</html>'; Headers = @{ 'Content-Type' = 'text/html' } } }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token } |
            Should -Throw '*non-JSON*'
    }

    It 'rejects invalid JSON' {
        Mock Invoke-WebRequest { @{ StatusCode = 200; Content = '<html>'; Headers = @{ 'Content-Type' = 'application/json' } } }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token } |
            Should -Throw '*invalid JSON*'
    }

    It 'does not expose SAS URLs in transport failures' {
        Mock Invoke-WebRequest { throw 'https://teststorage.blob.core.windows.net/private?sig=private' } -ParameterFilter { $Method -eq 'Head' }
        $message = $null
        try {
            & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token
        }
        catch {
            $message = $_.Exception.Message
        }
        $message | Should -BeLike '*Blob access failed*'
        $message | Should -Not -Match 'sig=|private'
    }

    It 'rejects unexpected SAS hosts without contacting them' {
        Mock Invoke-WebRequest {
            @{ StatusCode = 200; Content = '"https://unexpected.example/test.nupkg?sig=private"'; Headers = @{ 'Content-Type' = 'application/json' } }
        } -ParameterFilter { $Uri -like '*/nugetpackage?*' }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token } |
            Should -Throw '*unexpected download URL*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'Head' }
    }

    It 'fails when a package is inaccessible' {
        Mock Invoke-WebRequest { @{ StatusCode = 403; Headers = @{} } } -ParameterFilter { $Method -eq 'Head' }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token } |
            Should -Throw '*Blob access returned HTTP 403*'
    }

    It 'rejects untrusted Dataverse URLs before acquiring or sending a token' {
        { & $probePath -DataverseUrl 'https://example.com/' -AccessToken $token } |
            Should -Throw '*organization root URL*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'acquires a token for the organization, not the Developer Tools service' {
        Mock az {
            $global:LASTEXITCODE = 0
            '{"accessToken":"test-token-not-a-credential"}'
        }
        $result = @(& $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/')
        $result.Count | Should -Be 5
        Should -Invoke az -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'https://contoso.crm.dynamics.com'
        }
    }

    It 'stops before HTTP requests when token acquisition fails' {
        Mock az { $global:LASTEXITCODE = 1 }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' } |
            Should -Throw '*Could not acquire a Dataverse token*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'rejects an empty release catalog' {
        Mock Invoke-WebRequest {
            @{ StatusCode = 200; Content = '[]'; Headers = @{ 'Content-Type' = 'application/json' } }
        } -ParameterFilter { $Uri -like '*/finopsversions' }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token } |
            Should -Throw '*non-empty release array*'
    }

    It 'rejects a blob with no usable content length' {
        Mock Invoke-WebRequest { @{ StatusCode = 200; Headers = @{ 'Content-Length' = '0' } } } -ParameterFilter { $Method -eq 'Head' }
        { & $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token } |
            Should -Throw '*invalid package size*'
    }

    It 'selects the latest release by product version rather than build prefix' {
        Mock Invoke-WebRequest {
            @{ StatusCode = 200; Content = '[{"appVersion":"10.0.39","appBuild":"10.0.9999"},{"appVersion":"10.0.40","appBuild":"10.0.2000"}]'; Headers = @{ 'Content-Type' = 'application/json' } }
        } -ParameterFilter { $Uri -like '*/finopsversions' }
        $result = @(& $probePath -DataverseUrl 'https://contoso.crm.dynamics.com/' -AccessToken $token)
        $result[0].AppBuild | Should -Be '10.0.2000.10'
    }
}
