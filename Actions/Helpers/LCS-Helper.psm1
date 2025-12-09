function GetUNHeader {
    param (
        [string] $token,
        [string] $accept = "application/json"
    )
    $headers = @{ "Accept" = $accept }
    if (![string]::IsNullOrEmpty($token)) {
        $headers["Authorization"] = "Bearer $token"
    }

    return $headers
}

function GetToken {
    param (
        [string] $lcsClientId,
        [string] $lcsUserName,
        [string] $lcsUserPasswd
    )
    $body = 'grant_type=password' + `
    '&client_id='+$($lcsClientId)+'' + `
    '&username='+$($lcsUserName)+'' +`
    '&password='+$($lcsUserPasswd)+'' +`
    '&resource=https://lcsapi.lcs.dynamics.com' +`
    '&scope=openid'

    return (Invoke-RestMethod -Method Post -Uri https://login.microsoftonline.com/common/oauth2/token -Body $body).access_token
}                   
function GetLCSSharedAssetsList {
    param (
        [string] $token,
        [LcsAssetFileType] $FileType = [LcsAssetFileType]::SoftwareDeployablePackage

    )
    $header = GetUNHeader -token $token
    # initialize the array
    [PsObject[]]$array = @()
    $url = "https://lcsapi.lcs.dynamics.com/box/fileasset/GetSharedAssets?fileType="+$($FileType.value__)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $assetList = @()

    $repeat = $true
    $cnt = 0
    do{
        try {
            $assetList = (Invoke-RestMethod -Method Get -Uri $url -Headers $header -TimeoutSec 360)
            $repeat = $false
        }
        catch {
            if($cnt -lt 4)
            {
                $repeat = $true
                $cnt++
            }
            else {
                $repeat = $false
            }
        } 
    }
    while($repeat)

    $assetList.GetEnumerator() | ForEach-Object {
        $array += [PsObject]@{ Name = $_.Name; FileName = $_.FileName; ModifiedDate = $_.ModifiedDate; Id = $_.Id }
    }
    return  $array 
}    
function Invoke-FSCRequestHandler {
    [CmdletBinding()]
    param (
        [Alias("HttpMethod")]
        [string] $Method,

        [string] $Uri,
        
        [string] $ContentType,

        [string] $Payload,

        [Hashtable] $Headers,

        [Timespan] $RetryTimeout = "00:00:00"
    )
    
    begin {
        $parms = @{}
        $parms.Method = $Method
        $parms.Uri = $Uri
        $parms.Headers = $Headers
        $parms.ContentType = $ContentType

        if ($Payload) {
            $parms.Body = $Payload
        }

        $start = (Get-Date)
        $handleTimeout = $false

        if ($RetryTimeout.Ticks -gt 0) {
            $handleTimeout = $true
        }
    }
    
    process {
        $429Attempts = 0

        do {
            $429Retry = $false

            try {
                Invoke-RestMethod @parms
            }
            catch [System.Net.WebException] {
                if ($_.exception.response.statuscode -eq 429) {
                    $429Retry = $true
                    
                    $retryWaitSec = $_.exception.response.Headers["Retry-After"]

                    if (-not ($retryWaitSec -gt 0)) {
                        $retryWaitSec = 10
                    }

                    if ($handleTimeout) {
                        $timeSinceStart = New-TimeSpan -End $(Get-Date) -Start $start
                        $timeWithWait = $timeSinceStart.Add([timespan]::FromSeconds($retryWaitSec))
                        
                        $temp = $RetryTimeout - $timeWithWait

                        if ($temp.Ticks -lt 0) {
                            #We will be exceeding the timeout limit
                            $messageString = "The timeout value suggested from the endpoint will exceed the RetryTimeout (<c='em'>$RetryTimeout</c>) threshold."
                            Write-PSFMessage -Level Host -Message $messageString -Exception $PSItem.Exception -Target $entity
                            Stop-PSFFunction -Message "Stopping because of errors." -Exception $([System.Exception]::new($($messageString -replace '<[^>]+>', ''))) -ErrorRecord $_ -StepsUpward 1
                            return
                        }
                    }

                    Write-PSFMessage -Level Host -Message "Hit a 429 status code. Will wait for: <c='em'>$retryWaitSec</c> seconds before trying again. Attempt (<c='em'>$429Attempts</c>)"
                    Start-Sleep -Seconds $retryWaitSec
                    $429Attempts++
                }
                else {
                    Throw
                }
            }
        } while ($429Retry)
    }
}
function ProcessingNuGet {
    param (
        [string]$AssetId,
        [string]$AssetName,
        [string]$ProjectId,
        [string]$LCSToken,
        [string]$StorageToken,
        [string]$PackageDestination = "C:\temp\packages",
        [string]$StorageSAStoken,
        [string]$LCSAssetName
    )
    Begin{
        $storageAccountName = 'ciellosarchive'
        $storageContainer = 'nuget'
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $StorageSAStoken
        $header = GetUNHeader -token $LCSToken
        if(-not(Test-Path $PackageDestination))
        {
            [System.IO.Directory]::CreateDirectory($PackageDestination)
        }
        Remove-Item -Path $PackageDestination/* -Recurse -Force
        OutputInfo "AssetId: $AssetId"
        OutputInfo "AssetName: $AssetName"
        OutputInfo "ProjectId: $ProjectId"
        OutputInfo "LCSToken: $LCSToken"
        OutputInfo "PackageDestination: $PackageDestination"
        OutputInfo "LCSAssetName: $LCSAssetName"
    }
    process {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $destinationNugetFilePath = Join-Path $PackageDestination $AssetName  

        #get download link asset
        $uri = "https://lcsapi.lcs.dynamics.com/box/fileasset/GetFileAsset/$($ProjectId)?assetId=$($AssetId)"
        $assetJson = (Invoke-RestMethod -Method Get -Uri $uri -Headers $header)

        if(Test-Path $destinationNugetFilePath)
        {
            $regex = [regex] "\b(([0-9]*[0-9])\.){3}(?:[0-9]*[0-9]?)\b"
            $filenameVersion = $regex.Match($AssetName).Value
            $version = Get-NuGetVersion $destinationNugetFilePath
            if($filenameVersion -ne "")
            {
                $newdestinationNugetFilePath = ($destinationNugetFilePath).Replace(".$filenameVersion.nupkg", ".nupkg") 
            }
            else { $newdestinationNugetFilePath = $destinationNugetFilePath }
            $newdestinationNugetFilePath = ($newdestinationNugetFilePath).Replace(".nupkg",".$version.nupkg")
            if(-not(Test-Path $newdestinationNugetFilePath))
            {
                Rename-Item -Path $destinationNugetFilePath -NewName ([System.IO.DirectoryInfo]$newdestinationNugetFilePath).FullName -Force -PassThru
            }
            $destinationNugetFilePath = $newdestinationNugetFilePath
        }
        $download = (-not(Test-Path $destinationNugetFilePath))

        $blob = Get-AzStorageBlob -Context $ctx -Container $storageContainer -Blob $AssetName -ConcurrentTaskCount 10 -ErrorAction SilentlyContinue
       
        if(!$blob)
        {
            if($download)
            {               
                # Test if AzCopy.exe exists in current folder
                $WantFile = "c:\temp\azcopy.exe"
                $AzCopyExists = Test-Path $WantFile
                
                # Download AzCopy if it doesn't exist
                If ($AzCopyExists -eq $False)
                {
                    Write-Output "AzCopy not found. Downloading..."

                    #Download AzCopy
                    Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile c:\temp\AzCopy.zip -UseBasicParsing

                    #Expand Archive
                    Write-Output "Expanding archive...`n"
                    Expand-Archive c:\temp\AzCopy.zip c:\temp\AzCopy -Force

                    # Copy AzCopy to current dir
                    Get-ChildItem c:\temp\AzCopy/*/azcopy.exe | Copy-Item -Destination "c:\temp\azcopy.exe"
                }
            
                & $WantFile copy $assetJson.FileLocation "$destinationNugetFilePath" --output-level quiet
                if(Test-Path $destinationNugetFilePath)
                {
                    $regex = [regex] "\b(([0-9]*[0-9])\.){3}(?:[0-9]*[0-9]?)\b"
                    $filenameVersion = $regex.Match($AssetName).Value
                    $version = Get-NuGetVersion $destinationNugetFilePath
                    if($filenameVersion -ne "")
                    {
                        $newdestinationNugetFilePath = ($destinationNugetFilePath).Replace(".$filenameVersion.nupkg", ".nupkg") 
                    }
                    else { $newdestinationNugetFilePath = $destinationNugetFilePath }
                    $newdestinationNugetFilePath = ($newdestinationNugetFilePath).Replace(".nupkg",".$version.nupkg")
                    if(-not(Test-Path $newdestinationNugetFilePath))
                    {
                        Rename-Item -Path $destinationNugetFilePath -NewName ([System.IO.DirectoryInfo]$newdestinationNugetFilePath).FullName -Force -PassThru
                    }
                    $destinationNugetFilePath = $newdestinationNugetFilePath
                }
                #Invoke-D365AzCopyTransfer $assetJson.FileLocation "$destinationNugetFilePath"
            }
        }
        else
        {
            if($download)
            {
                $blob = Get-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob $AssetName -Destination $destinationNugetFilePath -ConcurrentTaskCount 10 -Force
                $blob.Name
            }
            OutputInfo "Blob was found!"
        }

        $regex = [regex] "\b(([0-9]*[0-9])\.){3}(?:[0-9]*[0-9]?)\b"
        $filenameVersion = $regex.Match($AssetName).Value
        $version = Get-NuGetVersion $destinationNugetFilePath
        $AssetName = ($AssetName).Replace(".$filenameVersion.nupkg", ".nupkg") 
        $AssetName = ($AssetName).Replace(".nupkg",".$version.nupkg")
        OutputInfo "FSCVersion:  $FSCVersion"
        OutputInfo "AssetName:  $AssetName"

        if($FSCVersion -ne "")
        {
            $versions = New-Object System.Collections.ArrayList
            $versionsDefaultFile = "Actions\Helpers\versions.default.json"
            $versionsDefault = (Get-Content $versionsDefaultFile) | ConvertFrom-Json
            $versionsDefault | ForEach-Object{$versions.Add($_)}
            $curVer = $versions.Where({$_.version -eq $FSCVersion})
            if(!$curVer)
            {
                $curVer = (@{version=$FSCVersion;data=@{PlatformVersionGA='';AppVersionGA='';PlatformVersionLatest='';AppVersionLatest=''; EcommerceMicrosoftRepoBranch=''}} | ConvertTo-Json | ConvertFrom-Json)
                $versions.Add($curVer)
                $curVer = $versions.Where({$_.version -eq $FSCVersion})
            }
            switch ($AssetName) {
                {$AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.Platform.CompilerPackage.".ToLower()) -or
                $AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp.".ToLower())} 
                {  
                    $curVer.data.PlatformVersionLatest = Get-NewestNugetVersion $version $curVer.data.PlatformVersionLatest;   
                    if($LCSAssetName.StartsWith("PU"))
                    {
                        $ver = Get-NewestNugetVersion $version $curVer.data.PlatformVersionGA;
                        $curVer.data.PlatformVersionGA = $ver
                    }        
                    if($curVer.data.PlatformVersionGA -eq "")
                    {
                        $curVer.data.PlatformVersionGA = $curVer.data.PlatformVersionLatest
                    }    
                    break;
                }
                {$AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.Application.DevALM.BuildXpp.".ToLower()) -or
                $AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp.".ToLower())} 
                {  
                    $curVer.data.AppVersionLatest = Get-NewestNugetVersion $version $curVer.data.AppVersionLatest;
                    if($LCSAssetName.StartsWith("PU"))
                    {
                        $ver = Get-NewestNugetVersion $version $curVer.data.AppVersionGA;
                        $curVer.data.AppVersionGA = $ver
                    }        
                    if($curVer.data.AppVersionGA -eq "")
                    {
                        $curVer.data.AppVersionGA = $curVer.data.AppVersionLatest
                    }   
                    break;
                }
                Default {}
            }
            Set-Content -Path $versionsDefaultFile ($versions | Sort-Object{$_.version} | ConvertTo-Json)
        }   
        Set-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob "$AssetName" -File "$destinationNugetFilePath" -StandardBlobTier Hot -ConcurrentTaskCount 10 -Force
    }
}
function ProcessingSDP {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$SelectedAsset,
        [Parameter(Mandatory = $true)]
        [array]$AssetCollection,
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        [Parameter(Mandatory = $true)]
        [string]$LCSToken,
        [string]$PackageDestination = "C:\temp\deployablepackages",
        [Parameter(Mandatory = $true)]
        [string]$StorageSAStoken
    )
    
    Begin{
        # Extract asset information from object properties
        $AssetId = $SelectedAsset.Id
        $AssetName = $SelectedAsset.Name
        
        # Convert asset properties to readable format
        $convertedAssetData = ConvertFrom-FSCPSFileAssetProperties -Asset $SelectedAsset
        $FSCVersion = $convertedAssetData.productVersion
        
        # Configure Azure Storage context
        $storageAccountName = 'ciellosarchive'
        $storageContainer = 'deployablepackages'
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $StorageSAStoken
        $header = GetUNHeader -token $LCSToken
        
        # Setup working directory
        if(-not(Test-Path $PackageDestination))
        {
            [System.IO.Directory]::CreateDirectory($PackageDestination)
        }
        Remove-Item -Path $PackageDestination/* -Recurse -Force
        
        # Display processing information
        OutputInfo "Processing Asset ID: $AssetId"
        OutputInfo "Processing Asset Name: $AssetName" 
        OutputInfo "Available Assets Total: $($AssetCollection.Count)"
        OutputInfo "Target Project: $ProjectId"
        OutputInfo "Destination Path: $PackageDestination"
        OutputInfo "FSC Product Version: $FSCVersion"
    }
    
    process {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $destinationFilePath = Join-Path $PackageDestination ($AssetName.Replace(":",".")+".zip")  

        # Retrieve download URL for the selected asset
        $downloadUri = "https://lcsapi.lcs.dynamics.com/box/fileasset/GetFileAsset/$($ProjectId)?assetId=$($AssetId)"
        $assetDownloadData = (Invoke-RestMethod -Method Get -Uri $downloadUri -Headers $header)

        OutputInfo "Processing FSC Version: $FSCVersion"

        if(-not [string]::IsNullOrEmpty($FSCVersion))
        {
            # Initialize version tracking collection
            $versionList = New-Object System.Collections.ArrayList
            $versionConfigPath = "Actions\Helpers\versions.default.json"
            $defaultVersionData = (Get-Content $versionConfigPath) | ConvertFrom-Json
            $defaultVersionData | ForEach-Object{$versionList.Add($_)}
            
            # Locate existing version or create new entry
            $currentVersion = $versionList.Where({$_.version -eq $FSCVersion})
            if(-not $currentVersion)
            {
                $newVersionRecord = (@{version=$FSCVersion;data=@{PlatformVersionGA='';
                                                        AppVersionGA='';
                                                        PlatformUpdate='';
                                                        PlatformVersionLatest='';
                                                        AppVersionLatest='';
                                                        FSCServiseUpdatePackageId=''; 
                                                        FSCPreviewVersionPackageId=''; 
                                                        FSCFinalQualityUpdatePackageId=''; 
                                                        EcommerceMicrosoftRepoBranch=''}} | ConvertTo-Json | ConvertFrom-Json)
                $versionList.Add($newVersionRecord)
                $currentVersion = $versionList.Where({$_.version -eq $FSCVersion})
            }
            
            # Ensure required package tracking properties exist
            $requiredFields = @("FSCServiseUpdatePackageId", "FSCPreviewVersionPackageId", "FSCLatestQualityUpdatePackageId")
            foreach($fieldName in $requiredFields)
            {
                if(-not $currentVersion.data.PSobject.Properties.Where({$_.name -eq $fieldName}))
                {
                    $currentVersion.data | Add-Member -MemberType NoteProperty -name $fieldName -value ""
                }
            }
            
            # Determine if package should be downloaded based on type and version comparison
            $shouldDownload = $false
            
            # Classify package type and update tracking data
            switch ($AssetName) {
                {$_.ToLower().StartsWith("Service Update".ToLower()) -or $_.ToLower().StartsWith("First Release Service Update".ToLower())} 
                {  
                    # For Service Updates, compare platformBuild versions
                    if (-not [string]::IsNullOrEmpty($currentVersion.data.FSCServiseUpdatePackageId)) {
                        # Find existing Service Update package in asset collection
                        $existingServiceUpdateAsset = $AssetCollection | Where-Object { $_.Id -eq $currentVersion.data.FSCServiseUpdatePackageId }
                        
                        if ($existingServiceUpdateAsset) {
                            # Get platformBuild of existing Service Update
                            $existingServiceUpdateProperties = ConvertFrom-FSCPSFileAssetProperties -Asset $existingServiceUpdateAsset
                            $existingPlatformBuild = $existingServiceUpdateProperties.platformBuild
                            
                            # Get platformBuild of current asset being processed
                            $currentPlatformBuild = $convertedAssetData.platformBuild
                            
                            # Compare platform builds (assuming format like "7.0.7690.33")
                            if (-not [string]::IsNullOrEmpty($currentPlatformBuild) -and -not [string]::IsNullOrEmpty($existingPlatformBuild)) {
                                try {
                                    $currentVersion = [System.Version]::Parse($currentPlatformBuild)
                                    $existingVersion = [System.Version]::Parse($existingPlatformBuild)
                                    
                                    if ($currentVersion -gt $existingVersion) {
                                        $shouldDownload = $true
                                        OutputInfo "Current platformBuild ($currentPlatformBuild) is newer than existing ($existingPlatformBuild). Download required."
                                    } else {
                                        OutputInfo "Current platformBuild ($currentPlatformBuild) is not newer than existing ($existingPlatformBuild). Skipping download."
                                    }
                                } catch {
                                    OutputInfo "Error comparing platform builds. Defaulting to download."
                                    $shouldDownload = $true
                                }
                            } else {
                                OutputInfo "Platform build information missing. Defaulting to download."
                                $shouldDownload = $true
                            }
                        } else {
                            OutputInfo "No existing Service Update found. Download required."
                            $shouldDownload = $true
                        }
                    } else {
                        OutputInfo "No existing Service Update package ID. Download required."
                        $shouldDownload = $true
                    }
                    
                    # Update tracking data if downloading
                    if ($shouldDownload) {
                        $currentVersion.data.FSCServiseUpdatePackageId=$AssetId;
                        $currentVersion.data.FSCLatestQualityUpdatePackageId=$AssetId;
                    }
                    break;
                }
                {$_.ToLower().StartsWith("Preview Version".ToLower())} 
                {  
                    $shouldDownload = $true
                    $currentVersion.data.FSCPreviewVersionPackageId=$AssetId;
                    $currentVersion.data.FSCLatestQualityUpdatePackageId=$AssetId;
                    break;
                }
                {$_.ToLower().StartsWith("Proactive Quality Update".ToLower())} 
                {  
                    $shouldDownload = $true
                    $currentVersion.data.FSCLatestQualityUpdatePackageId=$AssetId;
                    break;
                }
                {$_.ToLower().StartsWith("Final Quality Update".ToLower())} 
                {  
                    $shouldDownload = $true
                    $currentVersion.data.FSCLatestQualityUpdatePackageId=$AssetId;
                    $currentVersion.data.FSCFinalQualityUpdatePackageId=$AssetId;
                    break;
                }
                Default {
                    $shouldDownload = $true
                }
            }
            
            # Update platform information from asset properties and save configuration
            $platformUpdate = $convertedAssetData.platformVersion -replace '^Update', ''
            $currentVersion.data.PlatformUpdate = $platformUpdate
            Set-Content -Path $versionConfigPath ($versionList | Sort-Object{$_.version} | ConvertTo-Json)
            
            if($shouldDownload)
            {
                # Verify AzCopy availability
                $azCopyExecutable = "c:\temp\azcopy.exe"
                $azCopyReady = Test-Path $azCopyExecutable
                
                # Install AzCopy if not present
                If (-not $azCopyReady)
                {
                    Write-Output "AzCopy utility not detected. Downloading..."
                    Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile c:\temp\AzCopy.zip -UseBasicParsing
                    Write-Output "Extracting AzCopy archive..."
                    Expand-Archive c:\temp\AzCopy.zip c:\temp\AzCopy -Force
                    Get-ChildItem c:\temp\AzCopy/*/azcopy.exe | Copy-Item -Destination $azCopyExecutable
                }
                
                # Download package if not already present locally
                if(-not (Test-Path $destinationFilePath))
                {
                    Write-Output "Retrieving package from LCS platform..."
                    & $azCopyExecutable copy $assetDownloadData.FileLocation "$destinationFilePath" --output-level quiet
                }
                
                # Upload to Azure Storage (replace existing if present)
                Write-Output "Transferring package to Azure Storage: $destinationFilePath"
                Write-Output "Uploading to container '$storageContainer' with blob name '$AssetName' (will replace if exists)"
                Set-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob "$AssetName" -File $destinationFilePath -StandardBlobTier Hot -ConcurrentTaskCount 10 -Force
                Write-Output "Package successfully uploaded to Azure Storage"
            }
            
            # Clean up local file after processing
            if(Test-Path $destinationFilePath)
            {
                Remove-Item $destinationFilePath -Force
            }
        }
    }
}

function Remove-D365LcsAssetFile {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    [OutputType()]
    param (
        [int] $ProjectId = $Script:LcsApiProjectId,

        [Parameter(Mandatory = $true)]
        [string] $AssetId = "",
        
        [Alias('Token')]
        [string] $BearerToken = $Script:LcsApiBearerToken,

        [string] $LcsApiUri = $Script:LcsApiLcsApiUri,

        [Timespan] $RetryTimeout = "00:00:00",

        [switch] $EnableException
    )


    if (-not ($BearerToken.StartsWith("Bearer "))) {
        $BearerToken = "Bearer $BearerToken"
    }

    Remove-LcsAssetFile -BearerToken $BearerToken -ProjectId $ProjectId -LcsApiUri $LcsApiUri -RetryTimeout $RetryTimeout -AssetId $AssetId

    if (Test-PSFFunctionInterrupt) { return }

}
function Remove-LcsAssetFile {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int] $ProjectId,

        [Parameter(Mandatory = $true)]
        [string] $AssetId,

        [Alias('Token')]
        [string] $BearerToken,
        
        [Parameter(Mandatory = $true)]
        [string] $LcsApiUri,

        [Timespan] $RetryTimeout = "00:00:00",

        [switch] $EnableException
    )
    begin {
        
        $headers = @{
            "Authorization" = "$BearerToken"
        }

        $parms = @{}
        $parms.Method = "POST"
        $parms.Uri = "$LcsApiUri/box/fileasset/DeleteFileAsset/$($ProjectId)?assetId=$($AssetId)"
        $parms.Headers = $headers
        $parms.RetryTimeout = $RetryTimeout
    }
    process {
        try {
            Write-PSFMessage -Level Verbose -Message "Invoke LCS request."
            Invoke-FSCRequestHandler @parms
            Write-PSFMessage -Level Verbose -Message "Asset was deleted successfully."
        }
        catch [System.Net.WebException] {
            Write-PSFMessage -Level Host -Message "Error status code <c='em'>$($_.exception.response.statuscode)</c> in request for delete asset from the asset library of LCS. <c='em'>$($_.exception.response.StatusDescription)</c>." -Exception $PSItem.Exception
            Stop-PSFFunction -Message "Stopping because of errors" -StepsUpward 1
            return
        }
        catch {
            Write-PSFMessage -Level Host -Message "Something went wrong while working against the LCS API." -Exception $PSItem.Exception
            Stop-PSFFunction -Message "Stopping because of errors" -StepsUpward 1
            return
        }
    }
}
function ConvertFrom-FSCPSFileAssetProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]$Asset
    )
    
    begin {
        Write-PSFMessage -Level Verbose -Message "Starting conversion of FileAssetProperties"
    }
    
    process {
        $result = [PSCustomObject]@{}
        
        if ($Asset.FileAssetProperties) {
            $fileAssetProperties = $Asset.FileAssetProperties
            
            foreach ($property in $fileAssetProperties) {
                if (![string]::IsNullOrWhiteSpace($property.FileTypePropertyName)) {
                    $propertyName = $property.FileTypePropertyName
                    
                    $cleanName = $propertyName -replace '[^\w\s]', '' -replace '\s+', ' '
                    $words = $cleanName.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
                    
                    if ($words.Count -gt 0) {
                        $camelCaseName = $words[0].ToLower()
                        for ($i = 1; $i -lt $words.Count; $i++) {
                            $camelCaseName += $words[$i].Substring(0,1).ToUpper() + $words[$i].Substring(1).ToLower()
                        }
                        
                        $value = if (![string]::IsNullOrWhiteSpace($property.PropertyValueDisplay)) {
                            $property.PropertyValueDisplay
                        } elseif (![string]::IsNullOrWhiteSpace($property.PropertyValue)) {
                            $property.PropertyValue
                        } else {
                            $null
                        }
                        
                        Add-Member -InputObject $result -MemberType NoteProperty -Name $camelCaseName -Value $value -Force
                        
                        Write-PSFMessage -Level Verbose -Message "Added property: $camelCaseName = $value"
                    }
                }
            }
        } else {
            Write-PSFMessage -Level Warning -Message "Asset object does not contain FileAssetProperties"
        }
        
        Write-PSFMessage -Level Verbose -Message "Conversion completed"
        return $result
    }
}

function Get-FSCVersionFromPackageName
{
    param (
        [string]$PackageName
    )
    begin{
        $fscVersionRegex = [regex] "(([0-9]*[0-9])\.){2}(?:[0-9]*[0-9]?)\b"
        $platUpdateRegex = [regex] "(?:[0-9]*[0-9])"
    }
    process{
        $fscVersion = $fscVersionRegex.Match($PackageName).Value
        if(-not $fscVersion)
        {
            if($PackageName.Contains("Plat Update"))
            {
                $platVersion = $platUpdateRegex.Match($PackageName).Value
                $fscVersion = "10.0." + ($platVersion - 24)
            }
        }
        return $fscVersion
    }
}
function Get-NewestNugetVersion
{
    param (
        [string]$Version1,
        [string]$Version2
    )
    process{
        if ([string]::IsNullOrWhiteSpace($Version1)) { return $Version2 }
        if ([string]::IsNullOrWhiteSpace($Version2)) { return $Version1 }
        
        # Convert to System.Version for proper comparison
        try {
            $v1 = [Version]$Version1
            $v2 = [Version]$Version2
            
            if ($v1 -gt $v2) {
                return $Version1
            } else {
                return $Version2
            }
        }
        catch {
            # Fallback to string comparison if version parsing fails
            if ($Version1 -gt $Version2) {
                return $Version1
            } else {
                return $Version2
            }
        }
    }
}

# Converts an FSC version (e.g. 10.0.30) to a Platform Update number (e.g. 54) using rule PU = minor + 24
# Examples:
#   Convert-VersionToPlatformUpdate -Version 10.0.30          -> 54
#   Convert-VersionToPlatformUpdate -Version 10.0.30 -AsLabel -> "Plat Update 54"
#   Convert-VersionToPlatformUpdate -Version 10.0.30 -AsPU    -> "PU54"
function Convert-VersionToPlatformUpdate {
    [CmdletBinding()] 
    param(
        [Parameter(Mandatory = $true)]
        [string] $Version,

        # Return formatted like "Plat Update <n>"
        [switch] $AsLabel,

        # Return formatted like "PU<n>"
        [switch] $AsPU
    )
    process {
        if ([string]::IsNullOrWhiteSpace($Version)) { return $null }

        # Expecting at least 3 segments (Major.Minor.Build)
        $parts = $Version.Split('.')
        if ($parts.Count -lt 3) { return $null }

        $third = $parts[2]
        if (-not ($third -match '^[0-9]+$')) { return $null }

        $pu = ([int]$third) + 24

        if ($AsLabel) { return "Plat Update $pu" }
        if ($AsPU)    { return "PU$pu" }
        return $pu
    }
}
