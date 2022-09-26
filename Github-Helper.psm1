function Get-dependencies {
    Param(
        $probingPathsJson,
        $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $saveToPath = (Join-Path $ENV:GITHUB_WORKSPACE "dependencies"),
        [string] $mask = "-Apps-"
    )

    if (!(Test-Path $saveToPath)) {
        New-Item $saveToPath -ItemType Directory | Out-Null
    }

    Write-Host "Getting all the artifacts from probing paths"
    $downloadedList = @()
    $probingPathsJson | ForEach-Object {
        $dependency = $_

        if (-not ($dependency.PsObject.Properties.name -eq "repo")) {
            throw "AppDependencyProbingPaths needs to contain a repo property, pointing to the repository on which you have a dependency"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "AuthTokenSecret")) {
            $dependency | Add-Member -name "AuthTokenSecret" -MemberType NoteProperty -Value $token
        }
        if (-not ($dependency.PsObject.Properties.name -eq "Version")) {
            $dependency | Add-Member -name "Version" -MemberType NoteProperty -Value "latest"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "Projects")) {
            $dependency | Add-Member -name "Projects" -MemberType NoteProperty -Value "*"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "release_status")) {
            $dependency | Add-Member -name "release_status" -MemberType NoteProperty -Value "release"
        }

        # TODO better error messages

        $repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")
        if ($dependency.release_status -eq "latestBuild") {

            # TODO it should check the branch and limit to a certain branch

            Write-Host "Getting artifacts from $($dependency.repo)"
            $artifacts = GetArtifacts -token $dependency.authTokenSecret -api_url $api_url -repository $repository -mask $mask
            if ($dependency.version -ne "latest") {
                $artifacts = $artifacts | Where-Object { ($_.tag_name -eq $dependency.version) }
            }    
                
            $artifact = $artifacts | Select-Object -First 1
            if ($artifact) {
                $download = DownloadArtifact -path $saveToPath -token $dependency.authTokenSecret -artifact $artifact
            }
            else {
                Write-Host -ForegroundColor Red "Could not find any artifacts that matches '*$mask*'"
            }
        }
        else {

            Write-Host "Getting releases from $($dependency.repo)"
            $releases = GetReleases -api_url $api_url -token $dependency.authTokenSecret -repository $repository
            if ($dependency.version -ne "latest") {
                $releases = $releases | Where-Object { ($_.tag_name -eq $dependency.version) }
            }

            switch ($dependency.release_status) {
                "release" { $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft ) } | Select-Object -First 1 }
                "prerelease" { $release = $releases | Where-Object { ($_.prerelease ) } | Select-Object -First 1 }
                "draft" { $release = $releases | Where-Object { ($_.draft ) } | Select-Object -First 1 }
                Default { throw "Invalid release status '$($dependency.release_status)' is encountered." }
            }

            if (!($release)) {
                throw "Could not find a release that matches the criteria."
            }
                
            $projects = $dependency.projects
            if ([string]::IsNullOrEmpty($dependency.projects)) {
                $projects = "*"
            }

            $download = DownloadRelease -token $dependency.authTokenSecret -projects $projects -api_url $api_url -repository $repository -path $saveToPath -release $release -mask $mask
        }
        if ($download) {
            $downloadedList += $download
        }
    }
    
    return $downloadedList;
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
    $releases = @(Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases" | ConvertFrom-Json)
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
        [string] $accept = "application/json"
    )
    $headers = @{ "Accept" = $accept }
    if (![string]::IsNullOrEmpty($token)) {
        $headers["Authorization"] = "token $token"
    }

    return $headers
}

function GetReleaseNotes {
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

    Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Method POST -Body ($postParams | ConvertTo-Json) -Uri "$api_url/repos/$repository/releases/generate-notes" 
}

function GetLatestRelease {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )
    
    Write-Host "Getting the latest release from $api_url/repos/$repository/releases/latest"
    try {
        Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases/latest" | ConvertFrom-Json
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
        [string] $mask = "-Apps-",
        $release
    )

    if ($projects -eq "") { $projects = "*" }
    Write-Host "Downloading release $($release.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/octet-stream"
    }
    $projects.Split(',') | ForEach-Object {
        $project = $_
        Write-Host "project '$project'"
        
        $release.assets | Where-Object { $_.name -like "$project$mask*.zip" } | ForEach-Object {
            Write-Host "$api_url/repos/$repository/releases/assets/$($_.id)"
            $filename = Join-Path $path $_.name
            Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "$api_url/repos/$repository/releases/assets/$($_.id)" -OutFile $filename 
            return $filename
        }
    }
}       

function GetArtifacts {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $mask = "-Apps-"
    )

    Write-Host "Analyzing artifacts"
    $artifacts = Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/actions/artifacts" | ConvertFrom-Json
    $artifacts.artifacts | Where-Object { $_.name -like "*$($mask)*" }
}

function DownloadArtifact {
    Param(
        [string] $token,
        [string] $path,
        $artifact
    )

    Write-Host "Downloading artifact $($artifact.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.v3+json"
    }
    $outFile = Join-Path $path "$($artifact.Name).zip"
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $artifact.archive_download_url -OutFile $outFile
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

<#
.SYNOPSIS
Returns details of the repository, including owner and repo name.
#>
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

<#
.SYNOPSIS
Returns details of the issue associated with the workflow trigger,
including owner and repo name, and the issue (or PR) number.
#>
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


function install-gh
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)]
        [ValidateSet('Install','Uninstall','Repair')]
        [string]$DeploymentType = 'Install',
        [Parameter(Mandatory=$false)]
        [ValidateSet('Interactive','Silent','NonInteractive')]
        [string]$DeployMode = 'Interactive',
        [Parameter(Mandatory=$false)]
        [switch]$AllowRebootPassThru = $false,
        [Parameter(Mandatory=$false)]
        [switch]$TerminalServerMode = $false,
        [Parameter(Mandatory=$false)]
        [switch]$DisableLogging = $false
    )
    Try {
        ## Set the script execution policy for this process
        Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}
        ##*===============================================
        ##* VARIABLE DECLARATION
        ##*===============================================
        ## Variables: Application
        [string]$appVendor = ''
        [string]$appName = 'GitHub CLI'
        [string]$appVersion = ''
        [string]$appArch = ''
        [string]$appLang = ''
        [string]$appRevision = ''
        [string]$appScriptVersion = '1.0.0'
        [string]$appScriptDate = 'XX/XX/20XX'
        [string]$appScriptAuthor = 'Jason Bergner'
        ##*===============================================
        ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
        [string]$installName = ''
        [string]$installTitle = 'GitHub CLI'
        ##* Do not modify section below
        #region DoNotModify
        ## Variables: Exit Code
        [int32]$mainExitCode = 0
        ## Variables: Script
        [string]$deployAppScriptFriendlyName = 'Deploy Application'
        [version]$deployAppScriptVersion = [version]'3.8.4'
        [string]$deployAppScriptDate = '26/01/2021'
        [hashtable]$deployAppScriptParameters = $psBoundParameters
        ## Variables: Environment
        If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }

        #endregion
        ##* Do not modify section above
        ##*===============================================
        ##* END VARIABLE DECLARATION
        ##*===============================================
        If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
            ##*===============================================
            ##* PRE-INSTALLATION
            ##*===============================================
            [string]$installPhase = 'Pre-Installation'
            ## Show Welcome Message
            Show-InstallationWelcome
            ## Show Progress Message (With a Message to Indicate the Application is Being Installed)
            Show-InstallationProgress -StatusMessage "Removing Any Existing Version of GitHub CLI. Please Wait..."
            ## Remove Any Existing Version of GitHub CLI
            Remove-MSIApplications -Name "GitHub CLI"
   
            ##*===============================================
            ##* INSTALLATION
            ##*===============================================
            [string]$installPhase = 'Installation'
            ## Install GitHub CLI
            $MsiPath = Get-ChildItem -Path "$dirFiles" -Include gh*.msi -File -Recurse -ErrorAction SilentlyContinue
            $Transform = Get-ChildItem -Path "$dirFiles" -Include *.mst -File -Recurse -ErrorAction SilentlyContinue
            If(($MsiPath.Exists) -and ($Transform.Exists))
            {
            Write-Host -Message "Found $($MsiPath.FullName) and $($Transform.FullName), now attempting to install $installTitle."
            Show-InstallationProgress "Installing GitHub CLI. This may take some time. Please wait..."
            Execute-MSI -Action Install -Path "$MsiPath" -AddParameters "TRANSFORMS=$Transform"
            }
            ElseIf ($MsiPath.Exists)
            {
            Write-Host -Message "Found $($MsiPath.FullName), now attempting to install $installTitle."
            Show-InstallationProgress "Installing GitHub CLI. This may take some time. Please wait..."
            Execute-MSI -Action Install -Path "$MsiPath"
            }
       
            ##*===============================================
            ##* POST-INSTALLATION
            ##*===============================================
            [string]$installPhase = 'Post-Installation'
        }
        ElseIf ($deploymentType -ieq 'Uninstall')
        {
            ##*===============================================
            ##* PRE-UNINSTALLATION
            ##*===============================================
            [string]$installPhase = 'Pre-Uninstallation'
            ## Show Welcome Message
            Show-InstallationWelcome
            ## Show Progress Message (With a Message to Indicate the Application is Being Uninstalled)
            Show-InstallationProgress -StatusMessage "Uninstalling $installTitle. Please Wait..."
            ##*===============================================
            ##* UNINSTALLATION
            ##*===============================================
            [string]$installPhase = 'Uninstallation'
            ## Uninstall Any Existing Version of GitHub CLI
            Remove-MSIApplications -Name "GitHub CLI"
            ##*===============================================
            ##* POST-UNINSTALLATION
            ##*===============================================
            [string]$installPhase = 'Post-Uninstallation'
        }
        ElseIf ($deploymentType -ieq 'Repair')
        {
            ##*===============================================
            ##* PRE-REPAIR
            ##*===============================================
            [string]$installPhase = 'Pre-Repair'
            ##*===============================================
            ##* REPAIR
            ##*===============================================
            [string]$installPhase = 'Repair'
            ##*===============================================
            ##* POST-REPAIR
            ##*===============================================
            [string]$installPhase = 'Post-Repair'
        }
        ##*===============================================
        ##* END SCRIPT BODY
        ##*===============================================
        ## Call the Exit-Script function to perform final cleanup operations
        Exit-Script -ExitCode $mainExitCode
    }
    Catch {
        [int32]$mainExitCode = 60001
        [string]$mainErrorMessage = "$(Resolve-Error)"
        Write-Host -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
        Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
        Exit-Script -ExitCode $mainExitCode
    }

}