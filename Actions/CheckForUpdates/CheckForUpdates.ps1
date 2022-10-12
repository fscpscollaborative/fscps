Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Set this input to Y in order to update FSC-PS System Files if needed", Mandatory = $false)]
    [bool] $update,
    [Parameter(HelpMessage = "URL of the template repository (default is the template repository used to create the repository)", Mandatory = $false)]
    [string] $templateUrl = "",
    [Parameter(HelpMessage = "Branch in template repository to use for the update (default is the default branch)", Mandatory = $false)]
    [string] $templateBranch = "",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '',
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit    ,
    [Parameter(HelpMessage = "The environment type FSCM/Commerce", Mandatory = $false)]
    [string] $type = "FSCM"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)
    $workflowName = $env:GITHUB_WORKFLOW
    $baseFolder = $ENV:GITHUB_WORKSPACE
    #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    OutputInfo "======================================== Use settings and secrets"

    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable | ConvertTo-OrderedDictionary

    $EnvironmentsFile = Join-Path $baseFolder '.FSC-PS\environments.json'
    $environments = @((Get-Content $EnvironmentsFile) | ConvertFrom-Json | ForEach-Object {$_.Name})

    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable

    $settingsHash = $settings #| ConvertTo-HashTable
    $settings.secretsList | ForEach-Object {
        $setValue = ""
        if($settingsHash.Contains($_))
        {
            $setValue = $settingsHash."$_"
        }
        if ($secrets.ContainsKey($setValue)) 
        {
            OutputInfo "Found $($_) variable in the settings file with value: ($setValue)"
            $value = $secrets."$setValue"
        }
        else {
            $value = ""
        }
        Set-Variable -Name $_ -Value $value
    }
    
    $DynamicsVersion = $settings.buildVersion

    $versions = Get-Versions

    if($settings.sourceBranch -eq "")
    {
        $settings.sourceBranch = $settings.currentBranch
    }

    
    #SourceBranchToPascakCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    $buildPath = Join-Path "C:\Temp" $settings.buildPath
    Write-Output "::endgroup::"


    if(!$templateUrl)
    {
        $templateUrl = $settings.templateUrl
    }
    # Support old calling convention
    if (-not $templateUrl.Contains('@')) {
        if ($templateBranch) {
            $templateUrl += "@$templateBranch"
        }
        else {
            $templateUrl += "@main"
        }
    }

    if ($templateUrl -notlike "https://*") {
        $templateUrl = "https://github.com/$templateUrl"
    }

    $RepoSettingsFile = ".github\FSC-PS-Settings.json"
    if (Test-Path $RepoSettingsFile) {
        $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
    }
    else {
        $repoSettings = @{}
    }

    $templateBranch = $templateUrl.Split('@')[1]
    $templateUrl = $templateUrl.Split('@')[0]


    if(!$templateBranch)
    {
        $templateBranch = $settings.templateBranch
    }

    $updateSettings = $true
    if ($repoSettings.ContainsKey("templateUrl")) {
        if ($templateUrl.StartsWith('@')) {
            $templateUrl = "$($repoSettings.templateUrl.Split('@')[0])$templateUrl"
        }
        if (($repoSettings.templateUrl -eq $templateUrl) -and ($repoSettings.templateBranch -eq $templateBranch)) {
            $updateSettings = $false
        }
    }

    $headers = @{
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }

    if ($templateUrl -ne "") {
        try {
            $templateUrl = $templateUrl -replace "https://www.github.com/","$ENV:GITHUB_API_URL/repos/" -replace "https://github.com/","$ENV:GITHUB_API_URL/repos/"
            OutputInfo "Api url $templateUrl"
            $templateInfo = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $templateUrl | ConvertFrom-Json
        }
        catch {
            throw "Could not retrieve the template repository. Error: $($_.Exception.Message)"
        }
    }
    else {
        OutputInfo "Api url $($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)"
        $repoInfo = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)" | ConvertFrom-Json
        if (!($repoInfo.PSObject.Properties.Name -eq "template_repository")) {
            OutputWarning -message "This repository wasn't built on a template repository, or the template repository is deleted. You must specify a template repository in the FSC-PS settings file."
            exit
        }

        $templateInfo = $repoInfo.template_repository
    }

    $templateUrl = $templateInfo.html_url
    OutputInfo "Using template from $templateUrl@$templateBranch"

    $headers = @{             
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }
    $archiveUrl = $templateInfo.archive_url.Replace('{archive_format}','zipball').replace('{/ref}',"/$templateBranch")
    $tempName = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $archiveUrl -OutFile "$tempName.zip"
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"
    
    $checkfiles = @(
        @{ "dstPath" = ".github\workflows"; "srcPath" = ".github\workflows"; "pattern" = "*"; "type" = "workflow" },
        @{ "dstPath" = ".github"; "srcPath" = ".github"; "pattern" = "*.copy.md"; "type" = "releasenotes" }
    )
    if (Test-Path (Join-Path $baseFolder ".FSC-PS")) {
        $checkfiles += @(@{ "dstPath" = ".FSC-PS"; "srcPath" = ".FSC-PS"; "pattern" = "*.ps1"; "type" = "script" })
    }
    else {
        Get-ChildItem -Path $baseFolder -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".FSC-PS") -PathType Container } | ForEach-Object {
            $checkfiles += @(@{ "dstPath" = Join-Path $_.Name ".FSC-PS"; "srcPath" = ".FSC-PS"; "pattern" = "*.ps1"; "type" = "script" })
        }
    }
    $updateFiles = @()

    $checkfiles | ForEach-Object {
        $fileType = $_.type
        $srcPath = $_.srcPath
        $dstPath = $_.dstPath
        $dstFolder = Join-Path $baseFolder $dstPath
        $srcFolder = (Get-Item (Join-Path $tempName "*\$($srcPath)"))
        if($srcFolder)
        {
            Get-ChildItem -Path $srcFolder.FullName -Filter $_.pattern | ForEach-Object {
                $srcFile = $_.FullName
                $fileName = $_.Name
                $baseName = $_.BaseName
                $srcContent = (Get-Content -Path $srcFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
                $name = $fileType

                if ($fileType -eq "workflow") {
                    $srcContent.Split("`n") | Where-Object { $_ -like "name:*" } | Select-Object -First 1 | ForEach-Object {
                        if ($_ -match '^name:([^#]*)(#.*$|$)') { $name = "workflow '$($Matches[1].Trim())'" }
                    }
                }
            
                $workflowScheduleKey = "$($baseName)Schedule"
                if ($repoSettings.ContainsKey($workflowScheduleKey)) {
                    $srcPattern = "on:`r`n  workflow_dispatch:`r`n"
                    $replacePattern = "on:`r`n  schedule:`r`n  - cron: '$($repoSettings."$workflowScheduleKey")'`r`n  workflow_dispatch:`r`n"
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                }
            
                if ($fileName -ne "update_fsc_system_files.yml") {
                    if ($repoSettings.ContainsKey("runs-on")) {
                        $srcPattern = "Initialization:`r`n    runs-on: [ windows-latest ]`r`n"
                        $replacePattern = "Initialization:`r`n    runs-on: [ $($repoSettings."runs-on") ]`r`n"
                        $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                        #if (!($repoSettings.ContainsKey("gitHubRunner"))) {
                        #    $srcPattern = "runs-on: `${{ fromJson(needs.Initialization.outputs.githubRunner) }}`r`n"
                        #    $replacePattern = "runs-on: [ $($repoSettings."runs-on") ]`r`n"
                        #    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                        #}
                    }
                }
                
                if(($fileName -eq "import.yml") -and $type -eq "FSCM")
                {
                    if(Test-Path -Path (Join-Path $baseFolder "PackagesLocalDirectory")){ return }
                }

                if($fileName -eq "build.yml")
                {
                    $srcPattern = '        - "*"'
                    $replacePattern = '        - "*"'
                    $replacePattern += "`r`n"
                    Get-Versions | ForEach-Object { 
                        $ver = $_.version
                        $replacePattern += "        - "+'"'+$($ver)+'"'+"`r`n"

                    }
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                }
                
                if($fileName -eq "deploy.yml")
                {
                    $srcPattern = '        - "*"'
                    $replacePattern = '         - "*"'
                    $replacePattern += "`r`n"
                    $environments | ForEach-Object { 
                        $replacePattern += "         - "+'"'+$($_)+'"'+"`r`n"
                    }
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                    #schedule
                    $srcPattern = "on:`r`n  workflow_dispatch:`r`n"
                    $replacePattern = "on:`r`n  schedule:`r`n   - cron: '$($settings.deployScheduleCron)'`r`n  workflow_dispatch:`r`n"
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                }

                if($fileName -eq "ci.yml")
                {
                    $srcPattern = '       - main'
                    $replacePattern = ""
                    if($settings.ciBranches.Split(','))
                    {
                        $settings.ciBranches.Split(',') | ForEach-Object { 
                            $replacePattern += "       - "+'"'+$($_)+'"'+"`r`n"
                        }
                    }
                    else {
                        $replacePattern += "       - "+'"'+$($settings.ciBranches)+'"'+"`r`n"
                    }
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                }


                if($fileName -eq "update_model_version.yml")
                {
                    if($type -eq "Retail"){ return }
                    $srcPattern = '        - "*"'
                    $replacePattern = ""
                    $models = (Get-FSCModels -metadataPath $settings.metadataPath)
                    if($models.Split(','))
                    {
                        $models.Split(',') | ForEach-Object { 
                            $replacePattern += "         - "+'"'+$($_)+'"'+"`r`n"
                    }
                    else {
                        $replacePattern += "         - "+'"'+$($models)+'"'+"`r`n"
                    }

                    }
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                }

                
                $dstFile = Join-Path $dstFolder $fileName
                if (Test-Path -Path $dstFile -PathType Leaf) {
                    # file exists, compare
                    $dstContent = (Get-Content -Path $dstFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
                    if ($dstContent -ne $srcContent) {
                        OutputInfo "Updated $name ($(Join-Path $dstPath $filename)) available"
                        $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                    }
                }
                else {
                    # new file
                    OutputInfo "New $name ($(Join-Path $dstPath $filename)) available"
                    $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                }
            }
        }
    }
    $removeFiles = @()
    
    OutputInfo "Update files: $($updateFiles.Count -gt 0)"
    OutputInfo "Remove files $($removeFiles.Count -gt 0)"
    OutputInfo "Update Settings $($updateSettings)"    

    Write-Information "Update $update"
    if (-not $update) {
        if (($updateFiles) -or ($removeFiles)) {
            OutputWarning -message "There are updates for your FSC-PS system, run 'Update FSC-PS System Files' workflow to download the latest version of FSC-PS."
        }
        else {
            OutputWarning "Your repository runs on the latest version of FSC-PS System."
        }
    }
    else {
        if ($updateSettings -or ($updateFiles) -or ($removeFiles)) {
            try {
                # URL for git commands
                $tempRepo = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
                New-Item $tempRepo -ItemType Directory | Out-Null
                Set-Location $tempRepo
                $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
                $url = "$($serverUri.Scheme)://$($actor):$($repoTokenSecretName)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

                # Environment variables for hub commands
                $env:GITHUB_USER = $actor
                $env:GITHUB_TOKEN = $repoTokenSecretName
                $targetBranch = ("$env:GITHUB_REF").Replace("refs/heads/","")

                # Configure git username and email
                invoke-git config --global user.email "$actor@users.noreply.github.com"
                invoke-git config --global user.name "$actor"
                invoke-git config --system core.longpaths true
                # Configure hub to use https
                invoke-git config --global hub.protocol https

                # Clone URL
                invoke-git clone $url

                Set-Location -Path *
                
                if (!$directcommit) {
                    $branch = [System.IO.Path]::GetRandomFileName()
                    invoke-git checkout $targetBranch
                    invoke-git checkout -b $branch $targetBranch
                }

                invoke-git status

                $RepoSettingsFile = ".github\FSC-PS-Settings.json"
                if (Test-Path $RepoSettingsFile) {
                    $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json
                }
                else {
                    $repoSettings = [PSCustomObject]@{}
                }

                if ($repoSettings.PSObject.Properties.Name -eq "templateUrl") {
                    $repoSettings.templateUrl = $templateUrl
                }
                else {
                    $repoSettings | Add-Member -MemberType NoteProperty -Name "templateUrl" -Value $templateUrl
                }

                if ($repoSettings.PSObject.Properties.Name -eq "templateBranch") {
                    $repoSettings.templateBranch = $templateBranch
                }
                else {
                    $repoSettings | Add-Member -MemberType NoteProperty -Name "templateBranch" -Value $templateBranch
                }
                $repoSettings | ConvertTo-Json -Depth 99 | Set-Content $repoSettingsFile -Encoding UTF8

                $releaseNotes = ""
                $updateFiles | ForEach-Object {
                    $path = [System.IO.Path]::GetDirectoryName($_.DstFile)
                    if (-not (Test-Path -path $path -PathType Container)) {
                        New-Item -Path $path -ItemType Directory | Out-Null
                    }
                    
                    OutputInfo "Update $($_.DstFile)"
                    Set-Content -Path $_.DstFile -Encoding UTF8 -Value $_.Content
                }
                if ($releaseNotes -eq "") {
                    $releaseNotes = "No release notes available!"
                }
                $removeFiles | ForEach-Object {
                    OutputInfo "Remove $_"
                    Remove-Item (Join-Path (Get-Location).Path $_) -Force
                }

                invoke-git add *

                OutputInfo "ReleaseNotes:"
                OutputInfo $releaseNotes

                
                #$status = invoke-git status --porcelain=v2
                #OutputInfo "Git changes: $($status)"
                #if ($status) {
                    $message = "DevOps - Updated FSC-PS System Files"

                    invoke-git commit --allow-empty -m "'$message'"

                    if ($directcommit) {
                        invoke-git push $url
                    }
                    else {
                        invoke-git push -u $url $branch
                        Write-Output "Create PR to the $targetBranch"
                        invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY --body "$releaseNotes" --base "$targetBranch"
                    }
                #}
                #else {
                #    OutputInfo "No changes detected in files"
                #}
            }
            catch {
                if ($directCommit) {
                    throw "Failed to update FSC-PS System Files. Make sure that the personal access token, defined in the secret called repoTokenSecretName, is not expired and it has permission to update workflows. (Error was $($_.Exception.Message))"
                }
                else {
                    throw "Failed to create a pull-request to FSC-PS System Files. Make sure that the personal access token, defined in the secret called repoTokenSecretName, is not expired and it has permission to update workflows. (Error was $($_.Exception.Message))"
                }
            }
        }
        else {
            OutputWarning "Your repository runs on the latest version of FSC-PS System."
        }
    }

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
