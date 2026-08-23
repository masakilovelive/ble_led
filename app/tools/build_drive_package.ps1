param(
    [ValidateSet("debug", "release")]
    [string]$BuildMode = "debug",
    [string]$SourceDir = "$PSScriptRoot\..",
    [string]$WorkDir = "C:\android_app\septronics",
    [string]$FlutterCmd = "flutter"
)

$ErrorActionPreference = "Stop"
$mode = $BuildMode.ToLowerInvariant()
$isRelease = $mode -eq "release"
$workDirExplicit = $PSBoundParameters.ContainsKey("WorkDir")

function Resolve-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    return [System.IO.Path]::GetFullPath($resolved)
}

function Remove-ReleaseOnlySourceFiles {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $releaseOnlyFiles = @(
        "lib\router.dart",
        "lib\screens\scan_screen.dart",
        "lib\screens\pair_test_screen.dart",
        "lib\screens\dual_color_screen.dart",
        "lib\screens\endurance_screen.dart",
        "lib\screens\shipment_inspection_screen.dart",
        "lib\screens\stress_lab_screen.dart",
        "lib\ble\pair_test_controller.dart",
        "lib\ble\endurance_controller.dart",
        "lib\ble\shipment_inspection_controller.dart",
        "lib\ble\stress_lab_controller.dart",
        "lib\ble\restart_probe_profile.dart"
    )

    foreach ($relativePath in $releaseOnlyFiles) {
        $targetPath = Join-Path $RootPath $relativePath
        if (Test-Path -LiteralPath $targetPath) {
            Remove-Item -LiteralPath $targetPath -Force
        }
    }
}

function Write-ReleaseStubs {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $shipmentStubPath = Join-Path $RootPath "lib\screens\shipment_inspection_screen.dart"
    $shipmentStub = @'
import 'package:flutter/material.dart';

class ShipmentInspectionScreen extends StatelessWidget {
  const ShipmentInspectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SHIPMENT INSPECTION'),
      ),
      body: const Center(
        child: Text('Shipment inspection is disabled in release build.'),
      ),
    );
  }
}
'@
    Set-Content -LiteralPath $shipmentStubPath -Value $shipmentStub -Encoding UTF8
}

function Export-ReleaseFirmware {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $firmwareSpecs = @(
        @{ Source = "ver1_esp32c3_stock1\ver1_esp32c3_stock1.ino"; Output = "ver1_esp32c3_stock1_release.ino" },
        @{ Source = "ver1_esp32c6_stock1\ver1_esp32c6_stock1.ino"; Output = "ver1_esp32c6_stock1_release.ino" }
    )

    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null

    $created = @()
    foreach ($spec in $firmwareSpecs) {
        $sourcePath = Join-Path $SourceRoot $spec.Source
        if (!(Test-Path -LiteralPath $sourcePath)) {
            throw "Firmware source not found: $sourcePath"
        }

        $content = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
        $content = $content -replace "(#define\s+SEPTRONICS_RELEASE_BUILD\s+)0", '${1}1'

        $outputPath = Join-Path $DestinationRoot $spec.Output
        Set-Content -LiteralPath $outputPath -Value $content -Encoding UTF8
        $created += $outputPath
    }

    return ,$created
}

if (!(Test-Path -LiteralPath $SourceDir)) {
    throw "SourceDir not found: $SourceDir"
}

$sourcePath = Resolve-NormalizedPath -Path $SourceDir
$outputDir = Join-Path $sourcePath "dist"
$activeWorkDir = $WorkDir

if (Test-Path -LiteralPath $activeWorkDir) {
    $resolvedWork = Resolve-NormalizedPath -Path $activeWorkDir
    if (-not $resolvedWork.StartsWith("C:\android_app\septronics")) {
        throw "Refusing to remove unexpected WorkDir: $resolvedWork"
    }

    $removed = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $resolvedWork -Recurse -Force
            $removed = $true
            break
        }
        catch {
            if ($attempt -lt 3) {
                Start-Sleep -Seconds 2
            }
        }
    }

    if (-not $removed) {
        if ($workDirExplicit) {
            throw "Failed to clear WorkDir after retries: $resolvedWork"
        }
        $suffix = Get-Date -Format "yyyyMMdd_HHmmss"
        $activeWorkDir = "C:\android_app\septronics_${mode}_$suffix"
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $activeWorkDir) -Force | Out-Null

$robocopyArgs = @(
    $sourcePath,
    $activeWorkDir,
    "/E",
    "/XD", ".dart_tool", "build", "dist", ".gradle", ".kotlin",
    "/XF", ".flutter-plugins-dependencies"
)

robocopy @robocopyArgs | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

$ephemeralTargets = @(
    (Join-Path $activeWorkDir "windows\flutter\ephemeral"),
    (Join-Path $activeWorkDir "linux\flutter\ephemeral"),
    (Join-Path $activeWorkDir "ios\Flutter\ephemeral"),
    (Join-Path $activeWorkDir "macos\Flutter\ephemeral")
)

foreach ($target in $ephemeralTargets) {
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

if ($isRelease) {
    Remove-ReleaseOnlySourceFiles -RootPath $activeWorkDir
    Write-ReleaseStubs -RootPath $activeWorkDir
}

Push-Location $activeWorkDir
try {
    $flutterArgs = @("build", "apk")
    if ($isRelease) {
        $flutterArgs += @("--release", "--dart-define=SEPTRONICS_RELEASE_BUILD=1")
    }
    else {
        $flutterArgs += @("--debug", "--dart-define=SEPTRONICS_RELEASE_BUILD=0")
    }

    & $FlutterCmd @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk --$mode failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$apkSource = if ($isRelease) {
    Join-Path $activeWorkDir "build\app\outputs\flutter-apk\app-release.apk"
}
else {
    Join-Path $activeWorkDir "build\app\outputs\flutter-apk\app-debug.apk"
}
if (!(Test-Path -LiteralPath $apkSource)) {
    throw "APK not found after build: $apkSource"
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$pubspecPath = Join-Path $sourcePath "pubspec.yaml"
$versionLine = Get-Content -LiteralPath $pubspecPath | Where-Object { $_ -match "^version:\s*(.+)$" } | Select-Object -First 1
$version = if ($versionLine) { ($versionLine -replace "^version:\s*", "").Trim() } else { "unknown" }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$apkName = "septronics_${mode}.apk"
$apkOutput = Join-Path $outputDir $apkName
Copy-Item -LiteralPath $apkSource -Destination $apkOutput -Force

$releaseFirmwareFiles = @()
if ($isRelease) {
    $firmwareOutDir = Join-Path $outputDir "firmware_release"
    $releaseFirmwareFiles = Export-ReleaseFirmware -SourceRoot $sourcePath -DestinationRoot $firmwareOutDir
}

$manifestPath = Join-Path $outputDir "septronics_${mode}_drive_manifest.txt"
$manifestBody = @(
    "app: septronics",
    "version: $version",
    "build: $mode",
    "package_name: com.FAE.ScepTRONIC",
    "generated_at: $timestamp",
    "apk_file: $apkName",
    "release_debug_content_removed: $($isRelease.ToString().ToLowerInvariant())"
)
if ($isRelease -and $releaseFirmwareFiles.Count -gt 0) {
    $firmwareNames = $releaseFirmwareFiles | ForEach-Object { Split-Path -Leaf $_ }
    $manifestBody += "firmware_files: $($firmwareNames -join ', ')"
}
$manifestBody | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$zipPath = Join-Path $outputDir "septronics_${mode}_drive_package_${timestamp}.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$zipInputs = @($apkOutput, $manifestPath)
if ($isRelease -and $releaseFirmwareFiles.Count -gt 0) {
    $zipInputs += $releaseFirmwareFiles
}

Compress-Archive -LiteralPath $zipInputs -DestinationPath $zipPath -Force

Write-Host "Created APK: $apkOutput"
Write-Host "Created manifest: $manifestPath"
Write-Host "Build workspace: $activeWorkDir"
if ($isRelease -and $releaseFirmwareFiles.Count -gt 0) {
    Write-Host "Created release firmware files:"
    foreach ($file in $releaseFirmwareFiles) {
        Write-Host "  - $file"
    }
}
Write-Host "Created zip: $zipPath"
