param(
    [Parameter(Mandatory = $false)]
    [string]$ComPort = "COM4",
    [int]$Baud = 115200,
    [string]$ListenHost = "127.0.0.1",
    [int]$ListenPort = 9876,
    [string]$PythonExe = "python",
    [string]$AdbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$DeviceSerial = "",
    [switch]$SkipAdbReverse,
    [switch]$ListPorts
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "mcu_android_bridge.py"
if (!(Test-Path $scriptPath)) {
    throw "Bridge script not found: $scriptPath"
}

if ($ListPorts) {
    & $PythonExe $scriptPath --list-ports
    exit $LASTEXITCODE
}

if (!(Test-Path $AdbPath)) {
    throw "adb not found: $AdbPath"
}

if (-not $SkipAdbReverse) {
    $adbPrefix = @()
    if (![string]::IsNullOrWhiteSpace($DeviceSerial)) {
        $adbPrefix = @("-s", $DeviceSerial)
    }
    & $AdbPath @adbPrefix reverse "tcp:$ListenPort" "tcp:$ListenPort"
    if ($LASTEXITCODE -ne 0) {
        throw "adb reverse failed"
    }
}

Write-Host "Starting MCU bridge on $ListenHost`:$ListenPort -> $ComPort ($Baud baud)"
Write-Host "Android app should use PC Bridge with host 127.0.0.1 and port $ListenPort"

& $PythonExe $scriptPath `
    --serial-port $ComPort `
    --baud $Baud `
    --listen-host $ListenHost `
    --listen-port $ListenPort

exit $LASTEXITCODE
