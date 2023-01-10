$script:gitHubSecrets = $env:Secrets | ConvertFrom-Json
$script:isKeyvaultSet = $script:gitHubSecrets.PSObject.Properties.Name -eq "AZURE_CREDENTIALS"
$script:escchars = @(' ','!','\"','#','$','%','\u0026','\u0027','(',')','*','+',',','-','.','/','0','1','2','3','4','5','6','7','8','9',':',';','\u003c','=','\u003e','?','@','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z','[','\\',']','^','_',[char]96,'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','{','|','}','~')

function IsKeyVaultSet {
    return $script:isKeyvaultSet
}

function MaskValueInLog {
    Param(
        [string] $key,
        [string] $value
    )

    Write-Host "::add-mask::$value"

    $val2 = ""
    $value.ToCharArray() | ForEach-Object {
        $chint = [int]$_
        if ($chint -lt 32 -or $chint -gt 126 ) {
            throw "Secret $key contains characters, which are not supported in secrets in FSC-PS for GitHub. This exception is thrown to avoid that the secret is revealed in the log."
        }
        else {
            $val2 += $script:escchars[$chint-32]
        }
    }

    Write-Host "::add-mask::$val2"
}

function GetGithubSecret {
    param (
        [string] $secretName
    )
    $secretSplit = $secretName.Split('=')
    $envVar = $secretSplit[0]
    $secret = $envVar
    if ($secretSplit.Count -gt 1) {
        $secret = $secretSplit[1]
    }
    
    if ($script:gitHubSecrets.PSObject.Properties.Name -eq $secret) {
        $value = $script:githubSecrets."$secret"
        if ($value) {
            MaskValueInLog -key $secret -value $value
            Add-Content -Path $env:GITHUB_ENV -Value "$envVar=$value"
            return $value
        }
    }

    return $null
}
	

function GetSecret {
    param (
        [string] $secret,
        [string] $keyVaultName
    )

    Write-Host "Trying to get the secret($secret) from the github environment."
    $value = GetGithubSecret -secretName $secret
    if ($value) {
        Write-Host "Secret($secret) was retrieved from the github environment."
        return $value
    }

    Write-Host  "Could not find secret $secret in Github secrets."
    return $null
}
