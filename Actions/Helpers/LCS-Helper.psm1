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
    $url = "https://lcsapi.lcs.dynamics.com/box/fileasset/GetSharedAssets?fileType="+$($FileType.value__)
    $assetsList = Invoke-RestMethod -Method Get -Uri $url  -Headers $header
    return $assetsList
}    

function ProcessingNuGet {
    param (
        [string]$AssetId,
        [string]$AssetName,
        [string]$ProjectId,
        [string]$LCSToken,
        [string]$StorageToken,
        [string]$PackageDestination = "C:\temp\packages",
        [string]$StorageSAStoken
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
        $upload = $true

        OutputInfo "Download?: $download"
        OutputInfo "Upload?: $upload"

        $blob = Get-AzStorageBlob -Context $ctx -Container $storageContainer -Blob $AssetName -ConcurrentTaskCount 10 -ErrorAction SilentlyContinue
        $blob
        if(!$blob)
        {
            if($download)
            {               
                # Test if AzCopy.exe exists in current folder
                $WantFile = "c:\temp\azcopy.exe"
                $AzCopyExists = Test-Path $WantFile
                Write-Output ("AzCopy exists: {0}" -f $AzCopyExists)

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
                else
                {
                    Write-Output "AzCopy found, skipping download.`n"
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
            $upload = $false
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
                $curVer = (@{version=$FSCVersion;data=@{PlatformVersion='';AppVersion='';retailSDKVersion=''; retailSDKURL=''; ecommerceMicrosoftRepoBranch=''}} | ConvertTo-Json | ConvertFrom-Json)
                $versions.Add($curVer)
                $curVer = $versions.Where({$_.version -eq $FSCVersion})
            }
            switch ($AssetName) {
                {$AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.Platform.CompilerPackage.".ToLower()) -or
                $AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp.".ToLower())} 
                {  
                    $curVer.data.PlatformVersion=$version;                 
                    break;
                }
                {$AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.Application.DevALM.BuildXpp.".ToLower()) -or
                $AssetName.ToLower().StartsWith("Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp.")} 
                {  
                    $curVer.data.AppVersion=$version;
                    break;
                }
                    Default {}
            }
            Set-Content -Path $versionsDefaultFile ($versions | Sort-Object{$_.version} | ConvertTo-Json)
        }   
        Set-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob "$AssetName" -File "$destinationNugetFilePath" -ConcurrentTaskCount 10 -Force
    }
}
function ProcessingSDP {
    param (
        [string]$AssetId,
        [string]$AssetName,
        [string]$ProjectId,
        [string]$LCSToken,
        [string]$PackageDestination = "C:\temp\deployablepackages",
        [string]$StorageSAStoken
    )
    Begin{
        $storageAccountName = 'ciellosarchive'
        $storageContainer = 'deployablepackages'
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
        OutputInfo "PackageDestination: $PackageDestination"
    }
    process {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $destinationFilePath = Join-Path $PackageDestination ($AssetName+".zip")  

        #get download link asset
        $uri = "https://lcsapi.lcs.dynamics.com/box/fileasset/GetFileAsset/$($ProjectId)?assetId=$($AssetId)"
        $assetJson = (Invoke-RestMethod -Method Get -Uri $uri -Headers $header)

        OutputInfo "FSCVersion:  $FSCVersion"

        if($FSCVersion -ne "")
        {
            $versions = New-Object System.Collections.ArrayList
            $versionsDefaultFile = "Actions\Helpers\versions.default.json"
            $versionsDefault = (Get-Content $versionsDefaultFile) | ConvertFrom-Json
            $versionsDefault | ForEach-Object{$versions.Add($_)}
            $curVer = $versions.Where({$_.version -eq $FSCVersion})
            if(!$curVer)
            {
                $curVer = (@{version=$FSCVersion;data=@{PlatformVersion='';
                                                        AppVersion='';
                                                        retailSDKVersion=''; 
                                                        retailSDKURL=''; 
                                                        fscServiseUpdatePackageId=''; 
                                                        fscPreviewVersionPackageId=''; 
                                                        fscFinalQualityUpdatePackageId=''; 
                                                        ecommerceMicrosoftRepoBranch=''}} | ConvertTo-Json | ConvertFrom-Json)
                $versions.Add($curVer)
                $curVer = $versions.Where({$_.version -eq $FSCVersion})
            }
            if(-not $curVer.data.PSobject.Properties.Where({$_.name -eq "fscServiseUpdatePackageId"}))
            {
                $curVer.data | Add-Member -MemberType NoteProperty -name "fscServiseUpdatePackageId" -value ""
            }
            if(-not $curVer.data.PSobject.Properties.Where({$_.name -eq "fscPreviewVersionPackageId"}))
            {
                $curVer.data | Add-Member -MemberType NoteProperty -name "fscPreviewVersionPackageId" -value ""
            }
            if(-not $curVer.data.PSobject.Properties.Where({$_.name -eq "fscFinalQualityUpdatePackageId"}))
            {
                $curVer.data | Add-Member -MemberType NoteProperty -name "fscFinalQualityUpdatePackageId" -value ""
            }
            $blob = Get-AzStorageBlob -Context $ctx -Container $storageContainer -Blob $AssetName -ConcurrentTaskCount 10 -ErrorAction SilentlyContinue
            $download = $false
            if(!$blob)
            {
                $download = $true
            }
            switch ($AssetName) {
                {$AssetName.ToLower().StartsWith("Service Update".ToLower())} 
                {  
                    $curVer.data.fscServiseUpdatePackageId=$AssetId;                 
                    break;
                }
                {$AssetName.ToLower().StartsWith("Preview Version".ToLower())} 
                {  
                    $curVer.data.fscPreviewVersionPackageId=$AssetId;
                    break;
                }
                {$AssetName.ToLower().StartsWith("Final Quality Update".ToLower())} 
                {  
                    $curVer.data.fscFinalQualityUpdatePackageId=$AssetId;
                    break;
                }
                    Default {}
            }
            Set-Content -Path $versionsDefaultFile ($versions | Sort-Object{$_.version} | ConvertTo-Json)
            if($download)
            {
                # Test if AzCopy.exe exists in current folder
                $WantFile = "c:\temp\azcopy.exe"
                $AzCopyExists = Test-Path $WantFile
                Write-Output ("AzCopy exists: {0}" -f $AzCopyExists)

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
                else
                {
                    Write-Output "AzCopy found, skipping download.`n"
                }
                if(-not (Test-Path $destinationFilePath))
                {
                    Write-Output "Downloading package from the LCS..."
                    & $WantFile copy $assetJson.FileLocation "$destinationFilePath" --output-level quiet
                }
                Write-Output "Uploading package to the Azure..."
                Set-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob "$AssetName" -File "$destinationFilePath" -ConcurrentTaskCount 10 -Force
                $archDestinationPath = $destinationFilePath.Replace(".zip", "")
                Expand-7zipArchive $destinationFilePath -DestinationPath $archDestinationPath
                $retailSDKPath = Join-Path $archDestinationPath "RetailSDK\Code"
                $retailsdkVersion = Get-Content $retailSDKPath\"Microsoft-version.txt"
                $retailSDKDestinationPath = Join-Path C:\Temp ("RetailSDK."+$retailsdkVersion+".7z")
                Compress-7zipArchive -Path $retailSDKPath\* -DestinationPath $retailSDKDestinationPath
                ProcessingRSDK -PackageName ("RetailSDK."+$retailsdkVersion+".7z") -PackageDestination $retailSDKDestinationPath -SDKVersion $retailsdkVersion -StorageSAStoken $StorageSAStoken
            }
            if(Test-Path $destinationFilePath)
            {
                Remove-Item $destinationFilePath -Force
            }
            
        }
    }
}
function ProcessingRSDK {
    param (
        [string]$PackageName,
        [string]$SDKVersion,
        [string]$PackageDestination,
        [string]$StorageSAStoken
    )
    Begin{
        $storageAccountName = 'ciellosarchive'
        $storageContainer = 'retailsdk'
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $StorageSAStoken
        $header = GetUNHeader -token $LCSToken
        OutputInfo "PackageName: $PackageName"
        OutputInfo "PackageDestination: $PackageDestination"
    }
    process {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        OutputInfo "SDKVersion:  $SDKVersion"
        OutputInfo "PackageName:  $PackageName"

        if($SDKVersion -ne "")
        {
            $versions = New-Object System.Collections.ArrayList
            $versionsDefaultFile = "Actions\Helpers\versions.default.json"
            $versionsDefault = (Get-Content $versionsDefaultFile) | ConvertFrom-Json
            $versionsDefault | ForEach-Object{$versions.Add($_)}
            $curVer = $versions.Where({$_.version -eq $FSCVersion})
            
            $blob = Get-AzStorageBlob -Context $ctx -Container $storageContainer -Blob $PackageName -ConcurrentTaskCount 10 -ErrorAction SilentlyContinue
            $upload = $false
            if(!$blob)
            {
                $upload = $true
            }
            $curVer.data.retailSDKVersion=$SDKVersion; 
            Set-Content -Path $versionsDefaultFile ($versions | Sort-Object{$_.version} | ConvertTo-Json)
            if($upload)
            {
                Write-Output "Uploading package to the Azure..."
                Set-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob "$PackageName" -File "$PackageDestination" -ConcurrentTaskCount 10 -Force
            }
            
            Remove-Item $PackageDestination -Force
        }
    }
}