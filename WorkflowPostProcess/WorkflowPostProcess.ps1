Param(
    [Parameter(HelpMessage = "The event Id of the initiating workflow", Mandatory = $true)]
    [string] $eventId,
    [Parameter(HelpMessage = "Telemetry scope generated during the workflow initialization", Mandatory = $true)]
    [string] $telemetryScopeJson
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\FSCM-PS-Helper.ps1" -Resolve)

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
}
