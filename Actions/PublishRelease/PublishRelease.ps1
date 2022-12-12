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
    $workflowName = $env:GITHUB_WORKFLOW
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $github = (Get-ActionContext)


    $github.Payload.inputs

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
    
    $name = "$($github.Payload.inputs.name)" -replace "-" , " " -replace "    " , " " -replace "   " , " " -replace "  " , " " -replace " " , "."
       
    $tag = "v"+"$($github.Payload.inputs.versionNumber)"+"_"+"$($settings.currentBranch)"

    Write-Output "Tag is : $tag"


    $repoOwner = ""
    try{
        $repoOwner = "$($github.Payload.organization.login)"
    }
    catch{
        $repoOwner = "$($github.Payload.sender.login)"
    }
    $release = @{
        AccessToken = "$repoTokenSecretName"
        TagName = "$tag"
        Name = "$name"
        ReleaseText = "$name"
        Draft = "$($github.Payload.inputs.draft)" -eq "Y"
        PreRelease = "$($github.Payload.inputs.prerelease)" -eq "Y"
        RepositoryName = "$($github.Payload.repository.name)"
        RepositoryOwner = $repoOwner
    }
    Write-Output "Release: "
    $release 
    Write-Output "Artifacts path: $artifactsPath"

    Publish-GithubRelease @release -Artifact "$artifactsPath"

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
