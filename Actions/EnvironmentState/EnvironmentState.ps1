Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '',
    [Parameter(HelpMessage = "environmentName", Mandatory = $false)]
    [string] $environmentName = '',
    [Parameter(HelpMessage = "state", Mandatory = $false)]
    [string] $state = '',
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
    
    $settings.buildVersion

    if($settings.sourceBranch -eq "")
    {
        $settings.sourceBranch = $settings.currentBranch
    }

    #SourceBranchToPascakCase
    $settings.sourceBranch = [regex]::Replace(($settings.sourceBranch).Replace("refs/heads/","").Replace("/","_"), '(?i)(?:^|-|_)(\p{L})', { $args[0].Groups[1].Value.ToUpper() })
    Write-Output "::endgroup::"

    Write-Output "::group::Start/Stop environment"
    
    $PowerState = ""
    $PowerState = Check-AzureVMState -VMName $($settings.azVmname) -VMGroup $($settings.azVmrg) -ClientId "$($settings.azClientId)" -ClientSecret "$azClientsecretSecretname" -TenantId $($settings.azTenantId)
    OutputInfo "The environment '$environmentName' is $PowerState"

    if($state -eq "Start")
    {
        #Startup environment
        if($PowerState -ne "running")
        {
            OutputInfo "======================================== Start $($environmentName)"
            az vm start -g $($settings.azVmrg) -n $($settings.azVmname)
            #Start-Sleep -Seconds 60
            $PowerState = ([string](az vm get-instance-view --name $($settings.azVmname) --resource-group $($settings.azVmrg) --query instanceView.statuses[1] | ConvertFrom-Json).DisplayStatus).Trim().Trim("[").Trim("]").Trim('"').Trim("VM ").Replace(' ','')
            OutputInfo "The environment '$environmentName' is $PowerState"
            Start-Sleep -Seconds 3
        }
    }
    if($state -eq "Stop")
    {
        #Stop environment
        if($PowerState -eq "running")
        {
            OutputInfo "======================================== Stop $($environmentName)"
            az vm deallocate -g $($settings.azVmrg) -n $($settings.azVmname)
            #Start-Sleep -Seconds 15
            $PowerState = ([string](az vm get-instance-view --name $($settings.azVmname) --resource-group $($settings.azVmrg) --query instanceView.statuses[1] | ConvertFrom-Json).DisplayStatus).Trim().Trim("[").Trim("]").Trim('"').Trim("VM ").Replace(' ','')
            OutputInfo "The environment '$environmentName' is $PowerState"
            Start-Sleep -Seconds 3
        }
    }
    Write-Output "::endgroup::"

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    OutputInfo "Execution is done."
}
