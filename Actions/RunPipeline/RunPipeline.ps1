Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "DynamicsVersion", Mandatory = $false)]
    [string] $DynamicsVersion,
    [Parameter(HelpMessage = "Environment name o deploy", Mandatory = $false)]
    [string] $EnvironmentName,
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '',
    [Parameter(HelpMessage = "The environment type FSCM/Commerce", Mandatory = $false)]
    [string] $type = 'FSCM'
)

switch($type)
{
    'FSCM' { & $PSScriptRoot\RunFSCMPipeline.ps1 -actor $actor -EnvironmentName $EnvironmentName -DynamicsVersion $DynamicsVersion -token $token -settingsJson $settingsJson -secretsJson $secretsJson }
    'ECommerce' { & $PSScriptRoot\RunECommercePipeline.ps1 -actor $actor -EnvironmentName $EnvironmentName -DynamicsVersion $DynamicsVersion -token $token -settingsJson $settingsJson -secretsJson $secretsJson }
    'Retail' { & $PSScriptRoot\RunRetailPipeline.ps1 -actor $actor -EnvironmentName $EnvironmentName -DynamicsVersion $DynamicsVersion -token $token -settingsJson $settingsJson -secretsJson $secretsJson }
    'Commerce' { & $PSScriptRoot\RunCommercePipeline.ps1 -actor $actor -EnvironmentName $EnvironmentName -DynamicsVersion $DynamicsVersion -token $token -settingsJson $settingsJson -secretsJson $secretsJson }
}