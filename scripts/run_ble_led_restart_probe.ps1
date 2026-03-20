param(
    [string]$AdbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$PackageName = "com.example.ble_led_endurance_app",
    [string]$ActivityName = "com.example.ble_led_endurance_app/.MainActivity",
    [string]$RemoteProbeFile = "app_flutter/restart_probe_status.json",
    [string]$RemoteProfileFile = "app_flutter/restart_probe_profile.json",
    [string]$OutputDir = "C:\android_app\ble_led_restart_probe",
    [string]$DeviceSerial = "",
    [int]$Cycles = 20,
    [int]$LaunchTimeoutSec = 30,
    [int]$PollIntervalMs = 500,
    [int]$ForceStopDelayMs = 1000,
    [switch]$UseRecordedFeatureReplay,
    [string[]]$ReplayFeatures = @("color", "rainbow", "heartbeat"),
    [int]$CyclesPerFeature = 10,
    [string]$ReplayColorHex = "FFFF0000",
    [int]$ReplayBrightness = 255,
    [int]$ReplayHeartbeatIntervalMs = 600,
    [int]$ReplayRainbowIntervalMs = 40,
    [bool]$ReplaySyncro = $true,
    [switch]$UseMcuPower,
    [string]$McuBridgeHost = "127.0.0.1",
    [int]$McuBridgePort = 9876,
    [int]$McuConnectTimeoutSec = 4,
    [int]$McuCommandTimeoutSec = 12,
    [int]$McuPowerOffDelayMs = 500,
    [int]$McuBootSettleMs = 3000,
    [bool]$McuPowerOffAfterCycle = $true,
    [switch]$StopOnFail
)

$ErrorActionPreference = "Stop"
$ProbeFilePath = "/data/user/0/$PackageName/$RemoteProbeFile"
$ProfileFilePath = "/data/user/0/$PackageName/$RemoteProfileFile"
$ProfileDirPath = $ProfileFilePath.Substring(0, $ProfileFilePath.LastIndexOf('/'))

function Get-AdbArgs {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if ([string]::IsNullOrWhiteSpace($DeviceSerial)) {
        return $Args
    }
    return @("-s", $DeviceSerial) + $Args
}

function Invoke-AdbText {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    $allArgs = Get-AdbArgs @Args
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $AdbPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = ($allArgs | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }) -join ' '

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $text = ($stdout + $stderr).Trim()
    return [PSCustomObject]@{
        Text = $text
        ExitCode = $process.ExitCode
    }
}

function Remove-RemoteProbeFile {
    $null = Invoke-AdbText "shell" "run-as" $PackageName "rm" "-f" $ProbeFilePath
}

function Remove-RemoteProfileFile {
    $null = Invoke-AdbText "shell" "run-as" $PackageName "rm" "-f" $ProfileFilePath
}

function Read-RemoteProbeFile {
    $result = Invoke-AdbText "shell" "run-as" $PackageName "cat" $ProbeFilePath
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Text)) {
        return $null
    }
    try {
        return ($result.Text | ConvertFrom-Json)
    } catch {
        return [PSCustomObject]@{
            parse_error = $_.Exception.Message
            raw = $result.Text
        }
    }
}

function Wait-ForProbe {
    param(
        [datetime]$Deadline
    )

    while ((Get-Date) -lt $Deadline) {
        $probe = Read-RemoteProbeFile
        if ($null -ne $probe) {
            return $probe
        }
        Start-Sleep -Milliseconds $PollIntervalMs
    }
    return $null
}

function Set-RemoteProfileFile {
    param(
        [hashtable]$Profile
    )

    $localTemp = Join-Path $env:TEMP ("restart_probe_profile_{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $remoteTemp = "/data/local/tmp/restart_probe_profile.json"

    try {
        $json = $Profile | ConvertTo-Json -Compress -Depth 5
        [System.IO.File]::WriteAllText(
            $localTemp,
            $json,
            [System.Text.UTF8Encoding]::new($false)
        )

        $push = Invoke-AdbText "push" $localTemp $remoteTemp
        if ($push.ExitCode -ne 0) {
            throw "adb push failed: $($push.Text)"
        }

        $mkdir = Invoke-AdbText "shell" "run-as" $PackageName "mkdir" "-p" $ProfileDirPath
        if ($mkdir.ExitCode -ne 0) {
            throw "profile dir create failed: $($mkdir.Text)"
        }

        $write = Invoke-AdbText "shell" "run-as" $PackageName "cp" $remoteTemp $ProfileFilePath
        if ($write.ExitCode -ne 0) {
            throw "profile write failed: $($write.Text)"
        }
    } finally {
        if (Test-Path $localTemp) {
            Remove-Item -LiteralPath $localTemp -Force -ErrorAction SilentlyContinue
        }
        $null = Invoke-AdbText "shell" "rm" "-f" $remoteTemp
    }
}

function Open-McuBridge {
    $client = New-Object System.Net.Sockets.TcpClient
    $async = $client.BeginConnect($McuBridgeHost, $McuBridgePort, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($McuConnectTimeoutSec))) {
        $client.Close()
        throw "MCU bridge connect timeout: $McuBridgeHost`:$McuBridgePort"
    }
    $client.EndConnect($async)
    $stream = $client.GetStream()
    $stream.ReadTimeout = 250
    $stream.WriteTimeout = 1000

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($stream, $utf8NoBom)
    $writer.NewLine = "`n"
    $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($stream, $utf8NoBom)

    return [PSCustomObject]@{
        Client = $client
        Stream = $stream
        Reader = $reader
        Writer = $writer
    }
}

function Close-McuBridge {
    param($Bridge)

    if ($null -eq $Bridge) {
        return
    }
    try { $Bridge.Reader.Dispose() } catch {}
    try { $Bridge.Writer.Dispose() } catch {}
    try { $Bridge.Stream.Dispose() } catch {}
    try { $Bridge.Client.Close() } catch {}
}

function Clear-McuBridgeBuffer {
    param(
        $Bridge,
        [int]$QuietMs = 300
    )

    $deadline = (Get-Date).AddMilliseconds($QuietMs)
    $lines = New-Object System.Collections.Generic.List[string]
    while ((Get-Date) -lt $deadline) {
        try {
            $line = $Bridge.Reader.ReadLine()
            if ($null -ne $line) {
                $lines.Add($line)
                $deadline = (Get-Date).AddMilliseconds($QuietMs)
            }
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 50
        }
    }
    return $lines
}

function Invoke-McuCommand {
    param(
        $Bridge,
        [string]$Command,
        [string[]]$ExpectedPatterns
    )

    [void](Clear-McuBridgeBuffer -Bridge $Bridge)
    $Bridge.Writer.WriteLine($Command)
    $seen = @{}
    foreach ($pattern in $ExpectedPatterns) {
        $seen[$pattern] = $false
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $deadline = (Get-Date).AddSeconds($McuCommandTimeoutSec)

    while ((Get-Date) -lt $deadline) {
        try {
            $line = $Bridge.Reader.ReadLine()
            if ($null -eq $line) {
                continue
            }
            $lines.Add($line)
            foreach ($pattern in $ExpectedPatterns) {
                if (-not $seen[$pattern] -and $line.Contains($pattern)) {
                    $seen[$pattern] = $true
                }
            }
            if (($seen.Values | Where-Object { -not $_ }).Count -eq 0) {
                return [PSCustomObject]@{
                    Ok = $true
                    Lines = @($lines)
                    Detail = ""
                }
            }
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 50
        }
    }

    return [PSCustomObject]@{
        Ok = $false
        Lines = @($lines)
        Detail = "Timeout waiting for: $($ExpectedPatterns -join ', ')"
    }
}

function Invoke-McuPowerCycle {
    $bridge = $null
    try {
        $bridge = Open-McuBridge

        $poff = Invoke-McuCommand -Bridge $bridge -Command "poff" -ExpectedPatterns @("POWER_A_OFF", "POWER_B_OFF")
        if (-not $poff.Ok) {
            return [PSCustomObject]@{
                Ok = $false
                FailureClass = "MCU_POWEROFF_TIMEOUT"
                FailureDetail = $poff.Detail
                Log = ($poff.Lines -join " || ")
            }
        }
        if ($McuPowerOffDelayMs -gt 0) {
            Start-Sleep -Milliseconds $McuPowerOffDelayMs
        }

        $boot = Invoke-McuCommand -Bridge $bridge -Command "boot" -ExpectedPatterns @("BOOT done")
        if (-not $boot.Ok) {
            return [PSCustomObject]@{
                Ok = $false
                FailureClass = "MCU_BOOT_TIMEOUT"
                FailureDetail = $boot.Detail
                Log = ($boot.Lines -join " || ")
            }
        }
        if ($McuBootSettleMs -gt 0) {
            Start-Sleep -Milliseconds $McuBootSettleMs
        }

        return [PSCustomObject]@{
            Ok = $true
            FailureClass = "PASS"
            FailureDetail = ""
            Log = (($poff.Lines + $boot.Lines) -join " || ")
        }
    } catch {
        return [PSCustomObject]@{
            Ok = $false
            FailureClass = "MCU_BRIDGE_ERROR"
            FailureDetail = $_.Exception.Message
            Log = ""
        }
    } finally {
        Close-McuBridge -Bridge $bridge
    }
}

function Invoke-McuPowerOffOnly {
    $bridge = $null
    try {
        $bridge = Open-McuBridge
        $poff = Invoke-McuCommand -Bridge $bridge -Command "poff" -ExpectedPatterns @("POWER_A_OFF", "POWER_B_OFF")
        return [PSCustomObject]@{
            Ok = $poff.Ok
            FailureClass = if ($poff.Ok) { "PASS" } else { "MCU_POWEROFF_TIMEOUT" }
            FailureDetail = if ($poff.Ok) { "" } else { $poff.Detail }
            Log = ($poff.Lines -join " || ")
        }
    } catch {
        return [PSCustomObject]@{
            Ok = $false
            FailureClass = "MCU_BRIDGE_ERROR"
            FailureDetail = $_.Exception.Message
            Log = ""
        }
    } finally {
        Close-McuBridge -Bridge $bridge
    }
}

function Escape-Csv {
    param([object]$Value)

    $text = if ($null -eq $Value) { "" } else { [string]$Value }
    $escaped = $text.Replace('"', '""')
    if ($escaped.Contains(",") -or $escaped.Contains('"') -or $escaped.Contains("`n") -or $escaped.Contains("`r")) {
        return '"' + $escaped + '"'
    }
    return $escaped
}

function Write-CsvRow {
    param(
        [System.IO.StreamWriter]$Writer,
        [object[]]$Values
    )

    $Writer.WriteLine(($Values | ForEach-Object { Escape-Csv $_ }) -join ",")
}

function New-ReplayScenario {
    param(
        [string]$Feature
    )

    switch ($Feature.Trim().ToLower()) {
        "color" {
            return [PSCustomObject]@{
                Name = "syncro_color_red"
                Feature = "color"
                Cycles = $CyclesPerFeature
                Profile = @{
                    enabled = $true
                    syncro = $ReplaySyncro
                    feature = "color"
                    color_hex = $ReplayColorHex.ToUpper()
                    brightness = $ReplayBrightness
                    heartbeat_interval_ms = $ReplayHeartbeatIntervalMs
                    rainbow_interval_ms = $ReplayRainbowIntervalMs
                    scenario_label = "syncro_color_red"
                }
            }
        }
        "rainbow" {
            return [PSCustomObject]@{
                Name = "syncro_rainbow"
                Feature = "rainbow"
                Cycles = $CyclesPerFeature
                Profile = @{
                    enabled = $true
                    syncro = $ReplaySyncro
                    feature = "rainbow"
                    color_hex = $ReplayColorHex.ToUpper()
                    brightness = $ReplayBrightness
                    heartbeat_interval_ms = $ReplayHeartbeatIntervalMs
                    rainbow_interval_ms = $ReplayRainbowIntervalMs
                    scenario_label = "syncro_rainbow"
                }
            }
        }
        "heartbeat" {
            return [PSCustomObject]@{
                Name = "syncro_heartbeat"
                Feature = "heartbeat"
                Cycles = $CyclesPerFeature
                Profile = @{
                    enabled = $true
                    syncro = $ReplaySyncro
                    feature = "heartbeat"
                    color_hex = $ReplayColorHex.ToUpper()
                    brightness = $ReplayBrightness
                    heartbeat_interval_ms = $ReplayHeartbeatIntervalMs
                    rainbow_interval_ms = $ReplayRainbowIntervalMs
                    scenario_label = "syncro_heartbeat"
                }
            }
        }
        default {
            throw "Unsupported replay feature: $Feature"
        }
    }
}

function Ensure-ScenarioStats {
    param(
        [hashtable]$Stats,
        [string]$Name
    )

    if (-not $Stats.ContainsKey($Name)) {
        $Stats[$Name] = @{
            PASS = 0
            FAIL = 0
            TOTAL = 0
        }
    }
}

if (!(Test-Path $AdbPath)) {
    throw "adb not found: $AdbPath"
}

$packageLine = Invoke-AdbText "shell" "pm" "list" "packages" $PackageName
if ($packageLine.Text -notmatch [regex]::Escape($PackageName)) {
    throw "Package not installed: $PackageName"
}

if ($LaunchTimeoutSec -le 0 -or $PollIntervalMs -le 0 -or $ForceStopDelayMs -lt 0) {
    throw "Timeout values must be positive."
}

if ($UseMcuPower -and ($McuBridgePort -le 0 -or $McuBridgePort -gt 65535)) {
    throw "MCU bridge port must be in 1-65535."
}

if ($UseRecordedFeatureReplay) {
    if ($CyclesPerFeature -le 0) {
        throw "CyclesPerFeature must be greater than 0."
    }
    if ([string]::IsNullOrWhiteSpace($ReplayColorHex)) {
        throw "ReplayColorHex is required."
    }
} elseif ($Cycles -le 0) {
    throw "Cycles must be greater than 0."
}

$scenarioSpecs = @()
if ($UseRecordedFeatureReplay) {
    foreach ($feature in $ReplayFeatures) {
        $scenarioSpecs += New-ReplayScenario -Feature $feature
    }
} else {
    $scenarioSpecs += [PSCustomObject]@{
        Name = "baseline_restart_probe"
        Feature = ""
        Cycles = $Cycles
        Profile = $null
    }
}

$plannedTotalCycles = ($scenarioSpecs | Measure-Object -Property Cycles -Sum).Sum
if ($plannedTotalCycles -le 0) {
    throw "No restart probe cycles are planned."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$detailPath = Join-Path $OutputDir "restart_probe_$stamp.csv"
$summaryPath = Join-Path $OutputDir "restart_probe_summary_$stamp.csv"

$detailWriter = [System.IO.StreamWriter]::new($detailPath, $false, [System.Text.UTF8Encoding]::new($false))
$summaryWriter = [System.IO.StreamWriter]::new($summaryPath, $false, [System.Text.UTF8Encoding]::new($false))

try {
    Write-CsvRow $detailWriter @(
        "cycle",
        "scenario",
        "scenario_cycle",
        "scenario_total_cycles",
        "start_iso",
        "end_iso",
        "duration_ms",
        "result",
        "failure_class",
        "failure_detail",
        "phase",
        "auto_connect_ok",
        "registered",
        "a_status",
        "b_status",
        "a_device",
        "b_device",
        "a_pair",
        "b_pair",
        "error",
        "expected_feature",
        "expected_color_hex",
        "replay_profile_enabled",
        "replay_feature",
        "replay_syncro",
        "replay_scenario_label",
        "startup_wave_ok",
        "startup_wave_error",
        "replay_apply_ok",
        "replay_apply_error",
        "mcu_result",
        "mcu_failure_class",
        "mcu_failure_detail",
        "mcu_log"
    )

    $failureCounts = @{}
    $scenarioStats = @{}
    $passCount = 0
    $failCount = 0
    $globalCycle = 0
    $stopAll = $false

    foreach ($scenario in $scenarioSpecs) {
        if ($scenario.Profile -ne $null) {
            Set-RemoteProfileFile -Profile $scenario.Profile
        } else {
            Remove-RemoteProfileFile
        }

        Ensure-ScenarioStats -Stats $scenarioStats -Name $scenario.Name

        for ($scenarioCycle = 1; $scenarioCycle -le $scenario.Cycles; $scenarioCycle++) {
            $globalCycle++
            $startedAt = Get-Date
            $expectedFeature = [string]$scenario.Feature
            $expectedColorHex = if ($scenario.Profile -ne $null) {
                [string]$scenario.Profile.color_hex
            } else {
                ""
            }
            $expectedReplayEnabled = if ($scenario.Profile -ne $null) {
                [bool]$scenario.Profile.enabled
            } else {
                $false
            }
            $expectedReplaySyncro = if ($scenario.Profile -ne $null) {
                $scenario.Profile.syncro
            } else {
                $null
            }
            $expectedScenarioLabel = if ($scenario.Profile -ne $null) {
                [string]$scenario.Profile.scenario_label
            } else {
                ""
            }

            Remove-RemoteProbeFile

            $forceStop = Invoke-AdbText "shell" "am" "force-stop" $PackageName
            if ($forceStop.ExitCode -ne 0) {
                throw "adb force-stop failed: $($forceStop.Text)"
            }
            if ($ForceStopDelayMs -gt 0) {
                Start-Sleep -Milliseconds $ForceStopDelayMs
            }

            $mcuResult = "SKIPPED"
            $mcuFailureClass = ""
            $mcuFailureDetail = ""
            $mcuLog = ""
            if ($UseMcuPower) {
                $mcuCycle = Invoke-McuPowerCycle
                $mcuResult = if ($mcuCycle.Ok) { "PASS" } else { "FAIL" }
                $mcuFailureClass = $mcuCycle.FailureClass
                $mcuFailureDetail = $mcuCycle.FailureDetail
                $mcuLog = $mcuCycle.Log
                if (-not $mcuCycle.Ok) {
                    $endedAt = Get-Date
                    $durationMs = [int][Math]::Round(($endedAt - $startedAt).TotalMilliseconds)
                    $result = "FAIL"
                    $failureClass = $mcuFailureClass
                    $failureDetail = $mcuFailureDetail

                    if (-not $failureCounts.ContainsKey($failureClass)) {
                        $failureCounts[$failureClass] = 0
                    }
                    $failureCounts[$failureClass]++
                    $scenarioStats[$scenario.Name].FAIL++
                    $scenarioStats[$scenario.Name].TOTAL++
                    $failCount++

                    Write-CsvRow $detailWriter @(
                        $globalCycle,
                        $scenario.Name,
                        $scenarioCycle,
                        $scenario.Cycles,
                        $startedAt.ToString("o"),
                        $endedAt.ToString("o"),
                        $durationMs,
                        $result,
                        $failureClass,
                        $failureDetail,
                        "",
                        $null,
                        $null,
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        $expectedFeature,
                        $expectedColorHex,
                        $expectedReplayEnabled,
                        $expectedFeature,
                        $expectedReplaySyncro,
                        $expectedScenarioLabel,
                        $null,
                        "",
                        $null,
                        "",
                        $mcuResult,
                        $mcuFailureClass,
                        $mcuFailureDetail,
                        $mcuLog
                    )
                    $detailWriter.Flush()
                    Write-Host ("Cycle {0}/{1} [{2} {3}/{4}]: {5} {6} {7}" -f $globalCycle, $plannedTotalCycles, $scenario.Name, $scenarioCycle, $scenario.Cycles, $result, $failureClass, $failureDetail)
                    if ($StopOnFail) {
                        $stopAll = $true
                        break
                    }
                    continue
                }
            }

            $launch = Invoke-AdbText "shell" "am" "start" "-W" "-n" $ActivityName
            if ($launch.ExitCode -ne 0) {
                throw "adb launch failed: $($launch.Text)"
            }

            $probe = Wait-ForProbe -Deadline ((Get-Date).AddSeconds($LaunchTimeoutSec))
            $endedAt = Get-Date
            $durationMs = [int][Math]::Round(($endedAt - $startedAt).TotalMilliseconds)

            $result = "FAIL"
            $failureClass = "PROBE_TIMEOUT"
            $failureDetail = "restart_probe_status.json was not written within timeout."
            $phase = ""
            $autoConnectOk = $null
            $registered = $null
            $aStatus = ""
            $bStatus = ""
            $aDevice = ""
            $bDevice = ""
            $aPair = ""
            $bPair = ""
            $errorText = ""
            $replayProfileEnabled = $false
            $replayFeature = ""
            $actualReplaySyncro = $null
            $replayScenarioLabel = ""
            $startupWaveOk = $null
            $startupWaveError = ""
            $replayApplyOk = $null
            $replayApplyError = ""

            if ($null -ne $probe) {
                if ($probe.PSObject.Properties.Name -contains "parse_error") {
                    $failureClass = "PROBE_PARSE_ERROR"
                    $failureDetail = $probe.parse_error
                    $errorText = $probe.raw
                } else {
                    $phase = [string]$probe.phase
                    $autoConnectOk = $probe.auto_connect_ok
                    $registered = $probe.registered
                    $aStatus = [string]$probe.a_status
                    $bStatus = [string]$probe.b_status
                    $aDevice = [string]$probe.a_device
                    $bDevice = [string]$probe.b_device
                    $aPair = [string]$probe.a_pair
                    $bPair = [string]$probe.b_pair
                    $errorText = [string]$probe.error
                    $replayProfileEnabled = [bool]$probe.replay_profile_enabled
                    $replayFeature = [string]$probe.replay_feature
                    $actualReplaySyncro = $probe.replay_syncro
                    $replayScenarioLabel = [string]$probe.replay_scenario_label
                    $startupWaveOk = $probe.startup_wave_ok
                    $startupWaveError = [string]$probe.startup_wave_error
                    $replayApplyOk = $probe.replay_apply_ok
                    $replayApplyError = [string]$probe.replay_apply_error

                    if (-not $registered) {
                        $failureClass = "DEVICES_NOT_ASSIGNED"
                        $failureDetail = "Stock A/B are not assigned in the app."
                    } elseif ($autoConnectOk -ne $true -or $aStatus -ne "connected" -or $bStatus -ne "connected") {
                        if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                            $failureClass = "STARTUP_EXCEPTION"
                            $failureDetail = $errorText
                        } else {
                            $failureClass = "RECONNECT_INCOMPLETE"
                            $failureDetail = "A=$aStatus B=$bStatus auto_connect_ok=$autoConnectOk"
                        }
                    } elseif ($expectedFeature -ne "") {
                        if ($replayProfileEnabled -ne $true) {
                            $failureClass = "REPLAY_PROFILE_MISSING"
                            $failureDetail = "Restart replay profile was not loaded by the app."
                        } elseif ($startupWaveOk -ne $true) {
                            $failureClass = "STARTUP_WAVE_FAIL"
                            $failureDetail = if ([string]::IsNullOrWhiteSpace($startupWaveError)) { "Startup wave did not complete." } else { $startupWaveError }
                        } elseif ($replayApplyOk -ne $true) {
                            $failureClass = "REPLAY_APPLY_FAIL"
                            $failureDetail = if ([string]::IsNullOrWhiteSpace($replayApplyError)) { "Replay feature apply did not complete." } else { $replayApplyError }
                        } elseif ($replayFeature -ne $expectedFeature) {
                            $failureClass = "REPLAY_FEATURE_MISMATCH"
                            $failureDetail = "Expected=$expectedFeature Actual=$replayFeature"
                        } else {
                            $result = "PASS"
                            $failureClass = "PASS"
                            $failureDetail = ""
                        }
                    } else {
                        $result = "PASS"
                        $failureClass = "PASS"
                        $failureDetail = ""
                    }
                }
            }

            if ($result -eq "PASS") {
                $passCount++
                $scenarioStats[$scenario.Name].PASS++
            } else {
                $failCount++
                $scenarioStats[$scenario.Name].FAIL++
            }
            $scenarioStats[$scenario.Name].TOTAL++

            if (-not $failureCounts.ContainsKey($failureClass)) {
                $failureCounts[$failureClass] = 0
            }
            $failureCounts[$failureClass]++

            Write-CsvRow $detailWriter @(
                $globalCycle,
                $scenario.Name,
                $scenarioCycle,
                $scenario.Cycles,
                $startedAt.ToString("o"),
                $endedAt.ToString("o"),
                $durationMs,
                $result,
                $failureClass,
                $failureDetail,
                $phase,
                $autoConnectOk,
                $registered,
                $aStatus,
                $bStatus,
                $aDevice,
                $bDevice,
                $aPair,
                $bPair,
                $errorText,
                $expectedFeature,
                $expectedColorHex,
                $replayProfileEnabled,
                $replayFeature,
                $actualReplaySyncro,
                $replayScenarioLabel,
                $startupWaveOk,
                $startupWaveError,
                $replayApplyOk,
                $replayApplyError,
                $mcuResult,
                $mcuFailureClass,
                $mcuFailureDetail,
                $mcuLog
            )
            $detailWriter.Flush()

            Write-Host ("Cycle {0}/{1} [{2} {3}/{4}]: {5} {6} {7}" -f $globalCycle, $plannedTotalCycles, $scenario.Name, $scenarioCycle, $scenario.Cycles, $result, $failureClass, $failureDetail)

            if ($UseMcuPower -and $McuPowerOffAfterCycle) {
                $null = Invoke-McuPowerOffOnly
            }

            if ($StopOnFail -and $result -eq "FAIL") {
                $stopAll = $true
                break
            }
        }

        if ($stopAll) {
            break
        }
    }

    Remove-RemoteProfileFile

    Write-CsvRow $summaryWriter @("failure_class", "count")
    foreach ($key in ($failureCounts.Keys | Sort-Object)) {
        Write-CsvRow $summaryWriter @($key, $failureCounts[$key])
    }
    Write-CsvRow $summaryWriter @("TOTAL_CYCLES", ($passCount + $failCount))
    Write-CsvRow $summaryWriter @("PASS", $passCount)
    Write-CsvRow $summaryWriter @("FAIL", $failCount)
    $passRate = if (($passCount + $failCount) -eq 0) { 0 } else { [Math]::Round(($passCount * 100.0) / ($passCount + $failCount), 2) }
    Write-CsvRow $summaryWriter @("PASS_RATE(%)", $passRate)
    Write-CsvRow $summaryWriter @("", "")
    Write-CsvRow $summaryWriter @("scenario", "result", "count")
    foreach ($scenarioName in ($scenarioStats.Keys | Sort-Object)) {
        Write-CsvRow $summaryWriter @($scenarioName, "PASS", $scenarioStats[$scenarioName].PASS)
        Write-CsvRow $summaryWriter @($scenarioName, "FAIL", $scenarioStats[$scenarioName].FAIL)
        Write-CsvRow $summaryWriter @($scenarioName, "TOTAL", $scenarioStats[$scenarioName].TOTAL)
    }
}
finally {
    $detailWriter.Dispose()
    $summaryWriter.Dispose()
}

Write-Host "Detail: $detailPath"
Write-Host "Summary: $summaryPath"
