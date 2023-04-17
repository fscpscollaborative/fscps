Param(
    [string] $configName = "",
    [switch] $collect,
    [string] $githubOwner,
    [string] $token,
    [string] $algoBranch,
    [switch] $github,
    [switch] $directCommit
)

$gitHubHelperPath = Join-Path $PSScriptRoot "..\Actions\Helpers\Github-Helper.psm1" -Resolve
Import-Module $gitHubHelperPath -DisableNameChecking

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$oldPath = Get-Location
try {

    if ($github) {
        if (!$githubOwner -or !$token) { throw "When running deploy in a workflow, you need to set githubOwner and token" }

        invoke-git config --global user.email "$githubOwner@users.noreply.github.com"
        invoke-git config --global user.name "$githubOwner"
        invoke-git config --global hub.protocol https
        invoke-git config --global core.autocrlf true

        $ENV:GITHUB_TOKEN = $token
        gh auth login --with-token
    }

    $originalOwnerAndRepo = @{
        "actionsRepo" = "ciellosinc/FSC-PS-Actions"
        "fscTemplateRepo" = "ciellosinc/FSC-PS.FSC"
        "retailTemplateRepo" = "ciellosinc/FSC-PS.Retail"
        "ecommerceTemplateRepo" = "ciellosinc/FSC-PS.ECommerce"
    }
    $originalBranch = "main"

    Set-Location $PSScriptRoot
    $baseRepoPath = invoke-git -returnValue rev-parse --show-toplevel
    Write-Host "Base repo path: $baseRepoPath"
    $user = gh api user | ConvertFrom-Json
    Write-Host "GitHub user: $($user.login)"

    if ($configName -eq "") { $configName = $user.login }
    if ([System.IO.Path]::GetExtension($configName) -eq "") { $configName += ".json" }
    $config = Get-Content $configName | ConvertFrom-Json

    Write-Host "Using config file: $configName"
    $config | ConvertTo-Json | Out-Host

    Set-Location $baseRepoPath

    if ($algoBranch) {
        invoke-git checkout $algoBranch
    }
    else {
        $algoBranch = invoke-git -returnValue branch --show-current
        Write-Host "Source branch: $algoBranch"
    }
    if ($collect) {
        $status = invoke-git -returnValue status --porcelain=v1 | Where-Object { ($_) -and ($_.SubString(3) -notlike "Internal/*") }
        if ($status) {
            throw "Destination repo is not clean, cannot collect changes into dirty repo"
        }
    }

    $srcUrl = invoke-git -returnValue config --get remote.origin.url
    if ($srcUrl.EndsWith('.git')) { $srcUrl = $srcUrl.Substring(0,$srcUrl.Length-4) }
    $uri = [Uri]::new($srcUrl)
    $srcOwnerAndRepo = $uri.LocalPath.Trim('/')
    Write-Host "Source Owner+Repo: $srcOwnerAndRepo"

    if (($config.PSObject.Properties.Name -eq "baseFolder") -and ($config.baseFolder)) {
        $baseFolder =  Join-Path $config.baseFolder $config.localFolder 
    }else {
        $baseFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) $config.localFolder
    }

    $copyToMain = $false
    if ($config.PSObject.Properties.Name -eq "copyToMain") {
        $copyToMain = $config.copyToMain
    }

    if (!(Test-Path $baseFolder)) {
        New-Item $baseFolder -ItemType Directory | Out-Null
    }
    Set-Location $baseFolder

    $config.actionsRepo, $config.fscTemplateRepo, $config.retailTemplateRepo, $config.ecommerceTemplateRepo | ForEach-Object {
        if (Test-Path $_) {
            Set-Location $_
            if ($collect) {
                $expectedUrl = "https://github.com/$($config.githubOwner)/$_.git"
                $actualUrl = invoke-git -returnValue config --get remote.origin.url
                if ($expectedUrl -ne $actualUrl) {
                    throw "unexpected git repo - was $actualUrl, expected $expectedUrl"
                }
            }
            else {
                if (Test-Path ".git") {
                    $status = invoke-git -returnValue status --porcelain
                    if ($status) {
                        throw "Git repo $_ is not clean, please resolve manually"
                    }
                }
            }
            Set-Location $baseFolder
        }
    }

    $actionsRepoPath = Join-Path $baseFolder $config.actionsRepo
    $fscTemplateRepoPath = Join-Path $baseFolder $config.fscTemplateRepo
    $retailTemplateRepoPath = Join-Path $baseFolder $config.retailTemplateRepo
    $ecommerceTemplateRepoPath = Join-Path $baseFolder $config.ecommerceTemplateRepo


    if ($collect) {
        Write-Host "This script will collect the changes in $($config.branch) from three repositories:"
        Write-Host
        Write-Host "https://github.com/$($config.githubOwner)/$($config.actionsRepo)  (folder $actionsRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.fscTemplateRepo)   (folder $fscTemplateRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.retailTemplateRepo)   (folder $retailTemplateRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.ecommerceTemplateRepo)   (folder $ecommerceTemplateRepoPath)"
        Write-Host
        Write-Host "To the $algoBranch branch from $srcOwnerAndRepo (folder $baseRepoPath)"
        Write-Host
    }
    else {
        Write-Host "This script will deploy the $algoBranch branch from $srcOwnerAndRepo (folder $baseRepoPath) to work repos"
        Write-Host
        Write-Host "Destination is the $($config.branch) branch in the followingrepositories:"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.actionsRepo)  (folder $actionsRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.fscTemplateRepo)  (folder $fscTemplateRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.retailTemplateRepo)   (folder $retailTemplateRepoPath)"        
        Write-Host "https://github.com/$($config.githubOwner)/$($config.ecommerceTemplateRepo)   (folder $ecommerceTemplateRepoPath)"
        Write-Host
        Write-Host "Run the collect.ps1 to collect your modifications in these work repos and copy back"
        Write-Host
    }
    if (-not $github) {
        Read-Host "If this is not what you want to do, then press Ctrl+C now, else press Enter."
    }

    $config.actionsRepo, $config.fscTemplateRepo, $config.retailTemplateRepo, $config.ecommerceTemplateRepo | ForEach-Object {
        if ($collect) {
            if (Test-Path $_) {
                Set-Location $_
                invoke-git pull
                Set-Location $baseFolder
            }
            else {
                $serverUrl = "https://github.com/$($config.githubOwner)/$_.git"
                invoke-git clone --quiet $serverUrl
            }
        }
        else {
            if (Test-Path $_) {
                Remove-Item $_ -Force -Recurse
            }
        }
    }

    $repos = @(
        @{ "repo" = $config.actionsRepo;            "srcPath" = Join-Path $baseRepoPath "Actions";                      "dstPath" = $actionsRepoPath;            "branch" = $config.branch }
        @{ "repo" = $config.fscTemplateRepo;        "srcPath" = Join-Path $baseRepoPath "Templates\FSC-PS.FSC";         "dstPath" = $fscTemplateRepoPath;        "branch" = $config.branch }
        @{ "repo" = $config.retailTemplateRepo;     "srcPath" = Join-Path $baseRepoPath "Templates\FSC-PS.Retail";      "dstPath" = $retailTemplateRepoPath;     "branch" = $config.branch }
        @{ "repo" = $config.ecommerceTemplateRepo;  "srcPath" = Join-Path $baseRepoPath "Templates\FSC-PS.ECommerce";   "dstPath" = $ecommerceTemplateRepoPath;  "branch" = $config.branch }
    )

    if ($collect) {
        $baseRepoBranch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
        if ($baseRepoBranch) {
            Set-Location $baseRepoPath
            invoke-git checkout -b $baseRepoBranch
        }

        $repos | ForEach-Object {
            Set-Location $baseFolder
            $repo = $_.repo
            $srcPath = $_.srcPath
            $dstPath = $_.dstPath
        
            Write-Host -ForegroundColor Yellow "Collecting from $repo"

            Get-ChildItem -Path "$srcPath\*" | Where-Object { !($_.PSIsContainer -and $_.Name -eq ".git") } | ForEach-Object {
                if ($_.PSIsContainer) {
                    Remove-Item $_ -Force -Recurse
                }
                else {
                    Remove-Item $_ -Force
                }
            }

            Get-ChildItem "$dstPath\*" -Recurse | Where-Object { !$_.PSIsContainer -and $_.name -notlike '*.copy.md' } | ForEach-Object {
                $dstFile = $_.FullName
                $srcFile = $srcPath + $dstFile.Substring($dstPath.Length)
                $srcFilePath = [System.IO.Path]::GetDirectoryName($srcFile)
                if (!(Test-Path $srcFilePath)) {
                    New-Item $srcFilePath -ItemType Directory | Out-Null
                }
                Write-Host "$dstFile -> $srcFile"
                $lines = ([string](Get-Content -Raw -path $dstFile)).Split("`n")
                "templateRepo","templateRepo" | ForEach-Object {
                    $regex = "^(.*)$($config.githubOwner)/$($config."$_")(.*)$($config.branch)(.*)$"
                    $replace = "`$1$($originalOwnerAndRepo."$_")`$2$originalBranch`$3"
                    $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
                }
                $lines -join "`n" | Set-Content $srcFile -Force -NoNewline
            }
        }
        Set-Location $baseRepoPath

        if ($github) {
            $serverUrl = "https://$($user.login):$token@github.com/$($srcOwnerAndRepo).git"
        }
        else {
            $serverUrl = "https://github.com/$($srcOwnerAndRepo).git"
        }

        $commitMessage = "Collect changes from $($config.githubOwner)/*@$($config.branch)"
        invoke-git add *
        invoke-git commit --allow-empty -m "'$commitMessage'"
        if ($baseRepoBranch) {
            invoke-git push -u $serverUrl $baseRepoBranch
            invoke-gh pr create --fill --head $baseRepoBranch --repo $srcOwnerAndRepo
            invoke-git checkout $algoBranch
        }
        else {
            invoke-git push $serverUrl
        }
    }
    else {
        $additionalRepos = @()
        if ($copyToMain -and $config.branch -ne "main") {
            Write-Host "Copy template repositories to main branch"
            $additionalRepos = @(
                @{ "repo" = $config.fscTemplateRepo;        "srcPath" = Join-Path $baseRepoPath "Templates\FSC-PS.FSC";       "dstPath" = $fscTemplateRepoPath;       "branch" = "main" }
                @{ "repo" = $config.retailTemplateRepo;     "srcPath" = Join-Path $baseRepoPath "Templates\FSC-PS.Retail";    "dstPath" = $retailTemplateRepoPath;    "branch" = "main" }
                @{ "repo" = $config.ecommerceTemplateRepo;  "srcPath" = Join-Path $baseRepoPath "Templates\FSC-PS.ECommerce"; "dstPath" = $ecommerceTemplateRepoPath; "branch" = "main" }
                @{ "repo" = $config.actionsRepo;            "srcPath" = Join-Path $baseRepoPath "Actions";                    "dstPath" = $actionsRepoPath;           "branch" = "main" }
            )
        }

        $additionalRepos + $repos | ForEach-Object {
            Set-Location $baseFolder
            $repo = $_.repo
            $srcPath = $_.srcPath
            $dstPath = $_.dstPath
            $branch = $_.branch

            Write-Host -ForegroundColor Yellow "Deploying to $repo"

            try {
                if ($github) {
                    $serverUrl = "https://$($user.login):$token@github.com/$($config.githubOwner)/$repo.git"
                }
                else {
                    $serverUrl = "https://github.com/$($config.githubOwner)/$repo.git"
                }
                if (Test-Path $repo) {
                    Remove-Item $repo -Recurse -Force
                }



                invoke-git clone --quiet $serverUrl
                Set-Location $repo
                try {
                    invoke-git checkout $branch
                    Get-ChildItem -Path .\* -Exclude ".git" | Remove-Item -Force -Recurse
                }
                catch {
                    invoke-git checkout -b $branch
                    invoke-git commit --allow-empty -m 'init'
                    invoke-git branch -M $branch
                    if ($github) {
                        invoke-git remote set-url origin $serverUrl
                    }
                    invoke-git push -u origin $branch
                }
            }
            catch {
                Write-Host "gh repo create $($config.githubOwner)/$repo --public --clone"
                $ownerRepo = "$($config.githubOwner)/$repo"
                invoke-gh repo create $ownerRepo --public --clone
                Start-Sleep -Seconds 10
                Set-Location $repo
                invoke-git checkout -b $branch
                invoke-git commit --allow-empty -m 'init'
                invoke-git branch -M $branch
                if ($github) {
                    invoke-git remote set-url origin $serverUrl
                }
                invoke-git push -u origin $branch
            }
        
            Get-ChildItem "$srcPath\*" -Recurse | Where-Object { !$_.PSIsContainer } | ForEach-Object {
                $srcFile = $_.FullName
                $dstFile = $dstPath + $srcFile.Substring($srcPath.Length)
                $dstFilePath = [System.IO.Path]::GetDirectoryName($dstFile)
                if (!(Test-Path $dstFilePath -PathType Container)) {
                    New-Item $dstFilePath -ItemType Directory | Out-Null
                }
                $useBranch = $config.branch
                if ($_.Name -eq "FSC-PS-Settings.json") {
                    $useBranch = $branch
                }
                $lines = ([string](Get-Content -Raw -path $srcFile)).Split("`n")
                "actionsRepo","ecommerceTemplateRepo","retailTemplateRepo","fscTemplateRepo" | ForEach-Object {
                    $regex = "^(.*)$($originalOwnerAndRepo."$_")(.*)$originalBranch(.*)$"
                    $replace = "`$1$($config.githubOwner)/$($config."$_")`$2$($useBranch)`$3"
                    $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
                }
                $lines -join "`n" | Set-Content $dstFile -Force -NoNewline
            }
            if (Test-Path -Path '.\.github' -PathType Container) {
                #Copy-Item -Path (Join-Path $baseRepoPath "RELEASENOTES.md") -Destination ".\.github\RELEASENOTES.copy.md" -Force
            }
            
            invoke-git add .
            invoke-git commit --allow-empty -m 'checkout'
            invoke-git push $serverUrl

            try{
                $latestRelease = Get-LatestRelease -token $token -repository $($config.githubOwner)/$($repo)
                $latestRelease
                if($latestRelease.id)
                {
                    Remove-Release -token $token
                    $release = @{
                        AccessToken = "$token"
                        TagName = "$($latestRelease.tag_name)"
                        Name = "$($latestRelease.name)"
                        ReleaseText = ""
                        Draft = $false
                        PreRelease = $false
                        RepositoryName = "$($repo)"
                        RepositoryOwner = "$($config.githubOwner)"
                    }
                    Write-Output "Release: $release"
                    Publish-GithubRelease @release
                }
            }
            catch {

            }

        }
    }
}
finally {
    set-location $oldPath
}
