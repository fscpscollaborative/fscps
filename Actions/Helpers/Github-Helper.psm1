function InvokeWebRequest {
    Param(
        [Hashtable] $headers,
        [string] $method,
        [string] $body,
        [string] $outFile,
        [string] $uri,
        [switch] $retry,
        [switch] $ignoreErrors
    )

    try {
        $params = @{ "UseBasicParsing" = $true }
        if ($headers) {
            $params += @{ "headers" = $headers }
        }
        if ($method) {
            $params += @{ "method" = $method }
        }
        if ($body) {
            $params += @{ "body" = $body }
        }
        if ($outfile) {
            $params += @{ "outfile" = $outfile }
        }
        Invoke-WebRequest  @params -Uri $uri
    }
    catch {
        if ($retry) {
            Start-Sleep -Seconds 60
            try {
                Invoke-WebRequest  @params -Uri $uri
                return
            }
            catch {}
        }
        $errorRecord = $_
        $exception = $_.Exception
        $message = $exception.Message
        try {
            if ($errorRecord.ErrorDetails) {
                $errorDetails = $errorRecord.ErrorDetails | ConvertFrom-Json 
                $errorDetails.psObject.Properties.name | ForEach-Object {
                    $message += " $($errorDetails."$_")"
                }
            }
        }
        catch {}
        if (!$ignoreErrors.IsPresent) {
            Write-Host "::Error::$message"
            throw $message
        }
    }
}
function GetGHSecrets {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    Write-Host "Analyzing releases $api_url/repos/$repository/actions/secrets"
    $releases = @(InvokeWebRequest -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/actions/secrets" | ConvertFrom-Json)
    if ($releases.Count -gt 1) {
        # Sort by SemVer tag
        try {
            $sortedReleases = $releases.tag_name | 
                ForEach-Object { SemVerStrToSemVerObj -semVerStr $_ } | 
                Sort-Object -Property Major,Minor,Patch,Addt0,Addt1,Addt2,Addt3,Addt4 -Descending | 
                ForEach-Object { SemVerObjToSemVerStr -semVerObj $_ } | ForEach-Object {
                    $tag_name = $_
                    $releases | Where-Object { $_.tag_name -eq $tag_name }
                }
            $sortedReleases
        }
        catch {
            Write-Host -ForegroundColor red "Some of the release tags cannot be recognized as a semantic version string (https://semver.org)"
            Write-Host -ForegroundColor red "Using default GitHub sorting for releases"
            $releases
        }
    }
    else {
        $releases
    }
}

function CmdDo {
    Param(
        [string] $command = "",
        [string] $arguments = "",
        [switch] $silent,
        [switch] $returnValue
    )

    $oldNoColor = "$env:NO_COLOR"
    $env:NO_COLOR = "Y"
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $result = $true
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.WorkingDirectory = Get-Location
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $arguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
    
        $outtask = $p.StandardOutput.ReadToEndAsync()
        $errtask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit();

        $message = $outtask.Result
        $err = $errtask.Result

        if ("$err" -ne "") {
            $message += "$err"
        }
        
        $message = $message.Trim()

        if ($p.ExitCode -eq 0) {
            if (!$silent) {
                Write-Host $message
            }
            if ($returnValue) {
                $message.Replace("`r","").Split("`n")
            }
        }
        else {
            $message += "`n`nExitCode: "+$p.ExitCode + "`nCommandline: $command $arguments"
            throw $message
        }
    }
    finally {
    #    [Console]::OutputEncoding = $oldEncoding
        $env:NO_COLOR = $oldNoColor
    }
}

function invoke-choco {
    Param(
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )
    begin
    {
        If(!(Get-Command -Name choco.exe -ErrorAction SilentlyContinue))
        {
            Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))  
        }
    }
    process
    {
        $arguments = "$command "
        $remaining | ForEach-Object {
            if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
                $arguments += """$($_.Replace('"','\"'))"" "
            }
            else {
                $arguments += "$_ "
            }
        }
        cmdDo -command choco -arguments $arguments -silent:$silent -returnValue:$returnValue
    }
}

function invoke-gh {
    Param(
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    begin
    {
        try {
            $pList = invoke-choco search ' gh ' -returnValue -silent
            if(-not ($pList.Item($pList.Length - 1).Substring(0,1) -gt 0))
            {
                invoke-choco install gh -y --allow-unofficial -silent
                refreshenv
            }
            else {
                invoke-choco upgrade gh -y --allow-unofficial
            }
        }
        catch {
            Write-Verbose "gh is already installed."
        }
 
    }
    process
    {
        $arguments = "$command "
        $remaining | ForEach-Object {
            if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
                $arguments += """$($_.Replace('"','\"'))"" "
            }
            else {
                $arguments += "$_ "
            }
        }
        cmdDo -command gh -arguments $arguments -silent:$silent -returnValue:$returnValue
    }
}

function invoke-git {
    Param(
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    $arguments = "$command "
    $remaining | ForEach-Object {
        if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
            $arguments += """$($_.Replace('"','\"'))"" "
        }
        else {
            $arguments += "$_ "
        }
    }
    cmdDo -command git -arguments $arguments -silent:$silent -returnValue:$returnValue
}

function SemVerObjToSemVerStr {
    Param(
        $semVerObj
    )

    try {
        $str = "$($semVerObj.Prefix)$($semVerObj.Major).$($semVerObj.Minor).$($semVerObj.Patch)"
        for ($i=0; $i -lt 5; $i++) {
            $seg = $semVerObj."Addt$i"
            if ($seg -eq 'zzz') { break }
            if ($i -eq 0) { $str += "-$($seg)" } else { $str += ".$($seg)" }
        }
        $str
    }
    catch {
        throw "'$SemVerObj' cannot be recognized as a semantic version object (internal error)"
    }
}

function SemVerStrToSemVerObj {
    Param(
        [string] $semVerStr
    )

    $obj = New-Object PSCustomObject
    try {
        $prefix = ''
        $verstr = $semVerStr
        if ($semVerStr -like 'v*') {
            $prefix = 'v'
            $verStr = $semVerStr.Substring(1)
        }
        $version = [System.Version]"$($verStr.split('-')[0])"
        if ($version.Revision -ne -1) { throw "not semver" }
        $obj | Add-Member -MemberType NoteProperty -Name "Prefix" -Value $prefix
        $obj | Add-Member -MemberType NoteProperty -Name "Major" -Value ([int]$version.Major)
        $obj | Add-Member -MemberType NoteProperty -Name "Minor" -Value ([int]$version.Minor)
        $obj | Add-Member -MemberType NoteProperty -Name "Patch" -Value ([int]$version.Build)
        0..4 | ForEach-Object {
            $obj | Add-Member -MemberType NoteProperty -Name "Addt$_" -Value 'zzz'
        }
        $idx = $verStr.IndexOf('-')
        if ($idx -gt 0) {
            $segments = $verStr.SubString($idx+1).Split('.')
            if ($segments.Count -ge 5) {
                throw "max. 5 segments"
            }
            0..($segments.Count-1) | ForEach-Object {
                $result = 0
                if ([int]::TryParse($segments[$_], [ref] $result)) {
                    $obj."Addt$_" = [int]$result
                }
                else {
                    if ($segments[$_] -ge 'zzz') {
                        throw "Unsupported segment"
                    }
                    $obj."Addt$_" = $segments[$_]
                }
            }
        }
        $newStr = SemVerObjToSemVerStr -semVerObj $obj
        if ($newStr -cne $semVerStr) {
            throw "Not equal"
        }
    }
    catch {
        throw "'$semVerStr' cannot be recognized as a semantic version string (https://semver.org)"
    }
    $obj
}
function GetReleases {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    Write-Host "Analyzing releases $api_url/repos/$repository/releases"
    $releases = @(InvokeWebRequest -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases" | ConvertFrom-Json)
    if ($releases.Count -gt 1) {
        # Sort by SemVer tag
        try {
            $sortedReleases = $releases.tag_name | 
                ForEach-Object { SemVerStrToSemVerObj -semVerStr $_ } | 
                Sort-Object -Property Major,Minor,Patch,Addt0,Addt1,Addt2,Addt3,Addt4 -Descending | 
                ForEach-Object { SemVerObjToSemVerStr -semVerObj $_ } | ForEach-Object {
                    $tag_name = $_
                    $releases | Where-Object { $_.tag_name -eq $tag_name }
                }
            $sortedReleases
        }
        catch {
            Write-Host -ForegroundColor red "Some of the release tags cannot be recognized as a semantic version string (https://semver.org)"
            Write-Host -ForegroundColor red "Using default GitHub sorting for releases"
            $releases
        }
    }
    else {
        $releases
    }
}

function GetHeader {
    param (
        [string] $token,
        [string] $accept = "application/vnd.github.v3+json"
    )
    $headers = @{ "Accept" = $accept }
    if (![string]::IsNullOrEmpty($token)) {
        $headers["Authorization"] = "token $token"
    }

    return $headers
}

function Set-EnvironmentSecret {
    Param(
        [string] $token,
        [string] $environment_name,
        [string] $secret_name,
        [string] $secret_value,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $api_url = $ENV:GITHUB_API_URL
    )
    $github = (Get-ActionContext)
    $GetPublicKey = @{
        Uri     = "$api_url/repos/$repository/actions/secrets/public-key"
        Headers = @{
            Authorization = "Bearer $($token)"
        }
        Method = "GET"
    }
    $GitHubPublicKey = Invoke-RestMethod @GetPublicKey
    $putParams = @{
        encrypted_value = ConvertTo-SodiumEncryptedString -Text $secret_value -PublicKey $GitHubPublicKey.key;
        key_id = $GitHubPublicKey.key_id;
    }

    $SetEnvSecret = @{
        Uri     = "$api_url/repositories/$($github.Payload.repository.id)/environments/$environment_name/secrets/$secret_name"
        Headers = @{
            Authorization = "Token $($token)"
        }
        Method = "PUT"
        Body = ($putParams | ConvertTo-Json)
    }
    Invoke-RestMethod @SetEnvSecret
}

function Get-LatestDeployedDate
{
    Param(
        [string] $token,
        [string] $repoName = "$env:GITHUB_REPOSITORY",
        [string] $repoOwner = "$Env:GITHUB_REPOSITORY_OWNER",
        [string] $environmentName = ""
    )
    begin{
$query = @"
{
    repository(name: "$($repoName)", owner: "$($repoOwner)") {
        deployments(environments: "$($environmentName)", orderBy: {field: CREATED_AT, direction: DESC}, first: 100) {
        nodes {
            state
            commitOid
            createdAt
            environment
            commit {
            abbreviatedOid
            }
        }
        }
    }
    }
"@
    }
    process{
        $body = @{query=$query} | ConvertTo-Json

        $graphQL = @{
            Uri     = "https://api.github.com/graphql"
            Headers = @{
                Authorization = "Token $token"
            }
            Method = "POST"
            Body = $body
        }
        $data = Invoke-RestMethod @graphQL

        $result = ""
        $data.data.repository.deployments.nodes | Sort-Object { $_.createdAt } | Where-Object { $_.state -eq "ACTIVE" } | ForEach-Object { $result = ($_.createdAt) }

        return $result
    }
    end{}
}
function Get-LatestDeploymentState
{
    Param(
        [string] $token,
        [string] $repoName = "$env:GITHUB_REPOSITORY",
        [string] $repoOwner = "$Env:GITHUB_REPOSITORY_OWNER",
        [string] $environmentName = ""
    )
    begin{
$query = @"
{
    repository(name: "$($repoName)", owner: "$($repoOwner)") {
        deployments(environments: "$($environmentName)", orderBy: {field: CREATED_AT, direction: DESC}, first: 100) {
        nodes {
            state
            commitOid
            createdAt
            environment
            commit {
            abbreviatedOid
            }
        }
        }
    }
    }
"@
    }
    process{
        $body = @{query=$query} | ConvertTo-Json

        $graphQL = @{
            Uri     = "https://api.github.com/graphql"
            Headers = @{
                Authorization = "Token $token"
            }
            Method = "POST"
            Body = $body
        }
        $data = Invoke-RestMethod @graphQL

        $result = ""
        $data.data.repository.deployments.nodes | Sort-Object { $_.createdAt} | ForEach-Object { $result = ($_.state) }

        return $result
    }
    end{}
}
function Get-ReleaseNotes {
    Param(
        [string] $token,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $tag_name,
        [string] $previous_tag_name
    )
    
    Write-Host "Generating release note $api_url/repos/$repository/releases/generate-notes"

    $postParams = @{
        tag_name = $tag_name;
    }

    if (-not [string]::IsNullOrEmpty($previous_tag_name)) {
        $postParams["previous_tag_name"] = $previous_tag_name
    }

    InvokeWebRequest -Headers (GetHeader -token $token) -Method POST -Body ($postParams | ConvertTo-Json) -Uri "$api_url/repos/$repository/releases/generate-notes" 
}

function Get-LatestRelease {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )
    
    Write-Host "Getting the latest release from $api_url/repos/$repository/releases/latest"
    try {
        InvokeWebRequest -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases/latest" -ignoreErrors | ConvertFrom-Json
    }
    catch {
        return $null
    }
}
function Remove-Release {
    Param(
        [string] $token,
        [string] $release_id = 0,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )
    
    
    try {
        $release = ""
        if($release_id -eq 0)
        {
            $release = (Get-LatestRelease -token $token -repository $repository -api_url $api_url)
            $release_id = $release.id
        }
        Write-Host "Remove the release with id $release_id from $api_url/repos/$repository/releases/$release_id"
        InvokeWebRequest -method DELETE -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases/$release_id" -ignoreErrors | ConvertFrom-Json
        Write-Host "Remove the tag with name $($release.tag_name) from $api_url/repos/$repository/git/refs/tags/$($release.tag_name)"
        InvokeWebRequest -method DELETE -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/git/refs/tags/$($release.tag_name)" -ignoreErrors | ConvertFrom-Json

    }
    catch {
        return $null
    }
}
function DownloadRelease {
    Param(
        [string] $token,
        [string] $projects = "*",
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $path,
        [string] $mask = "Apps",
        $release
    )

    if ($projects -eq "") { $projects = "*" }
    Write-Host "Downloading release $($release.Name), projects $projects, type $mask"
    if ([string]::IsNullOrEmpty($token)) {
        $authstatus = (invoke-gh -silent -returnValue auth status --show-token) -join " "
        $token = $authStatus.SubString($authstatus.IndexOf('Token: ')+7).Trim()
    }
    $headers = @{ 
        "Accept"        = "application/octet-stream"
        "Authorization" = "token $token"
    }
    $projects.Split(',') | ForEach-Object {
        $project = $_.Replace('\','_')
        Write-Host "project '$project'"
        
        $release.assets | Where-Object { $_.name -like "$project-*-$mask-*.zip" -or $_.name -like "$project-$mask-*.zip" } | ForEach-Object {
            $uri = "$api_url/repos/$repository/releases/assets/$($_.id)"
            Write-Host $uri
            $filename = Join-Path $path $_.name
            InvokeWebRequest -Headers $headers -Uri $uri -OutFile $filename 
            return $filename
        }
    }
}       

function CheckRateLimit {
    Param(
        [string] $token
    )

    $headers = GetHeader -token $token
    $rate = (InvokeWebRequest -Headers $headers -Uri "https://api.github.com/rate_limit").Content | ConvertFrom-Json
    $rate | ConvertTo-Json -Depth 99 | Out-Host
    $rate = $rate.rate
    $percent = [int]($rate.remaining*100/$rate.limit)
    Write-Host "$($rate.remaining) API calls remaining out of $($rate.limit) ($percent%)"
    if ($percent -lt 10) {
        $resetTimeStamp = ([datetime] '1970-01-01Z').AddSeconds($rate.reset)
        $waitTime = $resetTimeStamp.Subtract([datetime]::Now)
        Write-Host "Less than 10% API calls left, waiting for $($waitTime.TotalSeconds) seconds for limits to reset."
        Start-Sleep -seconds $waitTime.TotalSeconds+1
    }
}

function Publish-GithubRelease
{
    <#
    .SYNOPSIS
        Publish a new release on a Github repository
 
    .FUNCTIONALITY
        CI/CD
 
    .EXAMPLE
        Publish-GithubRelease -AccessToken $mySecretToken -TagName "v1.0"
 
        Create a new release for the tag "v1.0".
        The name of the repository is assumed to be the same as the BHProjectName.
 
    .EXAMPLE
        Publish-GithubRelease -AccessToken $mySecretToken -TagName "v0.1" -Name "Beta Version 0.1" -PreRelease
 
        Create a new pre-release for the tag "v0.1".
 
    .EXAMPLE
        Publish-GithubRelease -AccessToken $mySecretToken -TagName "v1.0" -Draft
 
        Create a draft for a release on tag "v1.0".
 
    .EXAMPLE
        $release = @{
            AccessToken = "00000000000000000000000"
            TagName = "v1.0"
            Name = "Version 1.0"
            ReleaseText = "First version of my cool thing"
            Draft = $true
            PreRelease = $false
            RepositoryName = "MyGithubRepository"
        }
        Publish-GithubRelease @release
 
        Create a new draft release by using splatting (more info at "about_splatting").
 
    .LINK
        https://developer.github.com/v3/repos/releases/
 
    .LINK
        https://blog.github.com/2013-05-16-personal-api-tokens/
    #>
    [CmdletBinding()]
    param(
        # Personal API Token for authentication
        #
        # This sha string must be generated by a user that has push access to
        # the repository.
        # More information can be found at:
        # https://blog.github.com/2013-05-16-personal-api-tokens/
        [Parameter( Mandatory )]
        [ValidateNotNullOrEmpty()]
        [String]
        $AccessToken,

        # Name of the Github user or organization hosting the repository
        [Parameter( Mandatory )]
        [ValidateNotNullOrEmpty()]
        [Alias('Owner')]
        [String]
        $RepositoryOwner,

        # Name of the Github repository
        #
        # Default: $env:BHProjectName
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]
        $RepositoryName,

        # Name of the tag
        [Parameter( Mandatory )]
        [ValidateNotNullOrEmpty()]
        [String]
        $TagName,

        # Specifies the commitish value that determines where the Git tag is
        # created from. Can be any branch or commit SHA.
        #
        # Unused if the Git tag already exists.
        # Default: the repository's default branch (usually master).
        [Alias("Commit")]
        [String]
        $TargetCommit,

        # Name of the release
        [String]
        $Name,
        # Title of the release
        [String]
        $Title,
        # Text describing the contents of the tag.
        [Alias('Body')]
        [String]
        $ReleaseText,

        # Create a draft (unpublished) release
        [Switch]
        $Draft,

        # Identify the release as a prerelease
        [Switch]
        $PreRelease,

        # Path to the artifact to upload to the release
        [Parameter( ValueFromPipeline, ValueFromPipelineByPropertyName )]
        #[ValidateScript(
        #    {
        #        if (-not (Test-Path $_ -PathType Leaf))
        #        {
        #            $exception = ([System.ArgumentException]"File not found")
        #            $errorId = 'ParameterValue.FileNotFound'
        #            $errorCategory = 'ObjectNotFound'
        #            $errorTarget = $_
        #            $errorItem = New-Object -TypeName System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $errorTarget
        #            $errorItem.ErrorDetails = "No file could be found with the provided path '$_'."
        #            $PSCmdlet.ThrowTerminatingError($errorItem)
        #        }
        #        return $true
        #    }
        #)]
        [Alias('File', 'FullName', 'Path')]
        [String[]]
        $Artifact
    )

    begin
    {
        $body = @{ "tag_name" = $TagName }
        if ($PSBoundParameters.ContainsKey("TargetCommit"))
        {
            $body["target_commitish"] = $TargetCommit
        }
        if ($PSBoundParameters.ContainsKey("Name"))
        {
            $body["name"] = $Name
        }
        if ($PSBoundParameters.ContainsKey("ReleaseText"))
        {
            $body["body"] = $ReleaseText
        }
        if ($PSBoundParameters.ContainsKey("Draft"))
        {
            $body["draft"] = $Draft.IsPresent
        }
        if ($PSBoundParameters.ContainsKey("PreRelease"))
        {
            $body["prerelease"] = $PreRelease.IsPresent
        }
        
        $releaseParams = @{
            Uri         = "https://api.github.com/repos/{0}/{1}/releases" -f $RepositoryOwner, $RepositoryName
            Method      = 'POST'
            Headers     = @{
                Authorization = 'Basic ' + [Convert]::ToBase64String(
                    [Text.Encoding]::ASCII.GetBytes($AccessToken + ":x-oauth-basic")
                )
            }
            ContentType = 'application/json'
            Body        = $body | ConvertTo-Json
            ErrorAction = "Stop"
        }
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Write-Output "ReleaseParams: "    
            $release = Invoke-RestMethod @releaseParams
        }
        catch {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Output "ReleaseParams: "    
                $releaseParams | ConvertTo-Json
                $releaseParams.Body = '';
                $release = Invoke-RestMethod @releaseParams
            }
            catch {
                $streamReader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $ErrResp = $streamReader.ReadToEnd() | ConvertFrom-Json
                $streamReader.Close()
                throw $ErrResp.ToString()
            }
        }        
    }

    process
    {
        $artifacts = (Get-ChildItem $Artifact -File -Recurse)
        if ($Artifact)
        {
            foreach ($file in $artifacts)
            {
                Write-Output "Release File: "
                $file

                $body = [System.IO.File]::ReadAllBytes($file.FullName)
                if($Name.Length -eq 0)
                {
                    $uri = $release.upload_url -replace "\{\?name,label\}", "?name=$($file.Name)"
                }
                else
                {
                    if($file.Extension -eq '.zip' -and $Artifact.Count -eq 1)
                    {
                        $Name = $Name -replace "-" , " " -replace "    " , " " -replace "   " , " " -replace "  " , " " -replace " " , "."
                        $fileName = (($Name)+($file.Extension))
    
                        $uri = $release.upload_url -replace "\{\?name,label\}", "?name=$($fileName)"
                        
                    }
                    else {
                        $uri = $release.upload_url -replace "\{\?name,label\}", "?name=$($file.Name)"
                    }

                }
                $assetParams = @{
                    Uri         = $uri
                    Method      = 'POST'
                    Headers     = @{
                        Authorization = 'Basic ' + [Convert]::ToBase64String(
                            [Text.Encoding]::ASCII.GetBytes($AccessToken + ":x-oauth-basic")
                        )
                    }
                    ContentType = "application/octet-stream"
                    Body        = $body
                }

                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-RestMethod @assetParams
                }
                catch {
                    throw $_
                }
            }
        }
    }

    end {
        #### Update release
        $body = @{ "name" = $Title }
        if ($PSBoundParameters.ContainsKey("TargetCommit"))
        {
            $body["target_commitish"] = $TargetCommit
        }
        $updateParams = @{
            Uri         = "https://api.github.com/repos/{0}/{1}/releases/{2}" -f $RepositoryOwner, $RepositoryName, $release.id
            Method      = 'PATCH'
            Headers     = @{
                Authorization = 'Basic ' + [Convert]::ToBase64String(
                    [Text.Encoding]::ASCII.GetBytes($AccessToken + ":x-oauth-basic")
                )
            }
            ContentType = 'application/json'
            Body        = $body | ConvertTo-Json
            ErrorAction = "Stop"
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Output "Update params: " $updateParams    
        $release = Invoke-RestMethod @updateParams
    }
}

function GetArtifacts {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $mask = "Apps",
        [string] $branch = "main",
        [string] $projects,
        [string] $version
    )

    $headers = GetHeader -token $token
    $allArtifacts = @()
    $per_page = 100
    $page = 1
    if ($version -eq 'latest') { $version = '*' }
    Write-Host "Analyzing artifacts"
    do {
        $uri = "$api_url/repos/$repository/actions/artifacts?per_page=$($per_page)&page=$($page)"
        Write-Host $uri
        $artifacts = InvokeWebRequest -UseBasicParsing -Headers $headers -Uri $uri | ConvertFrom-Json
        $page++
        $allArtifacts += @($artifacts.artifacts | Where-Object { $_.name -like "*-$branch-$mask-$version" })
        $result = @()
        $allArtifactsFound = $true
        $projects.Split(',') | ForEach-Object {
            $project = $_.Replace('\','_')
            Write-Host "project '$project'"
        
            $projectArtifact = $allArtifacts | Where-Object { $_.name -like "$project-$branch-$mask-$version" } | Select-Object -First 1
            if ($projectArtifact) {
                $result += @($projectArtifact)
            }
            else {
                $allArtifactsFound = $false
                $result = @()
            }
        }
    } while (!$allArtifactsFound -and $artifacts.total_count -gt $page*$per_page)
    $result
}

function DownloadArtifact {
    Param(
        [string] $token,
        [string] $path,
        $artifact
    )

    Write-Host "Downloading artifact $($artifact.Name)"
    Write-Host $artifact.archive_download_url
    if ([string]::IsNullOrEmpty($token)) {
        $authstatus = (invoke-gh -silent -returnValue auth status --show-token) -join " "
        $token = $authStatus.SubString($authstatus.IndexOf('Token: ')+7).Trim()
    }
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.v3+json"
    }
    $outFile = Join-Path $path "$($artifact.Name).zip"
    InvokeWebRequest -Headers $headers -Uri $artifact.archive_download_url -OutFile $outFile
    $outFile
}    

function Get-ActionContext {
    [CmdletBinding()]
    param()

    $context = $script:actionContext
    if (-not $context) {
        $context = [pscustomobject]::new()
        $context.PSObject.TypeNames.Insert(0, "GitHub.Context")
        $contextProps = BuildActionContextMap
        AddReadOnlyProps $context $contextProps
        $script:actionContext = $context
    }
    $context
}

function Get-ActionRepo {
    [CmdletBinding()]
    param()

    $repo = $script:actionContextRepo
    if (-not $repo) {
        $repo = [pscustomobject]::new()
        $repo.PSObject.TypeNames.Insert(0, "GitHub.ContextRepo")
        $repoProps = BuildActionContextRepoMap
        AddReadOnlyProps $repo $repoProps
        $script:actionContextRepo = $repo
    }
    $repo
}

function Get-ActionIssue {
    [CmdletBinding()]
    param()

    $issue = $script:actionContextIssue
    if (-not $issue) {
        $issue = [pscustomobject]::new()
        $issue.PSObject.TypeNames.Insert(0, "GitHub.ContextIssue")
        $issueProps = BuildActionContextIssueMap
        AddReadOnlyProps $issue $issueProps
        $script:actionContextIssue = $issue
    }
    $issue
}
function ConvertTo-HashTable {
    [CmdletBinding()]
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object
    )
    $ht = @{}
    if ($object) {
        $object.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    }
    $ht
}
function BuildActionContextMap {
    [CmdletBinding()]
    param()

    Write-Verbose "Building Action Context"

    if ($env:GITHUB_EVENT_PATH) {
        $path = $env:GITHUB_EVENT_PATH
        Write-Verbose "Loading event payload from [$path]"
        if (Test-Path -PathType Leaf $path) {
            ## Webhook payload object that triggered the workflow
            $payload = (Get-Content -Raw $path -Encoding utf8) |
                ConvertFrom-Json |ConvertTo-HashTable
        }
        else {
            Write-Warning "`GITHUB_EVENT_PATH` [$path] does not eixst"
        }
    }

    @{
        _resolveDatetime = [datetime]::Now

        EventName = $env:GITHUB_EVENT_NAME
        Sha = $env:GITHUB_SHA
        Ref = $env:GITHUB_REF
        Workflow = $env:GITHUB_WORKFLOW
        Action = $env:GITHUB_ACTION
        Actor = $env:GITHUB_ACTOR
        Job = $env:GITHUB_JOB
        RunNumber = ParseIntSafely $env:GITHUB_RUN_NUMBER
        RunId = $Env:GITHUB_RUN_ID
        Repo = $Env:GITHUB_REPOSITORY
        Token = $Env:GITHUB_TOKEN
        Payload = $payload
    }
}

function BuildActionContextRepoMap {
    [CmdletBinding()]
    param()

    Write-Verbose "Building Action Context Repo"

    if ($env:GITHUB_REPOSITORY) {
        Write-Verbose "Resolving Repo via env GITHUB_REPOSITORY"
        ($owner, $repo) = $env:GITHUB_REPOSITORY -split '/',2
        return @{
            _resolveDatetime = [datetime]::Now

            Owner = $owner
            Repo = $repo
        }
    }

    $context = Get-ActionContext
    if ($context.Payload.repository) {
        Write-Verbose "Resolving Repo via Action Context"
        return @{
            _resolveDatetime = [datetime]::Now

            Owner = $context.Payload.repository.owner.login
            Repo = $context.Payload.repository.name
        }
    }

    throw "context.repo requires a GITHUB_REPOSITORY environment variable like 'owner/repo'"
}

function BuildActionContextIssueMap {
    [CmdletBinding()]
    param()

    Write-Verbose "Building Action Context Issue"

    $context = Get-ActionContext
    (BuildActionContextRepoMap) + @{
        Number = ($context.Payload).number
    }
}

function ParseIntSafely {
    param(
        [object]$value,
        [int]$default=-1
    )

    [int]$int = 0
    if (-not [int]::TryParse($value, [ref]$int)) {
        $int = $default
    }
    $int
}

function AddReadOnlyProps {
    param(
        [pscustomobject]$psco,
        [hashtable]$props
    )

    $props.GetEnumerator() | ForEach-Object {
        $propName = $_.Key
        $propValue = $_.Value

        if ($propValue -and ($propValue -is [hashtable])) {
            $newPropValue = [pscustomobject]::new()
            AddReadOnlyProps $newPropValue $propValue
            $propValue = $newPropValue
        }

        $psco | Add-Member -Name $propName -MemberType ScriptProperty -Value {
            $propValue
        }.GetNewClosure() -SecondValue {
            Write-Warning "Cannot modify Read-only property '$($propName)'"
        }.GetNewClosure()
    }
}

function Test-CronExpression
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Expression,
        [int]
        $WithDelayMinutes = 0,

        [Parameter()]
        $DateTime = $null
    )



    # current time
    if ($null -eq $DateTime) {
        $DateTime = [datetime]::Now
    }

    if($WithDelayMinutes)
    {   
        for(($digit = $WithDelayMinutes * -1);$digit -le $WithDelayMinutes; $digit++)
        {
            if(Test-CronExpression -Expression $Expression -DateTime ($DateTime.AddMinutes($digit)))
            {
                return $true
            }
        }
    }


    # convert the expression
    $Atoms = ConvertFrom-CronExpression -Expression $Expression

    # check day of month
    if (!(Test-RangeAndValue -AtomContraint $Atoms.DayOfMonth -NowValue $DateTime.Day)) {
        return $false
    }

    # check day of week
    if (!(Test-RangeAndValue -AtomContraint $Atoms.DayOfWeek -NowValue ([int]$DateTime.DayOfWeek))) {
        return $false
    }

    # check month
    if (!(Test-RangeAndValue -AtomContraint $Atoms.Month -NowValue $DateTime.Month)) {
        return $false
    }

    # check hour
    if (!(Test-RangeAndValue -AtomContraint $Atoms.Hour -NowValue $DateTime.Hour)) {
        return $false
    }

    # check minute
    if (!(Test-RangeAndValue -AtomContraint $Atoms.Minute -NowValue $DateTime.Minute)) {
        return $false
    }

    # date is valid
    return $true
}

function Get-CronFields
{
    return @(
        'Minute',
        'Hour',
        'DayOfMonth',
        'Month',
        'DayOfWeek'
    )
}

function Get-CronFieldConstraints
{
    return @{
        'MinMax' = @(
            @(0, 59),
            @(0, 23),
            @(1, 31),
            @(1, 12),
            @(0, 6)
        );
        'DaysInMonths' = @(
            31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
        );
        'Months' = @(
            'January', 'February', 'March', 'April', 'May', 'June', 'July',
            'August', 'September', 'October', 'November', 'December'
        )
    }
}

function Get-CronPredefined
{
    return @{
        # normal
        '@minutely' = '* * * * *';
        '@hourly' = '0 * * * *';
        '@daily' = '0 0 * * *';
        '@weekly' = '0 0 * * 0';
        '@monthly' = '0 0 1 * *';
        '@quarterly' = '0 0 1 1,4,7,10';
        '@yearly' = '0 0 1 1 *';
        '@annually' = '0 0 1 1 *';

        # twice
        '@semihourly' = '0,30 * * * *';
        '@semidaily' = '0 0,12 * * *';
        '@semiweekly' = '0 0 * * 0,4';
        '@semimonthly' = '0 0 1,15 * *';
        '@semiyearly' = '0 0 1 1,6 *';
        '@semiannually' = '0 0 1 1,6 *';
    }
}

function Get-CronFieldAliases
{
    return @{
        'Month' = @{
            'Jan' = 1;
            'Feb' = 2;
            'Mar' = 3;
            'Apr' = 4;
            'May' = 5;
            'Jun' = 6;
            'Jul' = 7;
            'Aug' = 8;
            'Sep' = 9;
            'Oct' = 10;
            'Nov' = 11;
            'Dec' = 12;
        };
        'DayOfWeek' = @{
            'Sun' = 0;
            'Mon' = 1;
            'Tue' = 2;
            'Wed' = 3;
            'Thu' = 4;
            'Fri' = 5;
            'Sat' = 6;
        };
    }
}

function ConvertFrom-CronExpression
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Expression
    )

    $Expression = $Expression.Trim()

    # check predefineds
    $predef = Get-CronPredefined
    if ($null -ne $predef[$Expression]) {
        $Expression = $predef[$Expression]
    }

    # split and check atoms length
    $atoms = @($Expression -isplit '\s+')
    if ($atoms.Length -ne 5) {
        throw "Cron expression should only consist of 5 parts: $($Expression)"
    }

    # basic variables
    $aliasRgx = '(?<tag>[a-z]{3})'

    # get cron obj and validate atoms
    $fields = Get-CronFields
    $constraints = Get-CronFieldConstraints
    $aliases = Get-CronFieldAliases
    $cron = @{}

    for ($i = 0; $i -lt $atoms.Length; $i++)
    {
        $_cronExp = @{
            'Range' = $null;
            'Values' = $null;
        }

        $_atom = $atoms[$i]
        $_field = $fields[$i]
        $_constraint = $constraints.MinMax[$i]
        $_aliases = $aliases[$_field]

        # replace day of week and months with numbers
        switch ($_field)
        {
            { $_field -ieq 'month' -or $_field -ieq 'dayofweek' }
                {
                    while ($_atom -imatch $aliasRgx) {
                        $_alias = $_aliases[$Matches['tag']]
                        if ($null -eq $_alias) {
                            throw "Invalid $($_field) alias found: $($Matches['tag'])"
                        }

                        $_atom = $_atom -ireplace $Matches['tag'], $_alias
                        $_atom -imatch $aliasRgx | Out-Null
                    }
                }
        }

        # ensure atom is a valid value
        if (!($_atom -imatch '^[\d|/|*|\-|,]+$')) {
            throw "Invalid atom character: $($_atom)"
        }

        # replace * with min/max constraint
        $_atom = $_atom -ireplace '\*', ($_constraint -join '-')

        # parse the atom for either a literal, range, array, or interval
        # literal
        if ($_atom -imatch '^\d+$') {
            $_cronExp.Values = @([int]$_atom)
        }

        # range
        elseif ($_atom -imatch '^(?<min>\d+)\-(?<max>\d+)$') {
            $_cronExp.Range = @{ 'Min' = [int]($Matches['min'].Trim()); 'Max' = [int]($Matches['max'].Trim()); }
        }

        # array
        elseif ($_atom -imatch '^[\d,]+$') {
            $_cronExp.Values = [int[]](@($_atom -split ',').Trim())
        }

        # interval
        elseif ($_atom -imatch '(?<start>(\d+|\*))\/(?<interval>\d+)$') {
            $start = $Matches['start']
            $interval = [int]$Matches['interval']

            if ($interval -ieq 0) {
                $interval = 1
            }

            if ([string]::IsNullOrWhiteSpace($start) -or $start -ieq '*') {
                $start = 0
            }

            $start = [int]$start
            $_cronExp.Values = @($start)

            $next = $start + $interval
            while ($next -le $_constraint[1]) {
                $_cronExp.Values += $next
                $next += $interval
            }
        }

        # error
        else {
            throw "Invalid cron atom format found: $($_atom)"
        }

        # ensure cron expression values are valid
        if ($null -ne $_cronExp.Range) {
            if ($_cronExp.Range.Min -gt $_cronExp.Range.Max) {
                throw "Min value for $($_field) should not be greater than the max value"
            }

            if ($_cronExp.Range.Min -lt $_constraint[0]) {
                throw "Min value '$($_cronExp.Range.Min)' for $($_field) is invalid, should be greater than/equal to $($_constraint[0])"
            }

            if ($_cronExp.Range.Max -gt $_constraint[1]) {
                throw "Max value '$($_cronExp.Range.Max)' for $($_field) is invalid, should be less than/equal to $($_constraint[1])"
            }
        }

        if ($null -ne $_cronExp.Values) {
            $_cronExp.Values | ForEach-Object {
                if ($_ -lt $_constraint[0] -or $_ -gt $_constraint[1]) {
                    throw "Value '$($_)' for $($_field) is invalid, should be between $($_constraint[0]) and $($_constraint[1])"
                }
            }
        }

        # assign value
        $cron[$_field] = $_cronExp
    }

    # post validation for month/days in month
    if ($null -ne $cron['Month'].Values -and $null -ne $cron['DayOfMonth'].Values)
    {
        foreach ($mon in $cron['Month'].Values) {
            foreach ($day in $cron['DayOfMonth'].Values) {
                if ($day -gt $constraints.DaysInMonths[$mon - 1]) {
                    throw "$($constraints.Months[$mon - 1]) only has $($constraints.DaysInMonths[$mon - 1]) days, but $($day) was supplied"
                }
            }
        }

    }

    # return the parsed cron expression
    return $cron
}

function Test-RangeAndValue($AtomContraint, $NowValue) {
    if ($null -ne $AtomContraint.Range) {
        if ($NowValue -lt $AtomContraint.Range.Min -or $NowValue -gt $AtomContraint.Range.Max) {
            return $false
        }
    }
    elseif ($AtomContraint.Values -inotcontains $NowValue) {
        return $false
    }

    return $true
}

function Update-SessionEnvironment {
<#
.SYNOPSIS
Updates the environment variables of the current powershell session with
any environment variable changes that may have occured during a
Chocolatey package install.
.DESCRIPTION
When Chocolatey installs a package, the package author may add or change
certain environment variables that will affect how the application runs
or how it is accessed. Often, these changes are not visible to the
current PowerShell session. This means the user needs to open a new
PowerShell session before these settings take effect which can render
the installed application nonfunctional until that time.
Use the Update-SessionEnvironment command to refresh the current
PowerShell session with all environment settings possibly performed by
Chocolatey package installs.
.NOTES
This method is also added to the user's PowerShell profile as
`refreshenv`. When called as `refreshenv`, the method will provide
additional output.
Preserves `PSModulePath` as set by the process starting in 0.9.10.
.INPUTS
None
.OUTPUTS
None
#>

  $refreshEnv = $false
  $invocation = $MyInvocation
  if ($invocation.InvocationName -eq 'refreshenv') {
    $refreshEnv = $true
  }

  if ($refreshEnv) {
    Write-Output 'Refreshing environment variables from the registry for powershell.exe. Please wait...'
  } else {
    Write-Verbose 'Refreshing environment variables from the registry.'
  }

  $userName = $env:USERNAME
  $architecture = $env:PROCESSOR_ARCHITECTURE
  $psModulePath = $env:PSModulePath

  #ordering is important here, $user should override $machine...
  $ScopeList = 'Process', 'Machine'
  if ('SYSTEM', "${env:COMPUTERNAME}`$" -notcontains $userName) {
    # but only if not running as the SYSTEM/machine in which case user can be ignored.
    $ScopeList += 'User'
  }
  foreach ($Scope in $ScopeList) {
    Get-EnvironmentVariableNames -Scope $Scope |
        ForEach-Object {
          Set-Item "Env:$_" -Value (Get-EnvironmentVariable -Scope $Scope -Name $_)
        }
  }

  #Path gets special treatment b/c it munges the two together
  $paths = 'Machine', 'User' |
    ForEach-Object {
      (Get-EnvironmentVariable -Name 'PATH' -Scope $_) -split ';'
    } |
    Select-Object -Unique
  $Env:PATH = $paths -join ';'

  # PSModulePath is almost always updated by process, so we want to preserve it.
  $env:PSModulePath = $psModulePath

  # reset user and architecture
  if ($userName) { $env:USERNAME = $userName; }
  if ($architecture) { $env:PROCESSOR_ARCHITECTURE = $architecture; }

  if ($refreshEnv) {
    Write-Output 'Finished'
  }
}

function Test-Property {
    Param(
        [HashTable] $json,
        [string] $key,
        [switch] $must,
        [switch] $should,
        [switch] $maynot,
        [switch] $shouldnot
    )

    $exists = $json.ContainsKey($key)
    if ($exists) {
        if ($maynot) {
            Write-Host "::Error::Property '$key' may not exist in $settingsFile"
        }
        elseif ($shouldnot) {
            Write-Host "::Warning::Property '$key' should not exist in $settingsFile"
        }
    }
    else {
        if ($must) {
            Write-Host "::Error::Property '$key' must exist in $settingsFile"
        }
        elseif ($should) {
            Write-Host "::Warning::Property '$key' should exist in $settingsFile"
        }
    }
}

function Test-Json {
    Param(
        [string] $jsonFile,
        [string] $baseFolder,
        [switch] $repo
    )

    $settingsFile = $jsonFile.Substring($baseFolder.Length)
    if ($repo) {
        Write-Host "Checking FSC-PS Repo Settings file $settingsFile"
    }
    else {
        Write-Host "Checking FSC-PS Settings file $settingsFile"
    }

    try {
        $json = Get-Content -Path $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
        if ($repo) {
            Test-Property -settingsFile $settingsFile -json $json -key 'templateUrl' -should
        }
        else {
            Test-Property -settingsFile $settingsFile -json $json -key 'templateUrl' -maynot
            'nextMajorSchedule','nextMinorSchedule','currentSchedule','githubRunner','runs-on' | ForEach-Object {
                Test-Property -settingsFile $settingsFile -json $json -key $_ -shouldnot
            }
        }
    }
    catch {
        Write-Host "::Error::$($_.Exception.Message)"
    }
}

function Test-FnSCMRepository {
    Param(
        [string] $baseFolder
    )

    # Test .json files are formatted correctly
    Get-ChildItem -Path $baseFolder -Filter '*.json' -Recurse | ForEach-Object {
        if ($_.FullName -like '*\.FSC-PS\Settings.json') {
            Test-Json -jsonFile $_.FullName -baseFolder $baseFolder
        }
        elseif ($_.FullName -like '*\.github\*Settings.json') {
            Test-Json -jsonFile $_.FullName -baseFolder $baseFolder -repo:($_.BaseName -eq "FSC-PS-Settings")
        }
    }
}

function Write-Big {
Param(
    [string] $str
)
$chars = @{
"0" = @'
   ___  
  / _ \ 
 | | | |
 | | | |
 | |_| |
  \___/ 
'@.Split("`n")
"1" = @'
  __
 /_ |
  | |
  | |
  | |
  |_|
'@.Split("`n")
"2" = @'
  ___  
 |__ \ 
    ) |
   / / 
  / /_ 
 |____|
'@.Split("`n")
"3" = @'
  ____  
 |___ \ 
   __) |
  |__ < 
  ___) |
 |____/ 
'@.Split("`n")
"4" = @'
  _  _   
 | || |  
 | || |_ 
 |__   _|
    | |  
    |_|  
'@.Split("`n")
"5" = @'
  _____ 
 | ____|
 | |__  
 |___ \ 
  ___) |
 |____/ 
'@.Split("`n")
"6" = @'
    __  
   / /  
  / /_  
 | '_ \ 
 | (_) |
  \___/ 
'@.Split("`n")
"7" = @'
  ______ 
 |____  |
     / / 
    / /  
   / /   
  /_/    
'@.Split("`n")
"8" = @'
   ___  
  / _ \ 
 | (_) |
  > _ < 
 | (_) |
  \___/ 
'@.Split("`n")
"9" = @'
   ___  
  / _ \ 
 | (_) |
  \__, |
    / / 
   /_/  
'@.Split("`n")
"." = @'
    
    
    
    
  _ 
 (_)
'@.Split("`n")
"v" = @'
        
        
 __   __
 \ \ / /
  \ V / 
   \_(_)
'@.Split("`n")
"p" = @'
  _____                _               
 |  __ \              (_)              
 | |__) | __ _____   ___  _____      __
 |  ___/ '__/ _ \ \ / / |/ _ \ \ /\ / /
 | |   | | |  __/\ V /| |  __/\ V  V / 
 |_|   |_|  \___| \_/ |_|\___| \_/\_/  
'@.Split("`n")
"d" = @'
  _____             
 |  __ \            
 | |  | | _____   __
 | |  | |/ _ \ \ / /
 | |__| |  __/\ V / 
 |_____/ \___| \_(_)
'@.Split("`n")
}


0..5 | ForEach-Object {
    $line = $_
    $str.ToCharArray() | ForEach-Object {
        $ch = $chars."$_"
        if ($ch) {
            Write-Host -noNewline $ch[$line]
        }
    }
    Write-Host
}
}