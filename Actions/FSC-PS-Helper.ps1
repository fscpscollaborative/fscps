Param(
    [switch] $local
)

$gitHubHelperPath = Join-Path $PSScriptRoot 'Helpers\Github-Helper.psm1'
if (Test-Path $gitHubHelperPath) {
    Import-Module $gitHubHelperPath
}
$lcsHelperPath = Join-Path $PSScriptRoot 'Helpers\LCS-Helper.psm1'
if (Test-Path $lcsHelperPath) {
    Import-Module $lcsHelperPath
}
enum LcsAssetFileType {
    Model = 1
    ProcessDataPackage = 4
    SoftwareDeployablePackage = 10
    GERConfiguration = 12
    DataPackage = 15
    PowerBIReportModel = 19
    ECommercePackage = 26
    NuGetPackage = 27
    RetailSelfServicePackage = 28
    CommerceCloudScaleUnitExtension = 29
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
function OutputVerbose {
    Param(
        [string] $message
    )

    Write-Host $message
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
function Compress-7zipArchive {
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
        $command = '7z a -t7z "{0}" "{1}"' -f $DestinationPath, $Path
        Invoke-Expression -Command $command | Out-Null
    }
    else {
        OutputDebug -message "Using Compress-Archive"
        Compress-Archive -Path $Path -DestinationPath "$DestinationPath" -Force
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
        $includeTest = $false,
        [switch]
        $all = $false

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
            if(!(Test-Path ("$metadataPath/$($_.BaseName)/Descriptor")) -and !$testModel -and $all) {
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
        "fscPsVer"                               = "v1.2"
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
        "useLocalNuGetStorage"                   = $true
        "githubSecrets"                          = ""
        "buildPath"                              = "_bld"
        "metadataPath"                           = "PackagesLocalDirectory"
        "lcsEnvironmentId"                       = ""
        "lcsProjectId"                           = 123456
        "lcsClientId"                            = ""
        "lcsUsernameSecretname"                  = "AZ_TENANT_USERNAME"
        "lcsPasswordSecretname"                  = "AZ_TENANT_PASSWORD"
        "azTenantId"                             = ""
        "azClientId"                             = ""
        "azClientsecretSecretname"               = "AZ_CLIENTSECRET"
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
        "ecommerceMicrosoftRepoUrl"              = "https://github.com/microsoft/Msdyn365.Commerce.Online.git"
        "ecommerceMicrosoftRepoBranch"           = "master"
        "repoTokenSecretName"                    = "REPO_TOKEN"
        "ciBranches"                             = "main,release"
        "deployScheduleCron"                     = "1 * * * *"
        "deploy"                                 = $false
        "deployOnlyNew"                          = $true
        "deploymentScheduler"                    = $true        
        "fscFinalQualityUpdatePackageId"         = ""    
        "fscPreviewVersionPackageId"             = ""    
        "fscServiseUpdatePackageId"              = ""  
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
function installModules {
    Param(
        [String[]] $modules
    )
    begin{
        Set-MpPreference -DisableRealtimeMonitoring $true
    }
    process{
        $modules | ForEach-Object {
            if($_ -eq "Az")
            {
                Set-ExecutionPolicy RemoteSigned
                try {
                    Uninstall-AzureRm
                }
                catch {
                }
                
            }

            if (-not (get-installedmodule -Name $_ -ErrorAction SilentlyContinue)) {
                Write-Host "Installing module $_"
                Install-Module $_ -Force -AllowClobber | Out-Null
            }
        }

        $modules | ForEach-Object { 
            Write-Host "Importing module $_"
            Import-Module $_ -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
        }

    }
    end{
        Set-MpPreference -DisableRealtimeMonitoring $false
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
function GenerateProjectFile {
    [CmdletBinding()]
    param (
        [string]$ModelName,
        [string]$MetadataPath,
        [string]$ProjectGuid
    )

    $ProjectFileName =  'Build.rnrproj'
    $ModelProjectFileName = $ModelName + '.rnrproj'
    $NugetFolderPath =  Join-Path $PSScriptRoot 'NewBuild'
    $SolutionFolderPath = Join-Path  $NugetFolderPath 'Build'
    $ModelProjectFile = Join-Path $SolutionFolderPath $ModelProjectFileName
    #$modelDisplayName = Get-AXModelDisplayName -ModelName $ModelName -ModelPath $MetadataPath 
    $modelDescriptorName = Get-AXModelName -ModelName $ModelName -ModelPath $MetadataPath 
    #generate project file

    if($modelDescriptorName -eq "")
    {
        $ProjectFileData = (Get-Content $ProjectFileName).Replace('ModelName', $ModelName).Replace('62C69717-A1B6-43B5-9E86-24806782FEC2'.ToLower(), $ProjectGuid.ToLower())
    }
    else {
        $ProjectFileData = (Get-Content $ProjectFileName).Replace('ModelName', $modelDescriptorName).Replace('62C69717-A1B6-43B5-9E86-24806782FEC2'.ToLower(), $ProjectGuid.ToLower())
    }
    #$ProjectFileData = (Get-Content $ProjectFileName).Replace('ModelName', $modelDescriptorName).Replace('62C69717-A1B6-43B5-9E86-24806782FEC2'.ToLower(), $ProjectGuid.ToLower())
     
    Set-Content $ModelProjectFile $ProjectFileData
}
function Get-AXModelDisplayName {
    param (
        [Alias('ModelName')]
        [string]$_modelName,
        [Alias('ModelPath')]
        [string]$_modelPath
    )
    process{
        $descriptorSearchPath = (Join-Path $_modelPath (Join-Path $_modelName "Descriptor"))
        $descriptor = (Get-ChildItem -Path $descriptorSearchPath -Filter '*.xml')
        if($descriptor)
        {
            OutputVerbose "Descriptor found at $descriptor"
            [xml]$xmlData = Get-Content $descriptor.FullName
            $modelDisplayName = $xmlData.SelectNodes("//AxModelInfo/DisplayName")
            return $modelDisplayName.InnerText
        }
    }
}
function Get-AXModelName {
    param (
        [Alias('ModelName')]
        [string]$_modelName,
        [Alias('ModelPath')]
        [string]$_modelPath
    )
    process{
        $descriptorSearchPath = (Join-Path $_modelPath (Join-Path $_modelName "Descriptor"))
        $descriptor = (Get-ChildItem -Path $descriptorSearchPath -Filter '*.xml')
        OutputVerbose "Descriptor found at $descriptor"
        [xml]$xmlData = Get-Content $descriptor.FullName
        $modelDisplayName = $xmlData.SelectNodes("//AxModelInfo/Name")
        return $modelDisplayName.InnerText
    }
}
function GenerateSolution {
    [CmdletBinding()]
    param (
        [string]$ModelName,
        [string]$NugetFeedName,
        [string]$NugetSourcePath,
        [string]$DynamicsVersion,
        [string]$MetadataPath
    )

    cd $PSScriptRoot\Build\Build

    OutputDebug "MetadataPath: $MetadataPath"

    $SolutionFileName =  'Build.sln'
    $NugetFolderPath =  Join-Path $PSScriptRoot 'NewBuild'
    $SolutionFolderPath = Join-Path  $NugetFolderPath 'Build'
    $NewSolutionName = Join-Path  $SolutionFolderPath 'Build.sln'
    New-Item -ItemType Directory -Path $SolutionFolderPath -ErrorAction SilentlyContinue
    Copy-Item build.props -Destination $SolutionFolderPath -force
    $ProjectPattern = 'Project("{FC65038C-1B2F-41E1-A629-BED71D161FFF}") = "ModelNameBuild (ISV) [ModelDisplayName]", "ModelName.rnrproj", "{62C69717-A1B6-43B5-9E86-24806782FEC2}"'
    $ActiveCFGPattern = '		{62C69717-A1B6-43B5-9E86-24806782FEC2}.Debug|Any CPU.ActiveCfg = Debug|Any CPU'
    $BuildPattern = '		{62C69717-A1B6-43B5-9E86-24806782FEC2}.Debug|Any CPU.Build.0 = Debug|Any CPU'

    [String[]] $SolutionFileData = @() 

    $projectGuids = @{};
    OutputDebug "Generate projects GUIDs..."
    Foreach($model in $ModelName.Split(','))
    {
        $projectGuids.Add($model, ([string][guid]::NewGuid()).ToUpper())
    }
    OutputDebug $projectGuids

    #generate project files file
    $FileOriginal = Get-Content $SolutionFileName
        
    OutputDebug "Parse files"
    Foreach ($Line in $FileOriginal)
    {   
        $SolutionFileData += $Line
        Foreach($model in $ModelName.Split(','))
        {
            $projectGuid = $projectGuids.Item($model)

            if ($Line -eq $ProjectPattern) 
            {
                OutputDebug "Get AXModel Display Name"
                $modelDisplayName = Get-AXModelDisplayName -ModelName $model -ModelPath $MetadataPath 
                OutputDebug "AXModel Display Name is $modelDisplayName"
                OutputDebug "Update Project line"
                $newLine = $ProjectPattern -replace 'ModelName', $model
                $newLine = $newLine -replace 'ModelDisplayName', $modelDisplayName
                $newLine = $newLine -replace 'Build.rnrproj', ($model+'.rnrproj')
                $newLine = $newLine -replace '62C69717-A1B6-43B5-9E86-24806782FEC2', $projectGuid
                #Add Lines after the selected pattern 
                $SolutionFileData += $newLine                
                $SolutionFileData += "EndProject"
        
            } 
            if ($Line -eq $ActiveCFGPattern) 
            { 
                OutputDebug "Update Active CFG line"
                $newLine = $ActiveCFGPattern -replace '62C69717-A1B6-43B5-9E86-24806782FEC2', $projectGuid
                $SolutionFileData += $newLine
            } 
            if ($Line -eq $BuildPattern) 
            {
                OutputDebug "Update Build line"
                $newLine = $BuildPattern -replace '62C69717-A1B6-43B5-9E86-24806782FEC2', $projectGuid
                $SolutionFileData += $newLine
            } 
        }
    }
    OutputDebug "Save solution file"
    #save solution file 
    Set-Content $NewSolutionName $SolutionFileData;
    #cleanup solution file
    $tempFile = Get-Content $NewSolutionName
    $tempFile | Where-Object {$_ -ne $ProjectPattern} | Where-Object {$_ -ne $ActiveCFGPattern} | Where-Object {$_ -ne $BuildPattern} | Set-Content -Path $NewSolutionName 

    #generate project files
    Foreach($project in $projectGuids.GetEnumerator())
    {
        GenerateProjectFile -ModelName $project.Name -ProjectGuid $project.Value -MetadataPath $MetadataPath 
    }

    cd $PSScriptRoot\Build
    #generate nuget.config
    $NugetConfigFileName = 'nuget.config'
    $NewNugetFile = Join-Path $NugetFolderPath $NugetConfigFileName
    if($NugetFeedName)
    {
        $tempFile = (Get-Content $NugetConfigFileName).Replace('NugetFeedName', $NugetFeedName).Replace('NugetSourcePath', $NugetSourcePath)
    }
    else {
        $tempFile = (Get-Content $NugetConfigFileName).Replace('<add key="NugetFeedName" value="NugetSourcePath" />', '')
    }
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
    begin
    {
        OutputDebug "SDKVersion is $sdkVersion"
        OutputDebug "SDKPath is $sdkPath"
        $storageAccountName = 'ciellosarchive'
        $storageContainer = 'retailsdk'
        #Just read-only SAS token :)
        $StorageSAStoken = 'sp=r&st=2022-10-26T06:49:19Z&se=2032-10-26T14:49:19Z&spr=https&sv=2021-06-08&sr=c&sig=MXHL7F8liAPlwIxzg8FJNjfwJVIjpLMqUV2HYlyvieA%3D'
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $StorageSAStoken
        $silent = [System.IO.Directory]::CreateDirectory($sdkPath) 
    }
    process
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $version = Get-VersionData -sdkVersion $sdkVersion
        $path = Join-Path $sdkPath ("RetailSDK.$($version.retailSDKVersion).7z")

        if(!(Test-Path -Path $path))
        {
            OutputDebug "RetailSDK $($version.retailSDKVersion) is not found."
            if($version.retailSDKURL)
            {
                OutputDebug "Web request. Downloading..."
                $silent = Invoke-WebRequest -Uri $version.retailSDKURL -OutFile $path
            }
            else {
                OutputDebug "Azure Blob. Downloading..."
                $silent = Get-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob ("RetailSDK.$($version.retailSDKVersion).7z") -Destination $path -ConcurrentTaskCount 10 -Force
            }
        }
        return $path
    }
}
function Update-FSCNuGet
{
    [CmdletBinding()]
    param (
        [string]$sdkVersion,
        [string]$NugetPath = 'C:\Temp\packages'
    )

    begin
    {
        $storageAccountName = 'ciellosarchive'
        $storageContainer = 'nuget'
        #Just read-only SAS token :)
        $StorageSAStoken = 'sp=r&st=2022-10-20T15:35:07Z&se=2032-10-20T23:35:07Z&spr=https&sv=2021-06-08&sr=c&sig=LZ94qSS%2FRmRObp6Fs%2FuTXM6KZKdSDY3kLZf02mF9ihc%3D'
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $StorageSAStoken
        [System.IO.Directory]::CreateDirectory($NugetPath) 
    }
    process
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $version = Get-VersionData -sdkVersion $sdkVersion

        $nugets = @(("Microsoft.Dynamics.AX.Application.DevALM.BuildXpp." + $version.AppVersion + ".nupkg"),
                    ("Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp." + $version.AppVersion + ".nupkg"),
                    ("Microsoft.Dynamics.AX.Platform.CompilerPackage." + $version.PlatformVersion + ".nupkg"),
                    ("Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp." + $version.PlatformVersion + ".nupkg") 
                    )

        $nugets | Foreach-Object{
            $destinationNugetFilePath = Join-Path $NugetPath $_ 
            
            $download = (-not(Test-Path $destinationNugetFilePath))

            if(!$download)
            {
                OutputDebug $_
                $blobSize = (Get-AzStorageBlob -Context $ctx -Container $storageContainer -Blob $_ -ConcurrentTaskCount 10).Length
                $localSize = (Get-Item $destinationNugetFilePath).length
                OutputDebug "BlobSize is: $blobSize"
                OutputDebug "LocalSize is: $blobSize"
                $download = $blobSize -ne $localSize
            }

            if($download)
            {
                $blob = Get-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob $_ -Destination $destinationNugetFilePath -ConcurrentTaskCount 10 -Force
                $blob.Name
            }
        } 
    }
}
function Get-NuGetVersion
{    
    [CmdletBinding()]
    param (
        [System.IO.DirectoryInfo]$NugetPath
    )
    begin{
        $zipFile = [IO.Compression.ZipFile]::OpenRead($NugetPath.FullName)
    }
    process{
        
        $zipFile.Entries | Where-Object {$_.FullName.Contains(".nuspec")} | ForEach-Object{
            $nuspecFilePath = "$(Join-Path $NugetPath.Parent.FullName $_.Name)"
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $nuspecFilePath, $true)

            [xml]$XmlDocument = Get-Content $nuspecFilePath
            $XmlDocument.package.metadata.version
            Remove-Item $nuspecFilePath
        }
    }
    end{
        $zipFile.Dispose()
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

function Update-FSCModelVersion {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$xppSourcePath,
        [Parameter()]
        [string]$xppDescriptorSearch,
        $xppLayer,
        $versionNumber
    )

    if ($xppDescriptorSearch.Contains("`n"))
    {
        [string[]]$xppDescriptorSearch = $xppDescriptorSearch -split "`n"
    }
    
    Test-Path -LiteralPath $xppSourcePath -PathType Container
        
    if ($versionNumber -match "^\d+\.\d+\.\d+\.\d+$")
    {
        $versions = $versionNumber.Split('.')
    }
    else
    {
        throw "Version Number '$versionNumber' is not of format #.#.#.#"
    }
    
    
    switch ( $xppLayer )
    {
        "SYS" { $xppLayer = 0 }
        "SYP" { $xppLayer = 1 }
        "GLS" { $xppLayer = 2 }
        "GLP" { $xppLayer = 3 }
        "FPK" { $xppLayer = 4 }
        "FPP" { $xppLayer = 5 }
        "SLN" { $xppLayer = 6 }
        "SLP" { $xppLayer = 7 }
        "ISV" { $xppLayer = 8 }
        "ISP" { $xppLayer = 9 }
        "VAR" { $xppLayer = 10 }
        "VAP" { $xppLayer = 11 }
        "CUS" { $xppLayer = 12 }
        "CUP" { $xppLayer = 13 }
        "USR" { $xppLayer = 14 }
        "USP" { $xppLayer = 15 }
    }
    
    
    
    # Discover packages
    #$BuildModuleDirectories = @(Get-ChildItem -Path $BuildMetadataDir -Directory)
    #foreach ($BuildModuleDirectory in $BuildModuleDirectories)
    #{
        $potentialDescriptors = Find-Match -DefaultRoot $xppSourcePath -Pattern $xppDescriptorSearch | Where-Object { (Test-Path -LiteralPath $_ -PathType Leaf) }
        if ($potentialDescriptors.Length -gt 0)
        {
            OutputInfo "Found $($potentialDescriptors.Length) potential descriptors"
    
            foreach ($descriptorFile in $potentialDescriptors)
            {
                try
                {
                    [xml]$xml = Get-Content $descriptorFile -Encoding UTF8
    
                    $modelInfo = $xml.SelectNodes("/AxModelInfo")
                    if ($modelInfo.Count -eq 1)
                    {
                        $layer = $xml.SelectNodes("/AxModelInfo/Layer")[0]
                        $layerid = $layer.InnerText
                        $layerid = [int]$layerid
    
                        $modelName = ($xml.SelectNodes("/AxModelInfo/Name")).InnerText
                            
                        # If this model's layer is equal or above lowest layer specified
                        if ($layerid -ge $xppLayer)
                        {
                            $version = $xml.SelectNodes("/AxModelInfo/VersionMajor")[0]
                            $version.InnerText = $versions[0]
    
                            $version = $xml.SelectNodes("/AxModelInfo/VersionMinor")[0]
                            $version.InnerText = $versions[1]
    
                            $version = $xml.SelectNodes("/AxModelInfo/VersionBuild")[0]
                            $version.InnerText = $versions[2]
    
                            $version = $xml.SelectNodes("/AxModelInfo/VersionRevision")[0]
                            $version.InnerText = $versions[3]
    
                            $xml.Save($descriptorFile)
    
                            OutputInfo " - Updated model $modelName version to $versionNumber in $descriptorFile"
                        }
                        else
                        {
                            OutputInfo " - Skipped $modelName because it is in a lower layer in $descriptorFile"
                        }
                    }
                    else
                    {
                        OutputError "File '$descriptorFile' is not a valid descriptor file"
                    }
                }
                catch
                {
                    OutputError "File '$descriptorFile' is not a valid descriptor file (exception: $($_.Exception.Message))"
                }
            }
        }
    #}        
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

        
        Unblock-File -Path "$PSScriptRoot\Helpers\Minimatch.dll"
        Add-Type -LiteralPath $PSScriptRoot\Helpers\Minimatch.dll

        <#
        Install-Package Minimatch -RequiredVersion 1.1.0 -Force  -Confirm:$false -Source https://www.nuget.org/api/v2
        $package = Get-Package Minimatch
        $zip = [System.IO.Compression.ZipFile]::Open($package.Source,"Read")
        $memStream = [System.IO.MemoryStream]::new()
        $reader = [System.IO.StreamReader]($zip.entries[2]).Open()
        $reader.BaseStream.CopyTo($memStream)
        [byte[]]$bytes = $memStream.ToArray()
        $reader.Close()
        $zip.dispose()
        [System.Reflection.Assembly]::Load($bytes)#>
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

                $childItems = @( Get-ChildItem -Path "$($Item.FullName)/*" -Force )
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
    
    Get-ChildItem -Path $metadataPath | ForEach-Object {
        $_.Name
        #if(Get-ChildItem -Path $_.FullName -Filter Descriptor -Recurse -ErrorAction SilentlyContinue -Force)
        #{
            Copy-Item -Path "$metadataPath\$($_.Name)" -Destination (Join-Path $targetPath "PackagesLocalDirectory\$($_.Name)") -Recurse -Force
        #}
    }
    
    $solutionPath = Get-ChildItem -Path $tempFolder -Filter *.sln -Recurse -ErrorAction SilentlyContinue -Force
    $projectsPath = $solutionPath[0].Directory.Parent.FullName
    $projectsPath
    Copy-Item -Path "$projectsPath\" -Destination (Join-Path $targetPath "VSProjects") -Recurse -Force
    Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
}

function Update-D365FSCISVSource
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
    
    Get-ChildItem -Path $metadataPath | ForEach-Object {
        $_.Name
        Remove-Item -Path (Join-Path $targetPath "PackagesLocalDirectory\$($_.Name)") -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
        Copy-Item -Path "$metadataPath\$($_.Name)" -Destination (Join-Path $targetPath "PackagesLocalDirectory\$($_.Name)") -Recurse -Force
    }
    
    Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
}
################################################################################
# End - Private functions.
################################################################################