Param(
    [switch] $local
)

$gitHubHelperPath = Join-Path $PSScriptRoot 'Github-Helper.psm1'
if (Test-Path $gitHubHelperPath) {
    Import-Module $gitHubHelperPath
}

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$FnSCMFolder = ".FnSCM-Go\"
$FnSCMSettingsFile = ".FnSCM-Go\settings.json"
$RepoSettingsFile = ".github\FnSCM-Go-Settings.json"
$runningLocal = $local.IsPresent

$MicrosoftTelemetryConnectionString = "InstrumentationKey=84bd9223-67d4-4378-8590-9e4a46023be2;IngestionEndpoint=https://westeurope-1.in.applicationinsights.azure.com/"

function invoke-git {
    Param(
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    Write-Host -ForegroundColor Yellow "git $command $remaining"
    git $command $remaining
    if ($lastexitcode) { throw "git $command error" }
}

function invoke-gh {
    Param(
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    Write-Host -ForegroundColor Yellow "gh $command $remaining"
    $ErrorActionPreference = "SilentlyContinue"
    gh $command $remaining
    $ErrorActionPreference = "Stop"
    if ($lastexitcode) { throw "gh $command error" }
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

function OutputError {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        throw $message
    }
    else {
        Write-Host "::Error::$message"
        $host.SetShouldExit(1)
    }
}

function OutputWarning {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host -ForegroundColor Yellow "WARNING: $message"
    }
    else {
        Write-Host "::Warning::$message"
    }
}

function MaskValueInLog {
    Param(
        [string] $value
    )

    if (!$runningLocal) {
        Write-Host "::add-mask::$value"
    }
}

function OutputDebug {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host $message
    }
    else {
        Write-Host "::Debug::$message"
    }
}

function GetUniqueFolderName {
    Param(
        [string] $baseFolder,
        [string] $folderName
    )

    $i = 2
    $name = $folderName
    while (Test-Path (Join-Path $baseFolder $name)) {
        $name = "$folderName($i)"
        $i++
    }
    $name
}

function stringToInt {
    Param(
        [string] $str,
        [int] $default = -1
    )

    $i = 0
    if ([int]::TryParse($str.Trim(), [ref] $i)) { 
        $i
    }
    else {
        $default
    }
}

function Expand-7zipArchive {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [string] $DestinationPath
    )

    $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

    $use7zip = $false
    if (Test-Path -Path $7zipPath -PathType Leaf) {
        try {
            $use7zip = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($7zipPath).FileMajorPart -ge 19
        }
        catch {
            $use7zip = $false
        }
    }

    if ($use7zip) {
        OutputDebug -message "Using 7zip"
        Set-Alias -Name 7z -Value $7zipPath
        $command = '7z x "{0}" -o"{1}" -aoa -r' -f $Path, $DestinationPath
        Invoke-Expression -Command $command | Out-Null
    }
    else {
        OutputDebug -message "Using Expand-Archive"
        Expand-Archive -Path $Path -DestinationPath "$DestinationPath" -Force
    }
}

function MergeCustomObjectIntoOrderedDictionary {
    Param(
        [System.Collections.Specialized.OrderedDictionary] $dst,
        [PSCustomObject] $src
    )

    # Add missing properties in OrderedDictionary

    $src.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $prop = $_.Name
        $srcProp = $src."$prop"
        $srcPropType = $srcProp.GetType().Name
        if (-not $dst.Contains($prop)) {
            if ($srcPropType -eq "PSCustomObject") {
                $dst.Add("$prop", [ordered]@{})
            }
            elseif ($srcPropType -eq "Object[]") {
                $dst.Add("$prop", @())
            }
            else {
                $dst.Add("$prop", $srcProp)
            }
        }
    }

    @($dst.Keys) | ForEach-Object {
        $prop = $_
        if ($src.PSObject.Properties.Name -eq $prop) {
            $dstProp = $dst."$prop"
            $srcProp = $src."$prop"
            $dstPropType = $dstProp.GetType().Name
            $srcPropType = $srcProp.GetType().Name
            if ($srcPropType -eq "PSCustomObject" -and $dstPropType -eq "OrderedDictionary") {
                MergeCustomObjectIntoOrderedDictionary -dst $dst."$prop" -src $srcProp
            }
            elseif ($dstPropType -ne $srcPropType) {
                throw "property $prop should be of type $dstPropType, is $srcPropType."
            }
            else {
                if ($srcProp -is [Object[]]) {
                    $srcProp | ForEach-Object {
                        $srcElm = $_
                        $srcElmType = $srcElm.GetType().Name
                        if ($srcElmType -eq "PSCustomObject") {
                            $ht = [ordered]@{}
                            $srcElm.PSObject.Properties | Sort-Object -Property Name -Culture "iv-iv" | ForEach-Object { $ht[$_.Name] = $_.Value }
                            $dst."$prop" += @($ht)
                        }
                        else {
                            $dst."$prop" += $srcElm
                        }
                    }
                }
                else {
                    $dst."$prop" = $srcProp
                }
            }
        }
    }
}

function ReadSettings {
    Param(
        [string] $baseFolder,
        [string] $repoName = "$env:GITHUB_REPOSITORY",
        [string] $workflowName = "",
        [string] $userName = ""
    )

    $repoName = $repoName.SubString("$repoName".LastIndexOf('/') + 1)
    
    # Read Settings file
    $settings = [ordered]@{
        "type"                                   = "PTE"
        "country"                                = "us"
        "artifact"                               = ""
        "companyName"                            = ""
        "repoVersion"                            = "1.0"
        "repoName"                               = $repoName
        "versioningStrategy"                     = 0
        "runNumberOffset"                        = 0
        "appBuild"                               = 0
        "appRevision"                            = 0
        "keyVaultName"                           = ""
        "licenseFileUrlSecretName"               = "LicenseFileUrl"
        "insiderSasTokenSecretName"              = "InsiderSasToken"
        "ghTokenWorkflowSecretName"              = "GhTokenWorkflow"
        "adminCenterApiCredentialsSecretName"    = "AdminCenterApiCredentials"
        "applicationInsightsConnectionStringSecretName" = "ApplicationInsightsConnectionString"
        "keyVaultCertificateUrlSecretName"       = ""
        "keyVaultCertificatePasswordSecretName"  = ""
        "keyVaultClientIdSecretName"             = ""
        "codeSignCertificateUrlSecretName"       = "CodeSignCertificateUrl"
        "codeSignCertificatePasswordSecretName"  = "CodeSignCertificatePassword"
        "storageContextSecretName"               = "StorageContext"
        "appFolders"                             = @()
        "testDependencies"                       = @()
        "testFolders"                            = @()
        "skipUpgrade"                            = $false
        "failOn"                                 = "error"
        "doNotBuildTests"                        = $false
        "doNotRunTests"                          = $false
        "memoryLimit"                            = ""
        "templateUrl"                            = ""
        "templateBranch"                         = ""
        "githubRunner"                           = "windows-latest"
        "cacheImageName"                         = "my"
        "cacheKeepDays"                          = 3
        "alwaysBuildAllProjects"                 = $false
        "Environments"                           = @()
    }

    $gitHubFolder = ".github"
    if (!(Test-Path (Join-Path $baseFolder $gitHubFolder) -PathType Container)) {
        $RepoSettingsFile = "..\$RepoSettingsFile"
        $gitHubFolder = "..\$gitHubFolder"
    }
    $workflowName = $workflowName.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $RepoSettingsFile, $FnSCMSettingsFile, (Join-Path $gitHubFolder "$workflowName.settings.json"), (Join-Path $FnSCMFolder "$workflowName.settings.json"), (Join-Path $FnSCMFolder "$userName.settings.json") | ForEach-Object {
        $settingsFile = $_
        $settingsPath = Join-Path $baseFolder $settingsFile
        Write-Host "Checking $settingsFile"
        if (Test-Path $settingsPath) {
            try {
                Write-Host "Reading $settingsFile"
                $settingsJson = Get-Content $settingsPath -Encoding UTF8 | ConvertFrom-Json
       
                # check settingsJson.version and do modifications if needed
         
                MergeCustomObjectIntoOrderedDictionary -dst $settings -src $settingsJson

                if ($settingsJson.PSObject.Properties.Name -eq "ConditionalSettings") {
                    $settingsJson.ConditionalSettings | ForEach-Object {
                        $conditionalSetting = $_
                        if ($conditionalSetting.branches | Where-Object { $ENV:GITHUB_REF_NAME -like $_ }) {
                            Write-Host "Applying conditional settings for $ENV:GITHUB_REF_NAME"
                            MergeCustomObjectIntoOrderedDictionary -dst $settings -src $conditionalSetting.settings
                        }
                    }
                }
            }
            catch {
                throw "Settings file $settingsFile, is wrongly formatted. Error is $($_.Exception.Message)."
            }
        }
    }

    $settings
}

function AnalyzeRepo {
    Param(
        [hashTable] $settings,
        [string] $baseFolder,
        [string] $insiderSasToken,
        [switch] $doNotCheckArtifactSetting,
        [switch] $doNotIssueWarnings
    )

    if (!$runningLocal) {
        Write-Host "::group::Analyzing repository"
    }

    # Check applicationDependency
    [Version]$settings.applicationDependency | Out-null

    Write-Host "Checking type"
    if ($settings.type -eq "PTE") {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $true)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $false)
        }
    }
    elseif ($settings.type -eq "AppSource App" ) {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $false)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $true)
        }
        if ($settings.enableAppSourceCop -and (-not ($settings.appSourceCopMandatoryAffixes))) {
            throw "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $FnSCMSettingsFile"
        }
    }
    else {
        throw "The type, specified in $FnSCMSettingsFile, must be either 'Per Tenant Extension' or 'AppSource App'. It is '$($settings.type)'."
    }

    $artifact = $settings.artifact
    if ($artifact.Contains('{INSIDERSASTOKEN}')) {
        if ($insiderSasToken) {
            $artifact = $artifact.replace('{INSIDERSASTOKEN}', $insiderSasToken)
        }
        else {
            throw "Artifact definition $artifact requires you to create a secret called InsiderSasToken, containing the Insider SAS Token from https://aka.ms/collaborate"
        }
    }

    if (-not (@($settings.appFolders)+@($settings.testFolders)+@($settings.bcptTestFolders))) {
        Get-ChildItem -Path $baseFolder -Directory | Where-Object { Test-Path -Path (Join-Path $_.FullName "app.json") } | ForEach-Object {
            $folder = $_
            $appJson = Get-Content (Join-Path $folder.FullName "app.json") -Encoding UTF8 | ConvertFrom-Json
            $isTestApp = $false
            $isBcptTestApp = $false
            if ($appJson.PSObject.Properties.Name -eq "dependencies") {
                $appJson.dependencies | ForEach-Object {
                    if ($_.PSObject.Properties.Name -eq "AppId") {
                        $id = $_.AppId
                    }
                    else {
                        $id = $_.Id
                    }
                    if ($performanceToolkitApps.Contains($id)) { 
                        $isBcptTestApp = $true
                    }
                    elseif ($testRunnerApps.Contains($id)) { 
                        $isTestApp = $true
                    }
                }
            }
            if ($isBcptTestApp) {
                $settings.bcptTestFolders += @($_.Name)
            }
            elseif ($isTestApp) {
                $settings.testFolders += @($_.Name)
            }
            else {
                $settings.appFolders += @($_.Name)
            }
        }
    }

    Write-Host "Checking appFolders and testFolders"
    $dependencies = [ordered]@{}
    1..3 | ForEach-Object {
        $appFolder = $_ -eq 1
        $testFolder = $_ -eq 2
        $bcptTestFolder = $_ -eq 3
        if ($appFolder) {
            $folders = @($settings.appFolders)
            $descr = "App folder"
        }
        elseif ($testFolder) {
            $folders = @($settings.testFolders)
            $descr = "Test folder"
        }
        elseif ($bcptTestFolder) {
            $folders = @($settings.bcptTestFolders)
            $descr = "Bcpt Test folder"
        }
        else {
            throw "Internal error"
        }
        $folders | ForEach-Object {
            $folderName = $_
            if ($dependencies.Contains($folderName)) {
                throw "$descr $folderName, specified in $FnSCMSettingsFile, is specified more than once."
            }
            $folder = Join-Path $baseFolder $folderName
            $appJsonFile = Join-Path $folder "app.json"
            $bcptSuiteFile = Join-Path $folder "bcptSuite.json"
            $removeFolder = $false
            if (-not (Test-Path $folder -PathType Container)) {
                if (!$doNotIssueWarnings) { OutputWarning -message "$descr $folderName, specified in $FnSCMSettingsFile, does not exist" }
                $removeFolder = $true
            }
            elseif (-not (Test-Path $appJsonFile -PathType Leaf)) {
                if (!$doNotIssueWarnings) { OutputWarning -message "$descr $folderName, specified in $FnSCMSettingsFile, does not contain the source code for an app (no app.json file)" }
                $removeFolder = $true
            }
            elseif ($bcptTestFolder -and (-not (Test-Path $bcptSuiteFile -PathType Leaf))) {
                if (!$doNotIssueWarnings) { OutputWarning -message "$descr $folderName, specified in $FnSCMSettingsFile, does not contain a BCPT Suite (bcptSuite.json)" }
                $removeFolder = $true
            }
            if ($removeFolder) {
                if ($appFolder) {
                    $settings.appFolders = @($settings.appFolders | Where-Object { $_ -ne $folderName })
                }
                elseif ($testFolder) {
                    $settings.testFolders = @($settings.testFolders | Where-Object { $_ -ne $folderName })
                }
                elseif ($bcptTestFolder) {
                    $settings.bcptTestFolders = @($settings.bcptTestFolders | Where-Object { $_ -ne $folderName })
                }
            }
            else {
                $dependencies.Add("$folderName", @())
                try {
                    $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                    if ($appJson.PSObject.Properties.Name -eq 'Dependencies') {
                        $appJson.dependencies | ForEach-Object {
                            if ($_.PSObject.Properties.Name -eq "AppId") {
                                $id = $_.AppId
                            }
                            else {
                                $id = $_.Id
                            }
                            if ($id -eq $applicationAppId) {
                                if ([Version]$_.Version -gt [Version]$settings.applicationDependency) {
                                    $settings.applicationDependency = $appDep
                                }
                            }
                            else {
                                $dependencies."$folderName" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
                            }
                        }
                    }
                    if ($appJson.PSObject.Properties.Name -eq 'Application') {
                        $appDep = $appJson.application
                        if ([Version]$appDep -gt [Version]$settings.applicationDependency) {
                            $settings.applicationDependency = $appDep
                        }
                    }
                }
                catch {
                    throw "$descr $folderName, specified in $FnSCMSettingsFile, contains a corrupt app.json file. Error is $($_.Exception.Message)."
                }
            }
        }
    }
    Write-Host "Application Dependency $($settings.applicationDependency)"

    if (!$doNotCheckArtifactSetting) {
        Write-Host "Checking artifact setting"
        if ($artifact -eq "" -and $settings.updateDependencies) {
            $artifact = Get-BCArtifactUrl -country $settings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
            if (-not $artifact) {
                if ($insiderSasToken) {
                    $artifact = Get-BCArtifactUrl -storageAccount bcinsider -country $settings.country -select all -sasToken $insiderSasToken | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
                    if (-not $artifact) {
                        throw "No artifacts found for application dependency $($settings.applicationDependency)."
                    }
                }
                else {
                    throw "No artifacts found for application dependency $($settings.applicationDependency). If you are targetting an insider version, you need to create a secret called InsiderSasToken, containing the Insider SAS Token from https://aka.ms/collaborate"
                }
            }
        }
        
        if ($artifact -like "https://*") {
            $artifactUrl = $artifact
            $storageAccount = ("$artifactUrl////".Split('/')[2]).Split('.')[0]
            $artifactType = ("$artifactUrl////".Split('/')[3])
            $version = ("$artifactUrl////".Split('/')[4])
            $country = ("$artifactUrl////".Split('/')[5])
            $sasToken = "$($artifactUrl)?".Split('?')[1]
        }
        else {
            $segments = "$artifact/////".Split('/')
            $storageAccount = $segments[0];
            $artifactType = $segments[1]; if ($artifactType -eq "") { $artifactType = 'Sandbox' }
            $version = $segments[2]
            $country = $segments[3]; if ($country -eq "") { $country = $settings.country }
            $select = $segments[4]; if ($select -eq "") { $select = "latest" }
            $sasToken = $segments[5]
            $artifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select $select -sasToken $sasToken | Select-Object -First 1
            if (-not $artifactUrl) {
                throw "No artifacts found for the artifact setting ($artifact) in $FnSCMSettingsFile"
            }
            $version = $artifactUrl.Split('/')[4]
            $storageAccount = $artifactUrl.Split('/')[2]
        }
    
        if ($settings.additionalCountries -or $country -ne $settings.country) {
            if ($country -ne $settings.country -and !$doNotIssueWarnings) {
                OutputWarning -message "artifact definition in $FnSCMSettingsFile uses a different country ($country) than the country definition ($($settings.country))"
            }
            Write-Host "Checking Country and additionalCountries"
            # AT is the latest published language - use this to determine available country codes (combined with mapping)
            $ver = [Version]$version
            Write-Host "https://$storageAccount/$artifactType/$version/$country"
            $atArtifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -country at -version "$($ver.Major).$($ver.Minor)" -select Latest -sasToken $sasToken
            Write-Host "Latest AT artifacts $atArtifactUrl"
            $latestATversion = $atArtifactUrl.Split('/')[4]
            $countries = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $latestATversion -sasToken $sasToken -select All | ForEach-Object { 
                $countryArtifactUrl = $_.Split('?')[0] # remove sas token
                $countryArtifactUrl.Split('/')[5] # get country
            }
            Write-Host "Countries with artifacts $($countries -join ',')"
            $allowedCountries = $bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name + $countries | Select-Object -Unique
            Write-Host "Allowed Country codes $($allowedCountries -join ',')"
            if ($allowedCountries -notcontains $settings.country) {
                throw "Country ($($settings.country)), specified in $FnSCMSettingsFile is not a valid country code."
            }
            $illegalCountries = $settings.additionalCountries | Where-Object { $allowedCountries -notcontains $_ }
            if ($illegalCountries) {
                throw "additionalCountries contains one or more invalid country codes ($($illegalCountries -join ",")) in $FnSCMSettingsFile."
            }
            $artifactUrl = $artifactUrl.Replace($artifactUrl.Split('/')[4],$atArtifactUrl.Split('/')[4])
        }
        else {
            Write-Host "Downloading artifacts from $($artifactUrl.Split('?')[0])"
            $folders = Download-Artifacts -artifactUrl $artifactUrl -includePlatform -ErrorAction SilentlyContinue
            if (-not ($folders)) {
                throw "Unable to download artifacts from $($artifactUrl.Split('?')[0]), please check $FnSCMSettingsFile."
            }
        }
        $settings.artifact = $artifactUrl

        if ([Version]$settings.applicationDependency -gt [Version]$version) {
            throw "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
        }
    }

    # unpack all dependencies and update app- and test dependencies from dependency apps
    $settings.appDependencies + $settings.testDependencies | ForEach-Object {
        $dep = $_
        if ($dep -is [string]) {
            # TODO: handle pre-settings - documentation pending
        }
    }

    Write-Host "Updating app- and test Dependencies"
    $dependencies.Keys | ForEach-Object {
        $folderName = $_
        $appFolder = $settings.appFolders.Contains($folderName)
        if ($appFolder) { $prop = "appDependencies" } else { $prop = "testDependencies" }
        $dependencies."$_" | ForEach-Object {
            $id = $_.Id
            $version = $_.version
            $exists = $settings."$prop" | Where-Object { $_ -is [System.Collections.Specialized.OrderedDictionary] -and $_.id -eq $id }
            if ($exists) {
                if ([Version]$version -gt [Version]$exists.Version) {
                    $exists.Version = $version
                }
            }
            else {
                $settings."$prop" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
            }
        }
    }

    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }

    $settings.appDependencies + $settings.testDependencies | ForEach-Object {
        $dep = $_
        if ($dep.GetType().Name -eq "OrderedDictionary") {
            if ($testRunnerApps.Contains($dep.id)) { $settings.installTestRunner = $true }
            if ($testFrameworkApps.Contains($dep.id)) { $settings.installTestFramework = $true }
            if ($testLibrariesApps.Contains($dep.id)) { $settings.installTestLibraries = $true }
            if ($performanceToolkitApps.Contains($dep.id)) { $settings.installPerformanceToolkit = $true }
        }
    }

    if (!$settings.doNotRunBcptTests -and -not $settings.bcptTestFolders) {
        if (!$doNotIssueWarnings) { OutputWarning -message "No performance test apps found in bcptTestFolders in $FnSCMSettingsFile" }
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotRunTests -and -not $settings.testFolders) {
        if (!$doNotIssueWarnings) { OutputWarning -message "No test apps found in testFolders in $FnSCMSettingsFile" }
        $settings.doNotRunTests = $true
    }
    if (-not $settings.appFolders) {
        if (!$doNotIssueWarnings) { OutputWarning -message "No apps found in appFolders in $FnSCMSettingsFile" }
    }

    $settings
    if (!$runningLocal) {
        Write-Host "::endgroup::"
    }
}

function installModules {
    Param(
        [String[]] $modules
    )

    $modules | ForEach-Object {
        if (-not (get-installedmodule -Name $_ -ErrorAction SilentlyContinue)) {
            Write-Host "Installing module $_"
            Install-Module $_ -Force | Out-Null
        }
    }
    $modules | ForEach-Object { 
        Write-Host "Importing module $_"
        Import-Module $_ -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
    }
}

function CloneIntoNewFolder {
    Param(
        [string] $actor,
        [string] $token,
        [string] $branch
    )

    $baseFolder = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    New-Item $baseFolder -ItemType Directory | Out-Null
    Set-Location $baseFolder
    $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
    $serverUrl = "$($serverUri.Scheme)://$($actor):$($token)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

    # Environment variables for hub commands
    $env:GITHUB_USER = $actor
    $env:GITHUB_TOKEN = $token

    # Configure git username and email
    invoke-git config --global user.email "$actor@users.noreply.github.com"
    invoke-git config --global user.name "$actor"

    # Configure hub to use https
    invoke-git config --global hub.protocol https

    invoke-git clone $serverUrl

    Set-Location *

    if ($branch) {
        invoke-git checkout -b $branch
    }

    $serverUrl
}

function CommitFromNewFolder {
    Param(
        [string] $serverUrl,
        [string] $commitMessage,
        [string] $branch
    )

    invoke-git add *
    if ($commitMessage.Length -gt 250) {
        $commitMessage = "$($commitMessage.Substring(0,250))...)"
    }
    invoke-git commit --allow-empty -m "'$commitMessage'"
    if ($branch) {
        invoke-git push -u $serverUrl $branch
        invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY
    }
    else {
        invoke-git push $serverUrl
    }
}

function Select-Value {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $title,
        [Parameter(Mandatory=$false)]
        [string] $description,
        [Parameter(Mandatory=$true)]
        $options,
        [Parameter(Mandatory=$false)]
        [string] $default = "",
        [Parameter(Mandatory=$true)]
        [string] $question
    )

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host -ForegroundColor Yellow ("-"*$title.Length)
    }
    if ($description) {
        Write-Host $description
        Write-Host
    }
    $offset = 0
    $keys = @()
    $values = @()

    $options.GetEnumerator() | ForEach-Object {
        Write-Host -ForegroundColor Yellow "$([char]($offset+97)) " -NoNewline
        $keys += @($_.Key)
        $values += @($_.Value)
        if ($_.Key -eq $default) {
            Write-Host -ForegroundColor Yellow $_.Value
            $defaultAnswer = $offset
        }
        else {
            Write-Host $_.Value
        }
        $offset++     
    }
    Write-Host
    $answer = -1
    do {
        Write-Host "$question " -NoNewline
        if ($defaultAnswer -ge 0) {
            Write-Host "(default $([char]($defaultAnswer + 97))) " -NoNewline
        }
        $selection = (Read-Host).ToLowerInvariant()
        if ($selection -eq "") {
            if ($defaultAnswer -ge 0) {
                $answer = $defaultAnswer
            }
            else {
                Write-Host -ForegroundColor Red "No default value exists. " -NoNewline
            }
        }
        else {
            if (($selection.Length -ne 1) -or (([int][char]($selection)) -lt 97 -or ([int][char]($selection)) -ge (97+$offset))) {
                Write-Host -ForegroundColor Red "Illegal answer. " -NoNewline
            }
            else {
                $answer = ([int][char]($selection))-97
            }
        }
        if ($answer -eq -1) {
            if ($offset -eq 2) {
                Write-Host -ForegroundColor Red "Please answer one letter, a or b"
            }
            else {
                Write-Host -ForegroundColor Red "Please answer one letter, from a to $([char]($offset+97-1))"
            }
        }
    } while ($answer -eq -1)

    Write-Host -ForegroundColor Green "$($values[$answer]) selected"
    Write-Host
    $keys[$answer]
}

function Enter-Value {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $title,
        [Parameter(Mandatory=$false)]
        [string] $description,
        [Parameter(Mandatory=$false)]
        $options,
        [Parameter(Mandatory=$false)]
        [string] $default = "",
        [Parameter(Mandatory=$true)]
        [string] $question,
        [switch] $doNotConvertToLower,
        [switch] $previousStep
    )

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host -ForegroundColor Yellow ("-"*$title.Length)
    }
    if ($description) {
        Write-Host $description
        Write-Host
    }
    $answer = ""
    do {
        Write-Host "$question " -NoNewline
        if ($options) {
            Write-Host "($([string]::Join(', ', $options))) " -NoNewline
        }
        if ($default) {
            Write-Host "(default $default) " -NoNewline
        }
        if ($doNotConvertToLower) {
            $selection = Read-Host
        }
        else {
            $selection = (Read-Host).ToLowerInvariant()
        }
        if ($selection -eq "") {
            if ($default) {
                $answer = $default
            }
            else {
                Write-Host -ForegroundColor Red "No default value exists. "
            }
        }
        else {
            if ($options) {
                $answer = $options | Where-Object { $_ -like "$selection*" }
                if (-not ($answer)) {
                    Write-Host -ForegroundColor Red "Illegal answer. Please answer one of the options."
                }
                elseif ($answer -is [Array]) {
                    Write-Host -ForegroundColor Red "Multiple options match the answer. Please answer one of the options that matched the previous selection."
                    $options = $answer
                    $answer = $null
                }
            }
            else {
                $answer = $selection
            }
        }
    } while (-not ($answer))

    Write-Host -ForegroundColor Green "$answer selected"
    Write-Host
    $answer
}

function OptionallyConvertFromBase64 {
    Param(
        [string] $value
    )

    if ($value.StartsWith('::') -and $value.EndsWith('::')) {
        if ($value.Length -eq 4) {
            ""
        }
        else {
            [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($value.Substring(2, $value.Length-4)))
        }
    }
}

function ConvertTo-HashTable() {
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

function CheckAndCreateProjectFolder {
    Param(
        [string] $project
    )

    if (-not $project) { $project -eq "." }
    if ($project -ne ".") {
        if (Test-Path $FnSCMSettingsFile) {
            Write-Host "Reading $FnSCMSettingsFile"
            $settingsJson = Get-Content $FnSCMSettingsFile -Encoding UTF8 | ConvertFrom-Json
            if ($settingsJson.appFolders.Count -eq 0 -and $settingsJson.testFolders.Count -eq 0) {
                OutputWarning "Converting the repository to a multi-project repository as no other apps have been added previously."
                New-Item $project -ItemType Directory | Out-Null
                Move-Item -path $FnSCMFolder -Destination $project
                Set-Location $project
            }
            else {
                throw "Repository is setup for a single project, cannot add a project. Move all appFolders, testFolders and the .FnSCM-Go folder to a subdirectory in order to convert to a multi-project repository."
            }
        }
        else {
            if (!(Test-Path $project)) {
                New-Item -Path (Join-Path $project $FnSCMFolder) -ItemType Directory | Out-Null
                Set-Location $project
                OutputWarning "Project folder doesn't exist, creating a new project folder and a default settings file with country us. Please modify if needed."
                [ordered]@{
                    "country" = "us"
                    "appFolders" = @()
                    "testFolders" = @()
                } | ConvertTo-Json | Set-Content $FnSCMSettingsFile -Encoding UTF8
            }
            else {
                Set-Location $project
            }
        }
    }
}
