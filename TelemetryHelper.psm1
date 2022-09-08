$signals = @{
    "DO0070" = "FnSCM-Go action ran: AddExistingApp"
    "DO0071" = "FnSCM-Go action ran: CheckForUpdates"
    "DO0072" = "FnSCM-Go action ran: CreateApp"
    "DO0073" = "FnSCM-Go action ran: CreateDevelopmentEnvironment"
    "DO0074" = "FnSCM-Go action ran: CreateReleaseNotes"
    "DO0075" = "FnSCM-Go action ran: Deploy"
    "DO0076" = "FnSCM-Go action ran: IncrementVersionNumber"
    "DO0077" = "FnSCM-Go action ran: PipelineCleanup"
    "DO0078" = "FnSCM-Go action ran: ReadSecrets"
    "DO0079" = "FnSCM-Go action ran: ReadSettings"
    "DO0080" = "FnSCM-Go action ran: RunPipeline"

    "DO0090" = "FnSCM-Go workflow ran: AddExistingAppOrTestApp"
    "DO0091" = "FnSCM-Go workflow ran: CiCd"
    "DO0092" = "FnSCM-Go workflow ran: CreateApp"
    "DO0093" = "FnSCM-Go workflow ran: CreateOnlineDevelopmentEnvironment"
    "DO0094" = "FnSCM-Go workflow ran: CreateRelease"
    "DO0095" = "FnSCM-Go workflow ran: CreateTestApp"
    "DO0096" = "FnSCM-Go workflow ran: IncrementVersionNumber"
    "DO0097" = "FnSCM-Go workflow ran: PublishToEnvironment"
    "DO0098" = "FnSCM-Go workflow ran: UpdateGitHubGoSystemFiles"
    "DO0099" = "FnSCM-Go workflow ran: NextMajor"
    "DO0100" = "FnSCM-Go workflow ran: NextMinor"
    "DO0101" = "FnSCM-Go workflow ran: Current"
    "DO0102" = "FnSCM-Go workflow ran: CreatePerformanceTestApp"
}

function CreateScope {
    param (
        [string] $eventId,
        [string] $parentTelemetryScopeJson = '{}'
    )

    $signalName = $signals[$eventId] 
    if (-not $signalName) {
        throw "Invalid event id ($eventId) is enountered."
    }

    if ($parentTelemetryScopeJson -and $parentTelemetryScopeJson -ne "{}") {
        $telemetryScope = RegisterTelemetryScope $parentTelemetryScopeJson
    }

    $telemetryScope = InitTelemetryScope -name $signalName -eventId $eventId  -parameterValues @()  -includeParameters @()

    return $telemetryScope
}

function GetHash {
    param(
        [string] $str
    )

    $stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($str))
    (Get-FileHash -InputStream $stream -FnSCMrithm SHA256).Hash
}
