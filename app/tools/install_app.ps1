param(
    [string]$AdbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [ValidateSet("debug", "release")]
    [string]$BuildMode = "debug",
    [string]$ApkPath = "",
    [string]$PackageName = "com.FAE.ScepTRONIC",
    [string]$DeviceSerial = "",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"
$mode = $BuildMode.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    $ApkPath = Join-Path $projectRoot "dist\septronics_$mode.apk"
}

if (!(Test-Path $AdbPath)) {
    throw "adb not found: $AdbPath"
}

if (!(Test-Path $ApkPath)) {
    throw "APK not found: $ApkPath"
}

$adbPrefix = @()
if (![string]::IsNullOrWhiteSpace($DeviceSerial)) {
    $adbPrefix = @("-s", $DeviceSerial)
}

& $AdbPath @adbPrefix "install" "-r" $ApkPath
if ($LASTEXITCODE -ne 0) {
    throw "adb install failed"
}

if ($Launch) {
    & $AdbPath @adbPrefix "shell" "monkey" "-p" $PackageName "-c" "android.intent.category.LAUNCHER" "1"
    if ($LASTEXITCODE -ne 0) {
        throw "adb launch failed"
    }
}
