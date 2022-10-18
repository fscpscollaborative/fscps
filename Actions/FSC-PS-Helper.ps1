Param(
    [switch] $local
)

$gitHubHelperPath = Join-Path $PSScriptRoot 'Helpers\Github-Helper.psm1'
if (Test-Path $gitHubHelperPath) {
    Import-Module $gitHubHelperPath
}

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$FnSCMFolder = ".FSC-PS\"
$FnSCMSettingsFile = ".FSC-PS\settings.json"
$RepoSettingsFile = ".github\FSC-PS-Settings.json"
$runningLocal = $false #$local.IsPresent


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

function OutputInfo {
    [CmdletBinding()]
    param (
        [string]$Message
    )
        filter timestamp {"[ $(Get-Date -Format yyyy.MM.dd-HH:mm:ss) ]: $_"}
        Write-Output ($Message | timestamp)
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

function Get-FSCModels
{
    [CmdletBinding()]
    param (
        [string]
        $metadataPath,
        [switch]
        $includeTest = $false

    )
    if(Test-Path "$metadataPath")
    {
        $modelsList = @()
        $models = Get-ChildItem -Directory "$metadataPath"

        $models | ForEach-Object {

            $testModel = ($_.BaseName -match "Test")

            if ($testModel -and $includeTest) {
                $modelsList += ($_.BaseName)
            }
            if((Test-Path ("$metadataPath/$($_.BaseName)/Descriptor")) -and !$testModel) {
                $modelsList += ($_.BaseName)
            }
        }
        $modelsList -join ","
    }
    else 
    {
        Throw "Folder $metadataPath with metadata doesnot exists"
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
    $branchName = "$env:GITHUB_REF"
    $branchName = [regex]::Replace($branchName.Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() }) 

    # Read Settings file
    $settings = [ordered]@{
        "companyName"                            = ""
        "currentBranch"                          = $branchName
        "sourceBranch"                           = ""
        "repoName"                               = $repoName
        "templateUrl"                            = "https://github.com/ciellosinc/FSC-PS-Template"
        "templateBranch"                         = "main"
        "githubRunner"                           = "windows-latest"
        "buildVersion"                           = ""
        "exportModel"                            = $false
        "uploadPackageToLCS"                     = $false
        "includeTestModel"                       = $false
        "codeSignCertificateUrlSecretName"       = ""
        "codeSignCertificatePasswordSecretName"  = ""
        "nugetFeedName"                          = ""
        "nugetFeedUserName"                      = ""
        "nugetFeedUserSecretName"                = ""
        "nugetFeedPasswordSecretName"            = ""
        "nugetSourcePath"                        = ""
        "nugetPackagesPath"                      = "NuGets"
        "useLocalNuGetStorage"                   = $false
        "githubSecrets"                          = ""
        "buildPath"                              = "_bld"
        "metadataPath"                           = "PackagesLocalDirectory"
        "lcsEnvironmentId"                       = ""
        "lcsProjectId"                           = 123456
        "lcsClientId"                            = ""
        "lcsUsernameSecretname"                  = ""
        "lcsPasswordSecretname"                  = ""
        "azTenantId"                             = ""
        "azClientId"                             = ""
        "azClientsecretSecretname"               = ""
        "azVmname"                               = ""
        "azVmrg"                                 = ""
        "artifactsPath"                          = "artifacts"
        "generatePackages"                       = $true
        "packageNamePattern"                     = "BRANCHNAME-PACKAGENAME-FNSCMVERSION_DATE.RUNNUMBER"
        "packageName"                            = ""
        "retailSDKVersion"                       = ""
        "retailSDKZipPath"                       = "C:\RSDK"
        "retailSDKBuildPath"                     = "C:\Temp\RetailSDK"
        "retailSDKURL"                           = ""
        "repoTokenSecretName"                    = "REPO_TOKEN"
        "ciBranches"                             = "main,release"
        "deployScheduleCron"                     = "1 * * * *"
        "deploy"                                 = $false
        "secretsList"                            = @('nugetFeedPasswordSecretName','nugetFeedUserSecretName','lcsUsernameSecretname','lcsPasswordSecretname','azClientsecretSecretname','repoTokenSecretName')

    }

    $gitHubFolder = ".github"
    if (!(Test-Path (Join-Path $baseFolder $gitHubFolder) -PathType Container)) {
        $RepoSettingsFile = "..\$RepoSettingsFile"
        $gitHubFolder = "..\$gitHubFolder"
    }
    $workflowName = ($workflowName.Split([System.IO.Path]::getInvalidFileNameChars()) -join "").Replace("(", "").Replace(")", "").Replace("/", "")
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
        if($_ -eq "Az")
        {
            Set-ExecutionPolicy RemoteSigned
            Uninstall-AzureRm
        }

        if (-not (get-installedmodule -Name $_ -ErrorAction SilentlyContinue)) {
            Write-Host "Installing module $_"
            Install-Module $_ -Force -AllowClobber -Scope CurrentUser | Out-Null
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
                throw "Repository is setup for a single project, cannot add a project. Move all appFolders, testFolders and the .FSC-PS folder to a subdirectory in order to convert to a multi-project repository."
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

function GenerateProjectFile {
    [CmdletBinding()]
    param (
        [string]$ModelName,
        [string]$ProjectGuid
    )

    $ProjectFileName =  'Build.rnrproj'
    $ModelProjectFileName = $ModelName + '.rnrproj'
    $NugetFolderPath =  Join-Path $PSScriptRoot 'NewBuild'
    $SolutionFolderPath = Join-Path  $NugetFolderPath 'Build'
    $ModelProjectFile = Join-Path $SolutionFolderPath $ModelProjectFileName

    #generate project file

    $ProjectFileData = (Get-Content $ProjectFileName).Replace('ModelName', $ModelName).Replace('62C69717-A1B6-43B5-9E86-24806782FEC2'.ToLower(), $ProjectGuid.ToLower())
     
    Set-Content $ModelProjectFile $ProjectFileData
}

function GenerateSolution {
    [CmdletBinding()]
    param (
        [string]$ModelName,
        [string]$NugetFeedName,
        [string]$NugetSourcePath,
        [string]$DynamicsVersion
    )

    cd $PSScriptRoot\Build\Build

    $SolutionFileName =  'Build.sln'
    $NugetFolderPath =  Join-Path $PSScriptRoot 'NewBuild'
    $SolutionFolderPath = Join-Path  $NugetFolderPath 'Build'
    $NewSolutionName = Join-Path  $SolutionFolderPath 'Build.sln'
    New-Item -ItemType Directory -Path $SolutionFolderPath -ErrorAction SilentlyContinue
    Copy-Item build.props -Destination $SolutionFolderPath -force
    $ProjectPattern = 'Project("{FC65038C-1B2F-41E1-A629-BED71D161FFF}") = "ModelNameBuild (ISV) [ModelName]", "ModelName.rnrproj", "{62C69717-A1B6-43B5-9E86-24806782FEC2}"'
    $ActiveCFGPattern = '		{62C69717-A1B6-43B5-9E86-24806782FEC2}.Debug|Any CPU.ActiveCfg = Debug|Any CPU'
    $BuildPattern = '		{62C69717-A1B6-43B5-9E86-24806782FEC2}.Debug|Any CPU.Build.0 = Debug|Any CPU'

    [String[]] $SolutionFileData = @() 

    $projectGuids = @{};
    Foreach($model in $ModelName.Split(','))
    {
        $projectGuids.Add($model, ([string][guid]::NewGuid()).ToUpper())
    }

    #generate project files file
    $FileOriginal = Get-Content $SolutionFileName
        
    Foreach ($Line in $FileOriginal)
    {   
        $SolutionFileData += $Line
        Foreach($model in $ModelName.Split(','))
        {
            $projectGuid = $projectGuids.Item($model)
            if ($Line -eq $ProjectPattern) 
            {
                $newLine = $ProjectPattern -replace 'ModelName', $model
                $newLine = $newLine -replace 'Build.rnrproj', ($model+'.rnrproj')
                $newLine = $newLine -replace '62C69717-A1B6-43B5-9E86-24806782FEC2', $projectGuid
                #Add Lines after the selected pattern 
                $SolutionFileData += $newLine                
                $SolutionFileData += "EndProject"
        
            } 
            if ($Line -eq $ActiveCFGPattern) 
            { 
                $newLine = $ActiveCFGPattern -replace '62C69717-A1B6-43B5-9E86-24806782FEC2', $projectGuid
                $SolutionFileData += $newLine
            } 
            if ($Line -eq $BuildPattern) 
            {
            
                $newLine = $BuildPattern -replace '62C69717-A1B6-43B5-9E86-24806782FEC2', $projectGuid
                $SolutionFileData += $newLine
            } 
        }
    }
    
    #save solution file
    Set-Content $NewSolutionName $SolutionFileData;
    #cleanup solution file
    $tempFile = Get-Content $NewSolutionName
    $tempFile | Where-Object {$_ -ne $ProjectPattern} | Where-Object {$_ -ne $ActiveCFGPattern} | Where-Object {$_ -ne $BuildPattern} | Set-Content -Path $NewSolutionName 

    #generate project files
    Foreach($project in $projectGuids.GetEnumerator())
    {
        GenerateProjectFile -ModelName $project.Name -ProjectGuid $project.Value
    }

    cd $PSScriptRoot\Build
    #generate nuget.config
    $NugetConfigFileName = 'nuget.config'
    $NewNugetFile = Join-Path $NugetFolderPath $NugetConfigFileName
    $tempFile = (Get-Content $NugetConfigFileName).Replace('NugetFeedName', $NugetFeedName).Replace('NugetSourcePath', $NugetSourcePath)
    Set-Content $NewNugetFile $tempFile


    Foreach($version in Get-Versions)
    {
        if($version.version -eq $DynamicsVersion)
        {
            $PlatformVersion = $version.data.PlatformVersion
            $ApplicationVersion = $version.data.AppVersion
        }
    }

    #generate packages.config
    $PackagesConfigFileName = 'packages.config'
    $NewPackagesFile = Join-Path $NugetFolderPath $PackagesConfigFileName
    $tempFile = (Get-Content $PackagesConfigFileName).Replace('PlatformVersion', $PlatformVersion).Replace('ApplicationVersion', $ApplicationVersion)
    Set-Content $NewPackagesFile $tempFile

    cd $PSScriptRoot
}

function Update-RetailSDK
{
    [CmdletBinding()]
    param (
        [string]$sdkVersion,
        [string]$sdkPath
    )

    process
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $version = Get-VersionData -sdkVersion $sdkVersion
        $path = Join-Path $sdkPath "RetailSDK.$($version.retailSDKVersion).7z"

        if(!(Test-Path -Path $sdkPath))
        {
            New-Item -ItemType Directory -Force -Path $sdkPath
        }

        if(!(Test-Path -Path $path))
        {
            Invoke-WebRequest -Uri $version.retailSDKURL -OutFile $path
        }
        Write-Output $path
    }
}

function Update-FSCNuGet
{
    [CmdletBinding()]
    param (
        [string]$sdkVersion,
        [string]$sdkPath,
        [string]$token
    )

    process
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $version = Get-VersionData -sdkVersion $sdkVersion
        $path = Join-Path $sdkPath "RetailSDK.$($version.retailSDKVersion).7z"

        if(!(Test-Path -Path $sdkPath))
        {
            New-Item -ItemType Directory -Force -Path $sdkPath
        }

        if(!(Test-Path -Path $path))
        {
            Invoke-WebRequest -Uri $version.retailSDKURL -OutFile $path
        }
        Write-Output $path
    }
}

function Get-VersionData
{
    [CmdletBinding()]
    param (
        [string]$sdkVersion
    )
    process
    {
        $data = Get-Versions
        foreach($d in $data)
        {
            if($d.version -eq $sdkVersion)
            {
                Write-Output $d.data
            }
        }
    }
}

function Get-Versions
{
    [CmdletBinding()]
    param (
    )

    process
    {
        $versionsDefaultFile = Join-Path "$PSScriptRoot" "Helpers\versions.default.json"
        $versionsDefault = (Get-Content $versionsDefaultFile) | ConvertFrom-Json 
        $versionsFile = Join-Path $ENV:GITHUB_WORKSPACE '.FSC-PS\versions.json'
        

        if(Test-Path $versionsFile)
        {
            $versions = (Get-Content $versionsFile) | ConvertFrom-Json
            ForEach($version in $versions)
            { 
                ForEach($versionDefault in $versionsDefault)
                {
                    if($version.version -eq $versionDefault.version)
                    {
            
                        if($version.data.PSobject.Properties.name -match "AppVersion")
                        {
                            if($version.data.AppVersion -ne "")
                            {
                                $versionDefault.data.AppVersion = $version.data.AppVersion
                            }
                        }
                        if($version.data.PSobject.Properties.name -match "PlatformVersion")
                        {
                            if($version.data.PlatformVersion -ne "")
                            {
                                $versionDefault.data.PlatformVersion = $version.data.PlatformVersion
                            }
                        }
                        if($version.data.PSobject.Properties.name -match "retailSDKURL")
                        {
                            if($version.data.retailSDKURL -ne "")
                            {
                                $versionDefault.data.retailSDKURL = $version.data.retailSDKURL
                            }
                        }
                        if($version.data.PSobject.Properties.name -match "retailSDKVersion")
                        {
                            if($version.data.retailSDKVersion -ne "")
                            {
                                $versionDefault.data.retailSDKVersion = $version.data.retailSDKVersion
                            }
                        }
                    }
                }
            }
        }
        Write-Output ($versionsDefault)
    }
}

function Copy-Filtered {
    param (
        [string] $Source,
        [string] $Target,
        [string[]] $Filter
    )
    $ResolvedSource = Resolve-Path $Source
    $NormalizedSource = $ResolvedSource.Path.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    Get-ChildItem $Source -Include $Filter -Recurse | ForEach-Object {
        $RelativeItemSource = $_.FullName.Replace($NormalizedSource, '')
        $ItemTarget = Join-Path $Target $RelativeItemSource
        $ItemTargetDir = Split-Path $ItemTarget
        if (!(Test-Path $ItemTargetDir)) {
            [void](New-Item $ItemTargetDir -Type Directory)
        }
        Copy-Item $_.FullName $ItemTarget
    }
}

################################################################################
# Start - Private functions.
################################################################################

function Find-Match {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DefaultRoot,
        [Parameter()]
        [string[]]$Pattern,
        $FindOptions,
        $MatchOptions)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'



        Write-Verbose "DefaultRoot: '$DefaultRoot'"
        if (!$FindOptions) {
            $FindOptions = New-FindOptions -FollowSpecifiedSymbolicLink -FollowSymbolicLinks
        }


        if (!$MatchOptions) {
            $MatchOptions = New-MatchOptions -Dot -NoBrace -NoCase
        }


        Add-Type -LiteralPath $PSScriptRoot\Helpers\Minimatch.dll

        # Normalize slashes for root dir.
        $DefaultRoot = ConvertTo-NormalizedSeparators -Path $DefaultRoot

        $results = @{ }
        $originalMatchOptions = $MatchOptions
        foreach ($pat in $Pattern) {
            Write-Verbose "Pattern: '$pat'"

            # Trim and skip empty.
            $pat = "$pat".Trim()
            if (!$pat) {
                Write-Verbose 'Skipping empty pattern.'
                continue
            }

            # Clone match options.
            $MatchOptions = Copy-MatchOptions -Options $originalMatchOptions

            # Skip comments.
            if (!$MatchOptions.NoComment -and $pat.StartsWith('#')) {
                Write-Verbose 'Skipping comment.'
                continue
            }

            # Set NoComment. Brace expansion could result in a leading '#'.
            $MatchOptions.NoComment = $true

            # Determine whether pattern is include or exclude.
            $negateCount = 0
            if (!$MatchOptions.NoNegate) {
                while ($negateCount -lt $pat.Length -and $pat[$negateCount] -eq '!') {
                    $negateCount++
                }

                $pat = $pat.Substring($negateCount) # trim leading '!'
                if ($negateCount) {
                    Write-Verbose "Trimmed leading '!'. Pattern: '$pat'"
                }
            }

            $isIncludePattern = $negateCount -eq 0 -or
                ($negateCount % 2 -eq 0 -and !$MatchOptions.FlipNegate) -or
                ($negateCount % 2 -eq 1 -and $MatchOptions.FlipNegate)

            # Set NoNegate. Brace expansion could result in a leading '!'.
            $MatchOptions.NoNegate = $true
            $MatchOptions.FlipNegate = $false

            # Trim and skip empty.
            $pat = "$pat".Trim()
            if (!$pat) {
                Write-Verbose 'Skipping empty pattern.'
                continue
            }

            # Expand braces - required to accurately interpret findPath.
            $expanded = $null
            $preExpanded = $pat
            if ($MatchOptions.NoBrace) {
                $expanded = @( $pat )
            } else {
                # Convert slashes on Windows before calling braceExpand(). Unfortunately this means braces cannot
                # be escaped on Windows, this limitation is consistent with current limitations of minimatch (3.0.3).
                Write-Verbose "Expanding braces."
                $convertedPattern = $pat -replace '\\', '/'
                $expanded = [Minimatch.Minimatcher]::BraceExpand(
                    $convertedPattern,
                    (ConvertTo-MinimatchOptions -Options $MatchOptions))
            }

            # Set NoBrace.
            $MatchOptions.NoBrace = $true

            foreach ($pat in $expanded) {
                if ($pat -ne $preExpanded) {
                    Write-Verbose "Pattern: '$pat'"
                }

                # Trim and skip empty.
                $pat = "$pat".Trim()
                if (!$pat) {
                    Write-Verbose "Skipping empty pattern."
                    continue
                }

                if ($isIncludePattern) {
                    # Determine the findPath.
                    $findInfo = Get-FindInfoFromPattern -DefaultRoot $DefaultRoot -Pattern $pat -MatchOptions $MatchOptions
                    $findPath = $findInfo.FindPath
                    Write-Verbose "FindPath: '$findPath'"

                    if (!$findPath) {
                        Write-Verbose "Skipping empty path."
                        continue
                    }

                    # Perform the find.
                    Write-Verbose "StatOnly: '$($findInfo.StatOnly)'"
                    [string[]]$findResults = @( )
                    if ($findInfo.StatOnly) {
                        # Simply stat the path - all path segments were used to build the path.
                        if ((Test-Path -LiteralPath $findPath)) {
                            $findResults += $findPath
                        }
                    } else {
                        $findResults = Get-FindResult -Path $findPath -Options $FindOptions
                    }

                    Write-Verbose "Found $($findResults.Count) paths."

                    # Apply the pattern.
                    Write-Verbose "Applying include pattern."
                    if ($findInfo.AdjustedPattern -ne $pat) {
                        Write-Verbose "AdjustedPattern: '$($findInfo.AdjustedPattern)'"
                        $pat = $findInfo.AdjustedPattern
                    }

                    $matchResults = [Minimatch.Minimatcher]::Filter(
                        $findResults,
                        $pat,
                        (ConvertTo-MinimatchOptions -Options $MatchOptions))

                    # Union the results.
                    $matchCount = 0
                    foreach ($matchResult in $matchResults) {
                        $matchCount++
                        $results[$matchResult.ToUpperInvariant()] = $matchResult
                    }

                    Write-Verbose "$matchCount matches"
                } else {
                    # Check if basename only and MatchBase=true.
                    if ($MatchOptions.MatchBase -and
                        !(Test-Rooted -Path $pat) -and
                        ($pat -replace '\\', '/').IndexOf('/') -lt 0) {

                        # Do not root the pattern.
                        Write-Verbose "MatchBase and basename only."
                    } else {
                        # Root the exclude pattern.
                        $pat = Get-RootedPattern -DefaultRoot $DefaultRoot -Pattern $pat
                        Write-Verbose "After Get-RootedPattern, pattern: '$pat'"
                    }

                    # Apply the pattern.
                    Write-Verbose 'Applying exclude pattern.'
                    $matchResults = [Minimatch.Minimatcher]::Filter(
                        [string[]]$results.Values,
                        $pat,
                        (ConvertTo-MinimatchOptions -Options $MatchOptions))

                    # Subtract the results.
                    $matchCount = 0
                    foreach ($matchResult in $matchResults) {
                        $matchCount++
                        $results.Remove($matchResult.ToUpperInvariant())
                    }

                    Write-Verbose "$matchCount matches"
                }
            }
        }

        $finalResult = @( $results.Values | Sort-Object )
        Write-Verbose "$($finalResult.Count) final results"
        return $finalResult
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } 
}

function New-FindOptions {
    [CmdletBinding()]
    param(
        [switch]$FollowSpecifiedSymbolicLink,
        [switch]$FollowSymbolicLinks)

    return New-Object psobject -Property @{
        FollowSpecifiedSymbolicLink = $FollowSpecifiedSymbolicLink.IsPresent
        FollowSymbolicLinks = $FollowSymbolicLinks.IsPresent
    }
}

function New-MatchOptions {
    [CmdletBinding()]
    param(
        [switch]$Dot,
        [switch]$FlipNegate,
        [switch]$MatchBase,
        [switch]$NoBrace,
        [switch]$NoCase,
        [switch]$NoComment,
        [switch]$NoExt,
        [switch]$NoGlobStar,
        [switch]$NoNegate,
        [switch]$NoNull)

    return New-Object psobject -Property @{
        Dot = $Dot.IsPresent
        FlipNegate = $FlipNegate.IsPresent
        MatchBase = $MatchBase.IsPresent
        NoBrace = $NoBrace.IsPresent
        NoCase = $NoCase.IsPresent
        NoComment = $NoComment.IsPresent
        NoExt = $NoExt.IsPresent
        NoGlobStar = $NoGlobStar.IsPresent
        NoNegate = $NoNegate.IsPresent
        NoNull = $NoNull.IsPresent
    }
}

function ConvertTo-NormalizedSeparators {
    [CmdletBinding()]
    param([string]$Path)

    # Convert slashes.
    $Path = "$Path".Replace('/', '\')

    # Remove redundant slashes.
    $isUnc = $Path -match '^\\\\+[^\\]'
    $Path = $Path -replace '\\\\+', '\'
    if ($isUnc) {
        $Path = '\' + $Path
    }

    return $Path
}

function Get-FindInfoFromPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefaultRoot,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        $MatchOptions)

    if (!$MatchOptions.NoBrace) {
        throw "Get-FindInfoFromPattern expected MatchOptions.NoBrace to be true."
    }

    # For the sake of determining the find path, pretend NoCase=false.
    $MatchOptions = Copy-MatchOptions -Options $MatchOptions
    $MatchOptions.NoCase = $false

    # Check if basename only and MatchBase=true
    if ($MatchOptions.MatchBase -and
        !(Test-Rooted -Path $Pattern) -and
        ($Pattern -replace '\\', '/').IndexOf('/') -lt 0) {

        return New-Object psobject -Property @{
            AdjustedPattern = $Pattern
            FindPath = $DefaultRoot
            StatOnly = $false
        }
    }

    # The technique applied by this function is to use the information on the Minimatch object determine
    # the findPath. Minimatch breaks the pattern into path segments, and exposes information about which
    # segments are literal vs patterns.
    #
    # Note, the technique currently imposes a limitation for drive-relative paths with a glob in the
    # first segment, e.g. C:hello*/world. It's feasible to overcome this limitation, but is left unsolved
    # for now.
    $minimatchObj = New-Object Minimatch.Minimatcher($Pattern, (ConvertTo-MinimatchOptions -Options $MatchOptions))

    # The "set" field is a two-dimensional enumerable of parsed path segment info. The outer enumerable should only
    # contain one item, otherwise something went wrong. Brace expansion can result in multiple items in the outer
    # enumerable, but that should be turned off by the time this function is reached.
    #
    # Note, "set" is a private field in the .NET implementation but is documented as a feature in the nodejs
    # implementation. The .NET implementation is a port and is by a different author.
    $setFieldInfo = $minimatchObj.GetType().GetField('set', 'Instance,NonPublic')
    [object[]]$set = $setFieldInfo.GetValue($minimatchObj)
    if ($set.Count -ne 1) {
        throw "Get-FindInfoFromPattern expected Minimatch.Minimatcher(...).set.Count to be 1. Actual: '$($set.Count)'"
    }

    [string[]]$literalSegments = @( )
    [object[]]$parsedSegments = $set[0]
    foreach ($parsedSegment in $parsedSegments) {
        if ($parsedSegment.GetType().Name -eq 'LiteralItem') {
            # The item is a LiteralItem when the original input for the path segment does not contain any
            # unescaped glob characters.
            $literalSegments += $parsedSegment.Source;
            continue
        }

        break;
    }

    # Join the literal segments back together. Minimatch converts '\' to '/' on Windows, then squashes
    # consequetive slashes, and finally splits on slash. This means that UNC format is lost, but can
    # be detected from the original pattern.
    $joinedSegments = [string]::Join('/', $literalSegments)
    if ($joinedSegments -and ($Pattern -replace '\\', '/').StartsWith('//')) {
        $joinedSegments = '/' + $joinedSegments # restore UNC format
    }

    # Determine the find path.
    $findPath = ''
    if ((Test-Rooted -Path $Pattern)) { # The pattern is rooted.
        $findPath = $joinedSegments
    } elseif ($joinedSegments) { # The pattern is not rooted, and literal segements were found.
        $findPath = [System.IO.Path]::Combine($DefaultRoot, $joinedSegments)
    } else { # The pattern is not rooted, and no literal segements were found.
        $findPath = $DefaultRoot
    }

    # Clean up the path.
    if ($findPath) {
        $findPath = [System.IO.Path]::GetDirectoryName(([System.IO.Path]::Combine($findPath, '_'))) # Hack to remove unnecessary trailing slash.
        $findPath = ConvertTo-NormalizedSeparators -Path $findPath
    }

    return New-Object psobject -Property @{
        AdjustedPattern = Get-RootedPattern -DefaultRoot $DefaultRoot -Pattern $Pattern
        FindPath = $findPath
        StatOnly = $literalSegments.Count -eq $parsedSegments.Count
    }
}

function Get-FindResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Options)

    if (!(Test-Path -LiteralPath $Path)) {
        Write-Verbose 'Path not found.'
        return
    }

    $Path = ConvertTo-NormalizedSeparators -Path $Path

    # Push the first item.
    [System.Collections.Stack]$stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $Path))

    $count = 0
    while ($stack.Count) {
        # Pop the next item and yield the result.
        $item = $stack.Pop()
        $count++
        $item.FullName

        # Traverse.
        if (($item.Attributes -band 0x00000010) -eq 0x00000010) { # Directory
            if (($item.Attributes -band 0x00000400) -ne 0x00000400 -or # ReparsePoint
                $Options.FollowSymbolicLinks -or
                ($count -eq 1 -and $Options.FollowSpecifiedSymbolicLink)) {

                $childItems = @( Get-DirectoryChildItem -Path $Item.FullName -Force )
                [System.Array]::Reverse($childItems)
                foreach ($childItem in $childItems) {
                    $stack.Push($childItem)
                }
            }
        }
    }
}

function Get-RootedPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefaultRoot,
        [Parameter(Mandatory = $true)]
        [string]$Pattern)

    if ((Test-Rooted -Path $Pattern)) {
        return $Pattern
    }

    # Normalize root.
    $DefaultRoot = ConvertTo-NormalizedSeparators -Path $DefaultRoot

    # Escape special glob characters.
    $DefaultRoot = $DefaultRoot -replace '(\[)(?=[^\/]+\])', '[[]' # Escape '[' when ']' follows within the path segment
    $DefaultRoot = $DefaultRoot.Replace('?', '[?]')     # Escape '?'
    $DefaultRoot = $DefaultRoot.Replace('*', '[*]')     # Escape '*'
    $DefaultRoot = $DefaultRoot -replace '\+\(', '[+](' # Escape '+('
    $DefaultRoot = $DefaultRoot -replace '@\(', '[@]('  # Escape '@('
    $DefaultRoot = $DefaultRoot -replace '!\(', '[!]('  # Escape '!('

    if ($DefaultRoot -like '[A-Z]:') { # e.g. C:
        return "$DefaultRoot$Pattern"
    }

    # Ensure root ends with a separator.
    if (!$DefaultRoot.EndsWith('\')) {
        $DefaultRoot = "$DefaultRoot\"
    }

    return "$DefaultRoot$Pattern"
}

function Test-Rooted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path)

    $Path = ConvertTo-NormalizedSeparators -Path $Path
    return $Path.StartsWith('\') -or # e.g. \ or \hello or \\hello
        $Path -like '[A-Z]:*'        # e.g. C: or C:\hello
}

function Trace-MatchOptions {
    [CmdletBinding()]
    param($Options)

    Write-Verbose "MatchOptions.Dot: '$($Options.Dot)'"
    Write-Verbose "MatchOptions.FlipNegate: '$($Options.FlipNegate)'"
    Write-Verbose "MatchOptions.MatchBase: '$($Options.MatchBase)'"
    Write-Verbose "MatchOptions.NoBrace: '$($Options.NoBrace)'"
    Write-Verbose "MatchOptions.NoCase: '$($Options.NoCase)'"
    Write-Verbose "MatchOptions.NoComment: '$($Options.NoComment)'"
    Write-Verbose "MatchOptions.NoExt: '$($Options.NoExt)'"
    Write-Verbose "MatchOptions.NoGlobStar: '$($Options.NoGlobStar)'"
    Write-Verbose "MatchOptions.NoNegate: '$($Options.NoNegate)'"
    Write-Verbose "MatchOptions.NoNull: '$($Options.NoNull)'"
}

function Trace-FindOptions {
    [CmdletBinding()]
    param($Options)

    Write-Verbose "FindOptions.FollowSpecifiedSymbolicLink: '$($FindOptions.FollowSpecifiedSymbolicLink)'"
    Write-Verbose "FindOptions.FollowSymbolicLinks: '$($FindOptions.FollowSymbolicLinks)'"
}

function Copy-MatchOptions {
    [CmdletBinding()]
    param($Options)

    return New-Object psobject -Property @{
        Dot = $Options.Dot -eq $true
        FlipNegate = $Options.FlipNegate -eq $true
        MatchBase = $Options.MatchBase -eq $true
        NoBrace = $Options.NoBrace -eq $true
        NoCase = $Options.NoCase -eq $true
        NoComment = $Options.NoComment -eq $true
        NoExt = $Options.NoExt -eq $true
        NoGlobStar = $Options.NoGlobStar -eq $true
        NoNegate = $Options.NoNegate -eq $true
        NoNull = $Options.NoNull -eq $true
    }
}

function ConvertTo-MinimatchOptions {
    [CmdletBinding()]
    param($Options)

    $opt = New-Object Minimatch.Options
    $opt.AllowWindowsPaths = $true
    $opt.Dot = $Options.Dot -eq $true
    $opt.FlipNegate = $Options.FlipNegate -eq $true
    $opt.MatchBase = $Options.MatchBase -eq $true
    $opt.NoBrace = $Options.NoBrace -eq $true
    $opt.NoCase = $Options.NoCase -eq $true
    $opt.NoComment = $Options.NoComment -eq $true
    $opt.NoExt = $Options.NoExt -eq $true
    $opt.NoGlobStar = $Options.NoGlobStar -eq $true
    $opt.NoNegate = $Options.NoNegate -eq $true
    $opt.NoNull = $Options.NoNull -eq $true
    return $opt
}

function Get-LocString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Key,
        [Parameter(Position = 2)]
        [object[]]$ArgumentList = @( ))

    # Due to the dynamically typed nature of PowerShell, a single null argument passed
    # to an array parameter is interpreted as a null array.
    if ([object]::ReferenceEquals($null, $ArgumentList)) {
        $ArgumentList = @( $null )
    }

    # Lookup the format string.
    $format = ''
    if (!($format = $script:resourceStrings[$Key])) {
        # Warn the key was not found. Prevent recursion if the lookup key is the
        # "string resource key not found" lookup key.
        $resourceNotFoundKey = 'PSLIB_StringResourceKeyNotFound0'
        if ($key -ne $resourceNotFoundKey) {
            Write-Warning (Get-LocString -Key $resourceNotFoundKey -ArgumentList $Key)
        }

        # Fallback to just the key itself if there aren't any arguments to format.
        if (!$ArgumentList.Count) { return $key }

        # Otherwise fallback to the key followed by the arguments.
        $OFS = " "
        return "$key $ArgumentList"
    }

    # Return the string if there aren't any arguments to format.
    if (!$ArgumentList.Count) { return $format }

    try {
        [string]::Format($format, $ArgumentList)
    } catch {
        Write-Warning (Get-LocString -Key 'PSLIB_StringFormatFailed')
        $OFS = " "
        "$format $ArgumentList"
    }
}

function ConvertFrom-LongFormPath {
    [CmdletBinding()]
    param([string]$Path)

    if ($Path) {
        if ($Path.StartsWith('\\?\UNC')) {
            # E.g. \\?\UNC\server\share -> \\server\share
            return $Path.Substring(1, '\?\UNC'.Length)
        } elseif ($Path.StartsWith('\\?\')) {
            # E.g. \\?\C:\directory -> C:\directory
            return $Path.Substring('\\?\'.Length)
        }
    }

    return $Path
}

function ConvertTo-LongFormPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path)

    [string]$longFormPath = Get-FullNormalizedPath -Path $Path
    if ($longFormPath -and !$longFormPath.StartsWith('\\?')) {
        if ($longFormPath.StartsWith('\\')) {
            # E.g. \\server\share -> \\?\UNC\server\share
            return "\\?\UNC$($longFormPath.Substring(1))"
        } else {
            # E.g. C:\directory -> \\?\C:\directory
            return "\\?\$longFormPath"
        }
    }

    return $longFormPath
}

# TODO: ADD A SWITCH TO EXCLUDE FILES, A SWITCH TO EXCLUDE DIRECTORIES, AND A SWITCH NOT TO FOLLOW REPARSE POINTS.
function Get-DirectoryChildItem {
    [CmdletBinding()]
    param(
        [string]$Path,
        [ValidateNotNullOrEmpty()]
        [Parameter()]
        [string]$Filter = "*",
        [switch]$Force,
        [VstsTaskSdk.FS.FindFlags]$Flags = [VstsTaskSdk.FS.FindFlags]::LargeFetch,
        [VstsTaskSdk.FS.FindInfoLevel]$InfoLevel = [VstsTaskSdk.FS.FindInfoLevel]::Basic,
        [switch]$Recurse)

    $stackOfDirectoryQueues = New-Object System.Collections.Stack
    while ($true) {
        $directoryQueue = New-Object System.Collections.Queue
        $fileQueue = New-Object System.Collections.Queue
        $findData = New-Object VstsTaskSdk.FS.FindData
        $longFormPath = (ConvertTo-LongFormPath $Path)
        $handle = $null
        try {
            $handle = [VstsTaskSdk.FS.NativeMethods]::FindFirstFileEx(
                [System.IO.Path]::Combine($longFormPath, $Filter),
                $InfoLevel,
                $findData,
                [VstsTaskSdk.FS.FindSearchOps]::NameMatch,
                [System.IntPtr]::Zero,
                $Flags)
            if (!$handle.IsInvalid) {
                while ($true) {
                    if ($findData.fileName -notin '.', '..') {
                        $attributes = [VstsTaskSdk.FS.Attributes]$findData.fileAttributes
                        # If the item is hidden, check if $Force is specified.
                        if ($Force -or !$attributes.HasFlag([VstsTaskSdk.FS.Attributes]::Hidden)) {
                            # Create the item.
                            $item = New-Object -TypeName psobject -Property @{
                                'Attributes' = $attributes
                                'FullName' = (ConvertFrom-LongFormPath -Path ([System.IO.Path]::Combine($Path, $findData.fileName)))
                                'Name' = $findData.fileName
                            }
                            # Output directories immediately.
                            if ($item.Attributes.HasFlag([VstsTaskSdk.FS.Attributes]::Directory)) {
                                $item
                                # Append to the directory queue if recursive and default filter.
                                if ($Recurse -and $Filter -eq '*') {
                                    $directoryQueue.Enqueue($item)
                                }
                            } else {
                                # Hold the files until all directories have been output.
                                $fileQueue.Enqueue($item)
                            }
                        }
                    }

                    if (!([VstsTaskSdk.FS.NativeMethods]::FindNextFile($handle, $findData))) { break }

                    if ($handle.IsInvalid) {
                        throw (New-Object -TypeName System.ComponentModel.Win32Exception -ArgumentList @(
                            [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                            Get-LocString -Key PSLIB_EnumeratingSubdirectoriesFailedForPath0 -ArgumentList $Path
                        ))
                    }
                }
            }
        } finally {
            if ($handle -ne $null) { $handle.Dispose() }
        }

        # If recursive and non-default filter, queue child directories.
        if ($Recurse -and $Filter -ne '*') {
            $findData = New-Object VstsTaskSdk.FS.FindData
            $handle = $null
            try {
                $handle = [VstsTaskSdk.FS.NativeMethods]::FindFirstFileEx(
                    [System.IO.Path]::Combine($longFormPath, '*'),
                    [VstsTaskSdk.FS.FindInfoLevel]::Basic,
                    $findData,
                    [VstsTaskSdk.FS.FindSearchOps]::NameMatch,
                    [System.IntPtr]::Zero,
                    $Flags)
                if (!$handle.IsInvalid) {
                    while ($true) {
                        if ($findData.fileName -notin '.', '..') {
                            $attributes = [VstsTaskSdk.FS.Attributes]$findData.fileAttributes
                            # If the item is hidden, check if $Force is specified.
                            if ($Force -or !$attributes.HasFlag([VstsTaskSdk.FS.Attributes]::Hidden)) {
                                # Collect directories only.
                                if ($attributes.HasFlag([VstsTaskSdk.FS.Attributes]::Directory)) {
                                    # Create the item.
                                    $item = New-Object -TypeName psobject -Property @{
                                        'Attributes' = $attributes
                                        'FullName' = (ConvertFrom-LongFormPath -Path ([System.IO.Path]::Combine($Path, $findData.fileName)))
                                        'Name' = $findData.fileName
                                    }
                                    $directoryQueue.Enqueue($item)
                                }
                            }
                        }

                        if (!([VstsTaskSdk.FS.NativeMethods]::FindNextFile($handle, $findData))) { break }

                        if ($handle.IsInvalid) {
                            throw (New-Object -TypeName System.ComponentModel.Win32Exception -ArgumentList @(
                                [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                                Get-LocString -Key PSLIB_EnumeratingSubdirectoriesFailedForPath0 -ArgumentList $Path
                            ))
                        }
                    }
                }
            } finally {
                if ($handle -ne $null) { $handle.Dispose() }
            }
        }

        # Output the files.
        $fileQueue

        # Push the directory queue onto the stack if any directories were found.
        if ($directoryQueue.Count) { $stackOfDirectoryQueues.Push($directoryQueue) }

        # Break out of the loop if no more directory queues to process.
        if (!$stackOfDirectoryQueues.Count) { break }

        # Get the next path.
        $directoryQueue = $stackOfDirectoryQueues.Peek()
        $Path = $directoryQueue.Dequeue().FullName

        # Pop the directory queue if it's empty.
        if (!$directoryQueue.Count) { $null = $stackOfDirectoryQueues.Pop() }
    }
}

function Get-FullNormalizedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path)

    [string]$outPath = $Path
    [uint32]$bufferSize = [VstsTaskSdk.FS.NativeMethods]::GetFullPathName($Path, 0, $null, $null)
    [int]$lastWin32Error = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($bufferSize -gt 0) {
        $absolutePath = New-Object System.Text.StringBuilder([int]$bufferSize)
        [uint32]$length = [VstsTaskSdk.FS.NativeMethods]::GetFullPathName($Path, $bufferSize, $absolutePath, $null)
        $lastWin32Error = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($length -gt 0) {
            $outPath = $absolutePath.ToString()
        } else  {
            throw (New-Object -TypeName System.ComponentModel.Win32Exception -ArgumentList @(
                $lastWin32Error
                Get-LocString -Key PSLIB_PathLengthNotReturnedFor0 -ArgumentList $Path
            ))
        }
    } else {
        throw (New-Object -TypeName System.ComponentModel.Win32Exception -ArgumentList @(
            $lastWin32Error
            Get-LocString -Key PSLIB_PathLengthNotReturnedFor0 -ArgumentList $Path
        ))
    }

    if ($outPath.EndsWith('\') -and !$outPath.EndsWith(':\')) {
        $outPath = $outPath.TrimEnd('\')
    }

    $outPath
}

function ConvertTo-OrderedDictionary
{
    #requires -Version 2.0

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]
        $InputObject,

        [Type]
        $KeyType = [string]
    )

    process
    {
        #$outputObject = New-Object "System.Collections.Generic.Dictionary[[$($KeyType.FullName)],[Object]]"
        $outputObject = New-Object "System.Collections.Specialized.OrderedDictionary"

        foreach ($entry in $InputObject.GetEnumerator())
        {
            $newKey = $entry.Key -as $KeyType
            
            if ($null -eq $newKey)
            {
                throw 'Could not convert key "{0}" of type "{1}" to type "{2}"' -f
                      $entry.Key,
                      $entry.Key.GetType().FullName,
                      $KeyType.FullName
            }
            elseif ($outputObject.Contains($newKey))
            {
                throw "Duplicate key `"$newKey`" detected in input object."
            }

            $outputObject.Add($newKey, $entry.Value)
        }

        Write-Output $outputObject
    }
}

function Extract-D365FSCSource
{
    [CmdletBinding()]
    param (
        [string]
        $archivePath,
        [string]
        $targetPath

    )

    $tempFolder = "$targetPath\_tmp"
    Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
    Expand-7zipArchive -Path $archivePath -DestinationPath $tempFolder

    $modelPath = Get-ChildItem -Path $tempFolder -Filter Descriptor -Recurse -ErrorAction SilentlyContinue -Force
    $metadataPath = $modelPath[0].Parent.Parent.FullName
    $metadataPath
    Copy-Item -Path "$metadataPath\" -Destination  (Join-Path $targetPath "PackagesLocalDirectory") -Recurse -Force

    $solutionPath = Get-ChildItem -Path $tempFolder -Filter *.sln -Recurse -ErrorAction SilentlyContinue -Force
    $projectsPath = $solutionPath[1].Directory.Parent.FullName
    $projectsPath
    Copy-Item -Path "$projectsPath\" -Destination (Join-Path $targetPath "VSProjects") -Recurse -Force
    Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
}

function Get-FSCDefaultNuGets {
    [CmdletBinding()]
    param (
        [string]$PlatformVersion,
        [string]$ApplicationVersion
    )
        #Temporary sas token
        $storageAccountUrl = "https://ciellosnuget.z13.web.core.windows.net"
        $dest = "c:\temp\packages\"

        Remove-Item $dest -Recurse -ErrorAction SilentlyContinue -Force
        [System.IO.Directory]::CreateDirectory($dest)

        $applicationBuildName   = "Microsoft.Dynamics.AX.Application.DevALM.BuildXpp"
        $applicationSuiteName   = "Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp"
        $compileToolsName       = "Microsoft.Dynamics.AX.Platform.CompilerPackage"
        $platformNuildName      = "Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp"

        $applicationBuildNameUrl   = "$storageAccountUrl/$applicationBuildName.$ApplicationVersion.nupkg"
        $applicationSuiteNameUrl   = "$storageAccountUrl/$applicationSuiteName.$ApplicationVersion.nupkg"
        $compileToolsNameUrl       = "$storageAccountUrl/$compileToolsName.$PlatformVersion.nupkg"
        $platformNuildNameUrl      = "$storageAccountUrl/$platformNuildName.$PlatformVersion.nupkg"

        Invoke-WebRequest -URI $applicationBuildNameUrl -OutFile $dest\"$($applicationBuildName+".nupkg")"
        Invoke-WebRequest -URI $applicationSuiteNameUrl -OutFile $dest\"$($applicationSuiteName+".nupkg")"
        Invoke-WebRequest -URI $compileToolsNameUrl     -OutFile $dest\"$($compileToolsName+".nupkg")"
        Invoke-WebRequest -URI $platformNuildNameUrl    -OutFile $dest\"$($platformNuildName+".nupkg")"

        Get-ChildItem $dest 
 }


 function ConvertTo-ASCIIArt
 {

<#
.SYNOPSIS
    Convertto-TextASCIIArt converts text string to ASCII Art.
.DESCRIPTION
    The Convertto-TextASCIIArt show normal string or text as big font nicely on console. I have created one font for use (It is not exactly font but background color and cannot be copied), alternatively if you are using online parameter it will fetch more fonts online from 'http://artii.herokuapp.com'.
.PARAMETER Text
    This is common parameter for inbuilt and online and incase not provided default value is '# This is test !', If you are using inbuilt font small letter will convert to capital letter.
.PARAMETER Online
    To use this parameter make sure you have active internet connection, as it will connect to website http://artii.herokuapp.com and and using api it will download the acsii Art
.PARAMETER FontName
    There are wide variaty of font list available on http://artii.herokuapp.com/fonts_list, when using online parameter, Value provided here is case sensetive.
.PARAMETER FontColor
    Below is the list of font color can be used to show ascii art.
    'Black', 'DarkBlue','DarkGreen','DarkCyan', 'DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White'
.PARAMETER FontHight
    This parameter is optional and default value is 5, this is font hight and required for the font I created. Algorithm of this script is depend on the default value.
.INPUTS
    [System.String]
.OUTPUTS
    [console]
.NOTES
    Version:        1.0
    Author:         Janvi Udapi
    Creation Date:  30 September 2017
    Purpose/Change: Personal use to show text to ascii art.
    Useful URLs: http://vcloud-lab.com, http://artii.herokuapp.com/fonts_list
.EXAMPLE
    PS C:\>.\Convertto-TextASCIIArt -Online -Text "http://vcloud-lab.com" -FontColor Gray -Fontname big
  _     _   _              ____         _                 _        _       _                         
 | |   | | | |       _    / / /        | |               | |      | |     | |                        
 | |__ | |_| |_ _ __(_)  / / /_   _____| | ___  _   _  __| |______| | __ _| |__   ___ ___  _ __ ___  
 | '_ \| __| __| '_ \   / / /\ \ / / __| |/ _ \| | | |/ _` |______| |/ _` | '_ \ / __/ _ \| '_ ` _ \ 
 | | | | |_| |_| |_) | / / /  \ V / (__| | (_) | |_| | (_| |      | | (_| | |_) | (__ (_) | | | | | |
 |_| |_|\__|\__| .__(_)_/_/    \_/ \___|_|\___/ \__,_|\__,_|      |_|\__,_|_.__(_)___\___/|_| |_| |_|
               | |                                                                                   
               |_|                                                                                   

    Shows and converts text to cool ascii art from online site http://artii.herokuapp.com using apis.
.EXAMPLE
    PS C:\>.\Convertto-TextASCIIArt -Text '# This !'

      ██  ██     ██████ ██  ██ ██   ████     ██
    ██████████     ██   ██  ██ ██ ██         ██  
      ██  ██       ██   ██████ ██   ██       ██  
    ██████████     ██   ██  ██ ██     ██    
      ██  ██       ██   ██  ██ ██ ████       ██  
    
    Shows local font on the script not internet required
#>

[CmdletBinding(SupportsShouldProcess=$True,
    ConfirmImpact='Medium',
    HelpURI='http://vcloud-lab.com',
    DefaultParameterSetName='Inbuilt')]
Param
(
    [parameter(Position=0, ParameterSetName='Inbuilt', ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, HelpMessage='Provide valid text')]
    [parameter(Position=0, ParameterSetName='Online', ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, HelpMessage='Provide valid text')]
    [string]$Text = '# This is test !',
    [parameter(Position=2, ParameterSetName='Inbuilt', ValueFromPipelineByPropertyName=$true, HelpMessage='Provide existing font hight')]
    [Alias('Hight')]    
    [string]$FontHight = '5',
    
    [parameter(Position=2, ParameterSetName='Online', ValueFromPipelineByPropertyName=$true, HelpMessage='Provide font name list is avaliable on http://artii.herokuapp.com/fonts_list')]
    [ValidateSet('3-d','3x5','5lineoblique','1943____','4x4_offr','64f1____','a_zooloo','advenger','aquaplan','asc_____','ascii___','assalt_m','asslt__m','atc_____','atc_gran','b_m__200','battle_s','battlesh','baz__bil','beer_pub','bubble__','bubble_b','c1______','c2______','c_ascii_','c_consen','caus_in_','char1___','char2___','char3___','char4___','charact1','charact2','charact3','charact4','charact5','charact6','characte','charset_','coil_cop','com_sen_','computer','convoy__','d_dragon','dcs_bfmo','deep_str','demo_1__','demo_2__','demo_m__','devilish','druid___','e__fist_','ebbs_1__','ebbs_2__','eca_____','etcrvs__','f15_____','faces_of','fair_mea','fairligh','fantasy_','fbr12___','fbr1____','fbr2____','fbr_stri','fbr_tilt','finalass','fireing_','flyn_sh','fp1_____','fp2_____','funky_dr','future_1','future_2','future_3','future_4','future_5','future_6','future_7','future_8','gauntlet','ghost_bo','gothic','gothic__','grand_pr','green_be','hades___','heavy_me','heroboti','high_noo','hills___','home_pak','house_of','hypa_bal','hyper___','inc_raw_','italics_','joust___','kgames_i','kik_star','krak_out','lazy_jon','letter_w','letterw3','lexible_','mad_nurs','magic_ma','master_o','mayhem_d','mcg_____','mig_ally','modern__','new_asci','nfi1____','notie_ca','npn_____','odel_lak','ok_beer_','outrun__','p_s_h_m_','p_skateb','pacos_pe','panther_','pawn_ins','phonix__','platoon2','platoon_','pod_____','r2-d2___','rad_____','rad_phan','radical_','rainbow_','rally_s2','rally_sp','rampage_','rastan__','raw_recu','rci_____','ripper!_','road_rai','rockbox_','rok_____','roman','roman___','script__','skate_ro','skateord','skateroc','sketch_s','sm______','space_op','spc_demo','star_war','stealth_','stencil1','stencil2','street_s','subteran','super_te','t__of_ap','tav1____','taxi____','tec1____','tec_7000','tecrvs__','ti_pan__','timesofl','tomahawk','top_duck','trashman','triad_st','ts1_____','tsm_____','tsn_base','twin_cob','type_set','ucf_fan_','ugalympi','unarmed_','usa_____','usa_pq__','vortron_','war_of_w','yie-ar__','yie_ar_k','z-pilot_','zig_zag_','zone7___','acrobatic','alligator','alligator2','alphabet','avatar','banner','banner3-D','banner3','banner4','barbwire','basic','5x7','5x8','6x10','6x9','brite','briteb','britebi','britei','chartr','chartri','clb6x10','clb8x10','clb8x8','cli8x8','clr4x6','clr5x10','clr5x6','clr5x8','clr6x10','clr6x6','clr6x8','clr7x10','clr7x8','clr8x10','clr8x8','cour','courb','courbi','couri','helv','helvb','helvbi','helvi','sans','sansb','sansbi','sansi','sbook','sbookb','sbookbi','sbooki','times','tty','ttyb','utopia','utopiab','utopiabi','utopiai','xbrite','xbriteb','xbritebi','xbritei','xchartr','xchartri','xcour','xcourb','xcourbi','xcouri','xhelv','xhelvb','xhelvbi','xhelvi','xsans','xsansb','xsansbi','xsansi','xsbook','xsbookb','xsbookbi','xsbooki','xtimes','xtty','xttyb','bell','big','bigchief','binary','block','broadway','bubble','bulbhead','calgphy2','caligraphy','catwalk','chunky','coinstak','colossal','contessa','contrast','cosmic','cosmike','crawford','cricket','cursive','cyberlarge','cybermedium','cybersmall','decimal','diamond','digital','doh','doom','dotmatrix','double','drpepper','dwhistled','eftichess','eftifont','eftipiti','eftirobot','eftitalic','eftiwall','eftiwater','epic','fender','fourtops','fraktur','goofy','graceful','gradient','graffiti','hex','hollywood','invita','isometric1','isometric2','isometric3','isometric4','italic','ivrit','jazmine','jerusalem','katakana','kban','l4me','larry3d','lcd','lean','letters','linux','lockergnome','madrid','marquee','maxfour','mike','mini','mirror','mnemonic','morse','moscow','mshebrew210','nancyj-fancy','nancyj-underlined','nancyj','nipples','ntgreek','nvscript','o8','octal','ogre','os2','pawp','peaks','pebbles','pepper','poison','puffy','pyramid','rectangles','relief','relief2','rev','rot13','rounded','rowancap','rozzo','runic','runyc','sblood','script','serifcap','shadow','short','slant','slide','slscript','small','smisome1','smkeyboard','smscript','smshadow','smslant','smtengwar','speed','stacey','stampatello','standard','starwars','stellar','stop','straight','tanja','tengwar','term','thick','thin','threepoint','ticks','ticksslant','tinker-toy','tombstone','trek','tsalagi','twopoint','univers','usaflag','weird','whimsy')]
    [Alias('Font')]
    [string]$FontName = 'big',

    [parameter(ParameterSetName = 'Online', Position=0, Mandatory=$false)]
    [Switch]$Online,

    [parameter(Position=1, ParameterSetName='Inbuilt', ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, HelpMessage='Provide valid console color')]
    [parameter(ParameterSetName = 'Online', Position=1, Mandatory=$false, HelpMessage='Provide valid console color')]  
    [Alias('Color')]
    [ValidateSet('Black', 'DarkBlue','DarkGreen','DarkCyan', 'DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')]
    [string]$FontColor = 'Yellow'
)
Begin {
    #$NonExistFont = $null
    if ($PsCmdlet.ParameterSetName -eq 'Inbuilt') {
        $a = {<#a 07#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#a#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor  -NoNewline; Write-Host " "
        <#a#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor  -NoNewline; Write-Host " "
        <#a#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#a#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor  -NoNewline; Write-Host " "} 
        $b = {<#b 07#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 3) 
        <#b#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor   -NoNewline; Write-Host " "
        <#b#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#b#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor  -NoNewline; Write-Host " "
        <#b#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 3) } 
        $c = {<#c 07#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#c#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4) 
        <#c#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#c#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#c#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $d = {<#d 07#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 3)
        <#d#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#d#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#d#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#d#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 3)}  
        $e = {<#e 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#e#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#e#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host "  " 
        <#e#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#e#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $f = {<#f 07#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#f#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#f#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host "  "
        <#f#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#f#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)}
        $g = {<#g 07#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#g#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 5)
        <#g#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host " " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#g#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#g#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $h = {<#h 07#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#h#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#h#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#h#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#h#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $i = {<#i 03#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#i#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "  
        <#i#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#i#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#i#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $j = {<#j 07#> Write-Host "  " -NoNewline; Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#j#> Write-Host $(" " * 4) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host " "  
        <#j#> Write-Host $(" " * 4) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host " " 
        <#h#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#j#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $k = {<#k 09#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#k#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host " " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#k#> Write-Host $(" " * 3) -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 5)
        <#k#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host " " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#k#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $l = {<#l 05#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host " "
        <#l#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#l#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#l#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#l#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $m = {<#m 09#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#m#> Write-Host $(" " * 3) -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host $(" " * 3) -NoNewline -BackgroundColor $FontColor; Write-Host " "
        <#m#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host " " -NoNewline ; Write-Host "  " -NoNewline -BackgroundColor $FontColor ; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#m#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#m#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $n = {<#n 09#> Write-Host $(" " * 3) -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#n#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host " " -NoNewline; Write-Host " " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#n#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host " " -NoNewline -BackgroundColor $FontColor ; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#n#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3) -NoNewline; Write-Host " " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#n#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $o = {<#o 07#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#o#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#o#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#o#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#o#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $p = {<#p 07#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#p#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#p#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#p#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 5) 
        <#p#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 5)}
        $q = {<#q 09#> Write-Host "  " -NoNewline; Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 3)
        <#q#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#q#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#q#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#q#> Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $r = {<#r 07#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#r#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#r#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#r#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 3)
        <#r#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $s = {<#s 07#> Write-Host "  " -NoNewline; Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#s#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 5)
        <#s#> Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#s#> Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#s#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host " "}
        $t = {<#t 07#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#t#> Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#t#> Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#t#> Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3) 
        <#t#> Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)}
        $u = {<#u 07#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#u#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#u#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#u#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#u#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $v = {<#v 11#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 6) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#v#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 6) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#v#> Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  "
        <#v#> Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3)
        <#v#> Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 5)}
        $w = {<#W 09#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host  $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#W#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host  $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#W#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline ; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#W#> Write-Host $(" " * 3) -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host $(" " * 3) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#W#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host  $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $x = {<#x 09#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#x#> Write-Host " " -NoNewline ; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " 
        <#x#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4) 
        <#x#> Write-Host " " -NoNewline ; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " 
        <#x#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $y = {<#y 11#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#y#> Write-Host " " -NoNewline;  Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  "
        <#y#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4) 
        <#y#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4) 
        <#y#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4)}
        $z = {<#z 07#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#z#> Write-Host $(" " * 4) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor ; Write-Host " " 
        <#z#> Write-Host "  " -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 3) 
        <#z#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 5)
        <#z#> Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $hyphen = {<#- 05#> Write-Host $(" " * 5)
        <#-#> Write-Host $(" " * 5)
        <#-#> Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#-#> Write-Host $(" " * 5)
        <#-#> Write-Host $(" " * 5)}
        $Hash = {<## 11#> Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host (" " * 3)
        <###> Write-Host $(" " * 10) -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <###> Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host (" " * 3)
        <###> Write-Host $(" " * 10) -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <###> Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host (" " * 3)}
        $AtRate = {<#@ 09#> Write-Host " " -NosNewline; Write-Host $(" " * 6) -BackgroundColor $FontColor -NoNewline; Write-Host "  "
        <#@#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host (" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#@#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host " " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#@#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  " -NoNewline; Write-Host " " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#@#> Write-Host " " -NoNewline; Write-Host $(" " * 4) -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $Exlaim = {<#! 03#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#!#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "  
        <#!#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#!#> Write-Host $(" " * 3)
        <#!#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $Dot = {<#. 03#> Write-Host $(" " * 3)
        <#.#> Write-Host $(" " * 3)  
        <#.#> Write-Host $(" " * 3) 
        <#.#> Write-Host $(" " * 3)
        <#.#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $Forward = {<#. 07#> Write-Host $(" " * 4) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#/#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host "  "
        <#/#> Write-Host "  " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 3)
        <#/#> Write-Host $(" " * 1) -NoNewline ; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#/#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 5)}
        $Colun = {<#: 03#> Write-Host $(" " * 3)
        <#:#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#:#> Write-Host $(" " * 3)  
        <#:#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#:#> Write-Host $(" " * 3)}
        $Space = {<#  02#> Write-Host $(" " * 2)
        <# #> Write-Host $(" " * 2)
        <# #> Write-Host $(" " * 2)
        <# #> Write-Host $(" " * 2)
        <# #> Write-Host $(" " * 2)}
        $1 = {<#1 04#> Write-Host $(" " * 3) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#1 #> Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#1 #> Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#1 #> Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#1 #> Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $2 = {<#2 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#2#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -NoNewline -BackgroundColor $FontColor ; Write-Host " " 
        <#z#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#z#> Write-Host "  " -NoNewline -BackgroundColor $FontColor; Write-Host $(" " * 4)
        <#z#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $3 = {<#3 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#3#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#3#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#3#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#3#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $4 = {<#4 06#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#4#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#4#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#4#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#4#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $5 = {<#5 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#s#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#s#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#s#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#s#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $6 = {<#6 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#6#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host $(" " * 4)
        <#6#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#6#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#6#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $7 = {<#7 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#7#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#7#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#7#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#7#> Write-Host $(" " * 3) -NoNewline;  Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $8 = {<#8 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#8#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#8#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#8#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#8#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $9 = {<#9 06#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#9#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#9#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "
        <#9#> Write-Host $(" " * 3) -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#9#> Write-Host $(" " * 5) -BackgroundColor $FontColor -NoNewline; Write-Host " "}
        $0 = {<#0 06#> Write-Host " " -NoNewline ;Write-Host $(" " * 3) -BackgroundColor $FontColor -NoNewline; Write-Host "  "
        <#0#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#0#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#0#> Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " -NoNewline; Write-Host "  " -BackgroundColor $FontColor -NoNewline; Write-Host " " 
        <#0#> Write-Host " " -NoNewline; Write-Host $(" " * 3) -BackgroundColor $FontColor -NoNewline; Write-Host "  "}
    }#if
}
Process {
    switch ($PsCmdlet.ParameterSetName) {
        'Inbuilt' {    
            [char[]]$AllCharacters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'
            foreach ($singleChar in $AllCharacters) {
                $CharScript = Get-Variable -Name $singleChar | Select-Object -ExpandProperty Value
                $CharScript = ($CharScript -split "`r`n")
                New-Variable -Name $singleChar -Value $CharScript -Force
            }
            $hyphen = $hyphen -split "`r`n"
            $Hash = $Hash -split "`r`n"
            $AtRate = $AtRate -split "`r`n"
            $Exlaim = $Exlaim -split "`r`n"
            $Dot = $Dot -split "`r`n"
            $Forward = $Forward -split "`r`n"
            $Colun = $Colun -split "`r`n"
            $Space = $Space -split "`r`n"

            $textlength = $text.Length 
            [char[]]$TextBreakDown = $text 
  
            $wordart = @() 
            $FindWidth  = @()
            $NonExistFont = @()

            for ($ind= 0; $ind -lt $FontHight; $ind++) { 
                $Conf = 1 
                foreach ($character in $TextBreakDown) { 
                    $NoFont = $True
                    Switch -regex ($character) {
                        '-' {
                            $charname =  Get-Variable -Name hyphen
                            break
                        } #-
                        '#' {
                            $charname =  Get-Variable -Name Hash
                            break
                        } ##
                        '@' {
                            $charname =  Get-Variable -Name AtRate
                            break
                        } #-
                        '!' {
                            $charname =  Get-Variable -Name Exlaim
                            break
                        } #!
                        '\.' {
                            $charname =  Get-Variable -Name Dot
                            break
                        } #.
                        ':' {
                            $charname =  Get-Variable -Name Colun
                            break
                        } #.
                        '/' {
                            $charname =  Get-Variable -Name Forward
                            break
                        } #.
                        '\s' {
                            $charname =  Get-Variable -Name space
                            break
                        } #.
                        "[A-Za-z_0-9]" {
                            $charname = Get-Variable -Name $character
                            break
                        } 
                        default {
                            $NoFont = $false
                            break
                        } #default
                    } #switch
                
                    if ($NoFont -eq $True) {
                        if ($Conf -eq $textlength) { 
                            $info = $charname.value[$ind] 
                            $wordart += $info
                        } #if conf
                        else {
                            $info = $charname.value[$ind] 
                            $wordart += "{0} {1}" -f $info, '-NoNewLine'
                        } #else conf
                        $wordart += "`r`n"
                
                        #Get First Line to calculate width
                        if ($ind -eq 0) {
                            $FindWidth += $charname.value[$ind]
                        } #if ind
                
                        #Calculate font width
                        if ($ind -eq 0) {
                            $AllFirstLines = @()
                            $FindWidth = $FindWidth.trim() | Where-Object {$_ -ne ""}
                            $CharWidth = $FindWidth | foreach {$_.Substring(4,2)}
                            $BigFontWidth = $CharWidth | Measure-Object -Sum | Select-Object -ExpandProperty Sum
                        } #if ind

                    } #if NoFont
                    else {
                        $NonExistFont += $character
                    } #else NoFont
                    $Conf++
                } #foreach character
            } #for
            $TempFilePath = [System.IO.Path]::GetTempPath()
            $TempFileName = "{0}{1}" -f $TempFilePath, 'Show-BigFontOnConsole.ps1'
            $wordart | foreach {$_.trim()} | Out-File $TempFileName
            & $TempFileName
            if ($NonExistFont -ne $null) {
                $NonExistFont = $NonExistFont | Sort-Object | Get-Unique
                $NonResult = $NonExistFont -join " "
                Write-Host "`n`nSkipping as, No ascii fonts found for $NonResult" -BackgroundColor DarkRed
            } # if NonExistFont
        } #Inbuilt
        'Online' {
            if ($text -eq '# This is test !') {
                $text = 'http://vcloud-lab.com'
            }
            $testEncode = [uri]::EscapeDataString($Text)
            $url = "http://artii.herokuapp.com/make?text=$testEncode&font=$FontName"
            Try {
                $WebsiteApi = Invoke-WebRequest -Uri $url -ErrorAction Stop
                Write-Host $WebsiteApi.Content -ForegroundColor $FontColor
            }
            catch {
                $errMessage = "Check your internet connection, Verify below url in browser`n"
                $errMessage += $url
                Write-Host $errMessage -BackgroundColor DarkRed
            }
        } #Online
    } #switch pscmdlet
}
end {
}

 }
################################################################################
# End - Private functions.
################################################################################



