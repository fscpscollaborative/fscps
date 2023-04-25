Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '',
    [Parameter(HelpMessage = "artifactsPath", Mandatory = $false)]
    [string] $artifactsPath = '',
    [Parameter(HelpMessage = "The environment type FSCM/Commerce", Mandatory = $false)]
    [string] $type = "FSCM"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSC-PS-Helper.ps1" -Resolve)
    $github = (Get-ActionContext)

    $github.Payload.inputs

    #Use settings and secrets
    Write-Output "::group::Use settings and secrets"
    OutputInfo "======================================== Use settings and secrets"

    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable | ConvertTo-OrderedDictionary
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
    
    if($settings.sourceBranch -eq "")
    {
        $settings.sourceBranch = $settings.currentBranch
    }

    #SourceBranchToPascakCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })

    Write-Output "::endgroup::"
    
    $name = "$($github.Payload.inputs.name)" -replace "-" , " " -replace "    " , " " -replace "   " , " " -replace "  " , " " -replace " " , "."
       
    $tag = "v"+"$($github.Payload.inputs.versionNumber)"+"_"+"$($settings.currentBranch)"

    Write-Output "Tag is : $tag"

    $latestRelease = Get-LatestRelease -token $token
    $releaseNote = Get-ReleaseNotes -token $token -tag_name "$tag" -previous_tag_name $($latestRelease.tag_name)

    
    $release = @{
        AccessToken = "$repoTokenSecretName"
        TagName = "$tag"
        Name = "$name"
        ReleaseText = "$(($releaseNote.Content | ConvertFrom-Json ).body)"
        Draft = $false
        PreRelease = $false
        RepositoryName = "$($github.Payload.repository.name)"
        RepositoryOwner = "$($Env:GITHUB_REPOSITORY_OWNER)"
    }
    Write-Output "Release: "
    
    $release 
    Write-Output "Artifacts path: $artifactsPath"

    ### Add custom file to the release folder
    if($github.Payload.inputs.PSObject.Properties.Name -eq "customFileUrl")
    {
        if($github.Payload.inputs.customFileUrl -ne "" -and $github.Payload.inputs.customFileName -ne "")
        {
            try {
                Invoke-WebRequest -Uri "$($github.Payload.inputs.customFileUrl)" -OutFile "$(Join-Path $artifactsPath $github.Payload.inputs.customFileName)"
            }
            catch {
                OutputError "Something went wrong with the file downloading! Error: $($_.Exception.Message)"
            }
        }
    }
    ###
    Publish-GithubRelease @release -Artifact "$artifactsPath" -Commit $settings.sourceBranch
}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
