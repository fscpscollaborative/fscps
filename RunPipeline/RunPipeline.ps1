Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "DynamicsVersion", Mandatory = $true)]
    [string] $DynamicsVersion,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"AppBuild":"", "AppRevision":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePassword":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePassword":"","KeyVaultClientId":"","StorageContext":"","ApplicationInsightsConnectionString":""}'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FnSCM-Go-Helper.ps1" -Resolve)


    $VersionsFile = Join-Path $ENV:GITHUB_WORKSPACE '.FnSCM-Go\versions.json'

    $versions = (Get-Content $VersionsFile) | ConvertFrom-Json

    Foreach($version in $versions)
    {
        if($version.version -eq $DynamicsVersion)
        {
            $PlatformVersion = $version.data.PlatformVersion
            $ApplicationVersion = $version.data.AppVersion
        }
    }


    $tools_package =  'Microsoft.Dynamics.AX.Platform.CompilerPackage.' + $PlatformVersion
    $plat_package =  'Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp.' + $PlatformVersion
    $app_package =  'Microsoft.Dynamics.AX.Application.DevALM.BuildXpp.' + $ApplicationVersion
    $appsuite_package =  'Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp.' + $ApplicationVersion


    $runAlPipelineParams = @{}
    $project = "" 
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $ENV:GITHUB_WORKSPACE
    }
    $workflowName = $env:GITHUB_WORKFLOW

    #Use settings and secrets
    Write-Host "======================================== Use settings and secrets"

    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'nugetFeedPasswordSecretName','nugetFeedUserSecretName','lcsUserNameSecretName','lcsPasswordSecretName' | ForEach-Object {
        $setValue = ""
        if($settings.ContainsKey($_))
        {
            $setValue = $settings."$_"
        }
        if ($secrets.ContainsKey($setValue)) {
            $value = $secrets."$setValue"
        }
        else {
            $value = "test"
        }
        Set-Variable -Name $_ -Value $value
    }

    
    $buildPath = Join-Path "C:\Temp" $settings.buildPath
    #Generate solution folder
    Write-Host "======================================== Generate solution folder"
    GenerateSolution -ModelName $settings.models -NugetFeedName $settings.nugetFeedName -NugetSourcePath $settings.nugetSourcePath -DynamicsVersion $DynamicsVersion

    Write-Host "======================================== Cleanup Build folder"
    #Cleanup Build folder
    Remove-Item $buildPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "======================================== Copy branch files"
    #Copy branch files
    New-Item -ItemType Directory -Force -Path $buildPath; Copy-Item $ENV:GITHUB_WORKSPACE\* -Destination $buildPath -Recurse -Force

    Write-Host "======================================== Copy solution folder"
    #Copy solution folder
    Copy-Item NewBuild -Destination $buildPath -Recurse -Force

    Write-Host "======================================== Cleanup NuGet"
    #Cleanup NuGet
    nuget sources remove -Name $settings.nugetFeedName -Source $settings.nugetSourcePath

    Write-Host "======================================== Nuget add source"
    #Nuget add source
    nuget sources Add -Name $settings.nugetFeedName -Source $settings.nugetSourcePath -username $nugetFeedUserSecretName -password $nugetFeedPasswordSecretName
   
    $packagesFilePath = Join-Path $buildPath NewBuild\packages.config
    
    Write-Host "======================================== Nuget install packages"

    if(Test-Path $packagesFilePath)
    {
        Write-Host "Found packages.config file at path: " $packagesFilePath
    }
    else
    {
        Write-Host "Not Found packages.config file at path:" $packagesFilePath
    }
    cd $buildPath
    cd NewBuild
    #Nuget install packages
    nuget restore -PackagesDirectory ..\NuGets

    
    #Copy dll`s to build folder
    Write-Host "======================================== Copy dll`s to build folder"
    Write-Host "Source path: " (Join-Path $($buildPath) $($settings.metadataPath))
    Write-Host "Destination path: " (Join-Path $($buildPath) bin)


    Copy-Filtered -Source (Join-Path $($buildPath) $($settings.metadataPath)) -Target (Join-Path $($buildPath) bin) -Filter *.dll

    #Build solution
    Write-Host "======================================== Build solution"
    cd $buildPath

    $msReferenceFolder = "$($buildPath)\$($settings.nugetPackagesPath)\$($app_package)\ref\net40;$($buildPath)\$($settings.nugetPackagesPath)\$plat_package\ref\net40;$($buildPath)\$($settings.nugetPackagesPath)\$appsuite_package\ref\net40;$($buildPath)\$($settings.metadataPath);$($buildPath)\bin"
    $msBuildTasksDirectory = "$($buildPath)\$($settings.nugetPackagesPath)\$tools_package\DevAlm".Trim()
    $msMetadataDirectory = "$($buildPath)\$($settings.metadataPath)".Trim()
    $msFrameworkDirectory = "$($buildPath)\$($settings.nugetPackagesPath)\$tools_package".Trim()
    $msReferencePath = "$($buildPath)\$($settings.nugetPackagesPath)\$tools_package".Trim()
    $msOutputDirectory = "$($buildPath)\bin".Trim()

    $buidPropsFile = Join-Path $buildPath NewBuild\Build\build.props
    $tempFile = (Get-Content $buidPropsFile).Replace('ReferenceFolders', $msReferenceFolder)
    Set-Content $buidPropsFile $tempFile

    msbuild NewBuild\Build\Build.sln  `
         /p:BuildTasksDirectory=$msBuildTasksDirectory `
         /p:MetadataDirectory=$msMetadataDirectory `
         /p:FrameworkDirectory=$msFrameworkDirectory `
         /p:ReferencePath=$msReferencePath `
         /p:OutputDirectory=$msOutputDirectory 



    #GeneratePackages
    if($settings.generatePackages)
    {
        Write-Host "======================================== Generate packages"

        $packageName = (($settings.packageNamePattern).Replace("BRANCHNAME", $settings.currentBranch).Replace("FNSCMVERSION", $DynamicsVersion).Replace("PACKAGENAME", $settings.packageName).Replace("DATE", (Get-Date -Format "yyyyMMdd").ToString()).Replace("RUNNUMBER", $ENV:GITHUB_RUN_NUMBER) + ".zip" )

        $xppToolsPath = $msFrameworkDirectory
        $xppBinariesPath = (Join-Path $($buildPath) bin)
        $xppBinariesSearch = Join-Path (Join-Path $($buildPath) bin) $settings.modelsIntoPackagePattern
        $deployablePackagePath = Join-Path (Join-Path $buildPath $settings.deployablePackagePath) ($packageName)


        if ($xppBinariesSearch.Contains(";"))
        {
            [string[]]$xppBinariesSearch = $xppBinariesSearch -split ";"
        }

        $potentialPackages = Find-Match -DefaultRoot $xppBinariesPath -Pattern $xppBinariesSearch | Where-Object { (Test-Path -LiteralPath $_ -PathType Container) }
        $packages = @()
        if ($potentialPackages.Length -gt 0)
        {
            Write-Host "Found $($potentialPackages.Length) potential folders to include:"
            foreach($package in $potentialPackages)
            {
                $packageBinPath = Join-Path -Path $package -ChildPath "bin"
                # If there is a bin folder and it contains *.MD files, assume it's a valid X++ binary
                if ((Test-Path -Path $packageBinPath) -and ((Get-ChildItem -Path $packageBinPath -Filter *.md).Count -gt 0))
                {
                    Write-Host "  - $package"
                    $packages += $package
                }
                else
                {
                    Write-Warning "  - $package (not an X++ binary folder, skipped)"
                }
            }

            $artifactDirectory = [System.IO.Path]::GetDirectoryName($deployablePackagePath)
            if (!(Test-Path -Path $artifactDirectory))
            {
                # The reason to use System.IO.Directory.CreateDirectory is it creates any directories missing in the whole path
                # whereas New-Item would only create the top level directory
                [System.IO.Directory]::CreateDirectory($artifactDirectory)
            }

            Import-Module (Join-Path -Path $xppToolsPath -ChildPath "CreatePackage.psm1")
            $outputDir = Join-Path -Path $artifactDirectory -ChildPath ((New-Guid).ToString())
            $tempCombinedPackage = Join-Path -Path $artifactDirectory -ChildPath "$((New-Guid).ToString()).zip"
            try
            {
                New-Item -Path $outputDir -ItemType Directory > $null

                Write-Host "Creating binary packages"
                foreach($packagePath in $packages)
                {
                    $packageName = (Get-Item $packagePath).Name
                    Write-Host "  - '$packageName'"

                    $version = ""
                    $packageDll = Join-Path -Path $packagePath -ChildPath "bin\Dynamics.AX.$packageName.dll"
                    if (Test-Path $packageDll)
                    {
                        $version = (Get-Item $packageDll).VersionInfo.FileVersion
                    }

                    if (!$version)
                    {
                        $version = "1.0.0.0"
                    }

                    New-XppRuntimePackage -packageName $packageName -packageDrop $packagePath -outputDir $outputDir -metadataDir $xppBinariesPath -packageVersion $version -binDir $xppToolsPath -enforceVersionCheck $True
                }

                Write-Host "Creating deployable package"
                Add-Type -Path "$xppToolsPath\Microsoft.Dynamics.AXCreateDeployablePackageBase.dll"
                Write-Host "  - Creating combined metadata package"
                [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::CreateMetadataPackage($outputDir, $tempCombinedPackage)
                Write-Host "  - Creating merged deployable package"
                [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::MergePackage("$xppToolsPath\BaseMetadataDeployablePackage.zip", $tempCombinedPackage, $deployablePackagePath, $true, [String]::Empty)

                Write-Host "Deployable package '$deployablePackagePath' successfully created."



                $pname = ($deployablePackagePath.SubString("$deployablePackagePath".LastIndexOf('\') + 1)).Replace(".zip","")

                Write-Host "::set-output name=PACKAGE_NAME::$pname"
                Write-Host "set-output name=PACKAGE_NAME::$pname"
                Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_NAME=$pname"

                Write-Host "::set-output name=PACKAGE_PATH::$deployablePackagePath"
                Write-Host "set-output name=PACKAGE_PATH::$deployablePackagePath"
                Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_PATH=$deployablePackagePath"

                #Upload to LCS
                if($settings.uploadPackageToLCS)
                {
                    Write-Host "LCSUsername: " $lcsUserNameSecretName
                    Write-Host "LCSPassword: " $lcsPasswordSecretName
                    Write-Host "LCSClientId: " $settings.lcsClientId
                    Write-Host "LCSProject: " $settings.lcsProjectId

                    Get-D365LcsApiToken -ClientId $settings.lcsClientId -Username $lcsUserNameSecretName -Password $lcsPasswordSecretName -LcsApiUri "https://lcsapi.lcs.dynamics.com" -Verbose | Set-D365LcsApiConfig -ProjectId $settings.lcsProjectId
                    Invoke-D365LcsUpload -FilePath $deployablePackagePath -FileType "SoftwareDeployablePackage" -FileName $pname -Verbose
                }
            }
            finally
            {
                if (Test-Path -Path $outputDir)
                {
                    Remove-Item -Path $outputDir -Recurse -Force
                }
                if (Test-Path -Path $tempCombinedPackage)
                {
                    Remove-Item -Path $tempCombinedPackage -Force
                }
            }
        }
        else
        {
            throw "No X++ binary package(s) found"
        }

    }

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
