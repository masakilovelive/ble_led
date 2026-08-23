[CmdletBinding()]
param(
  [ValidateSet('build', 'upload', 'ports', 'monitor', 'send', 'console')]
  [string]$Action = 'build',

  [string]$SketchPath = 'arduino/x9c103s_controller/x9c103s_controller.ino',

  [string]$Port = $env:ARDUINO_PORT,

  [string]$BuildRoot = '.arduino-build',

  [int]$Baud = 115200,

  [int]$DurationSeconds = 0,

  [string]$CommandText = '',

  [switch]$VerboseBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkspaceRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-LatestInstalledDir {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    throw "Required path was not found: $Path"
  }

  $dir = Get-ChildItem -Path $Path -Directory | Sort-Object Name -Descending | Select-Object -First 1
  if (-not $dir) {
    throw "No installed directories were found under: $Path"
  }

  return $dir.FullName
}

function Ensure-Dir {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Invoke-LoggedCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Exe,

    [Parameter(Mandatory = $true)]
    [string[]]$Args,

    [switch]$Quiet
  )

  if (-not $Quiet) {
    Write-Host ''
    Write-Host ('> ' + $Exe + ' ' + ($Args -join ' '))
  }

  $savedErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $rawOutput = @(& $Exe @Args 2>&1)
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $savedErrorActionPreference
  }

  $output = @($rawOutput | ForEach-Object { $_.ToString() })
  if ($exitCode -ne 0) {
    if ($Quiet) {
      Write-Host ''
      Write-Host ('> ' + $Exe + ' ' + ($Args -join ' '))
    }
    if ($output.Count -gt 0) {
      $output | Out-Host
    }
    throw "Command failed with exit code ${exitCode}: $Exe"
  }

  if ((-not $Quiet) -and $output.Count -gt 0) {
    $output | Out-Host
  }

  return $output
}

function Get-Toolchain {
  $arduinoData = Join-Path $env:LOCALAPPDATA 'Arduino15'
  $hardwarePath = Get-LatestInstalledDir -Path (Join-Path $arduinoData 'packages/arduino/hardware/avr')
  $avrGccPath = Get-LatestInstalledDir -Path (Join-Path $arduinoData 'packages/arduino/tools/avr-gcc')
  $avrdudePath = Get-LatestInstalledDir -Path (Join-Path $arduinoData 'packages/arduino/tools/avrdude')

  return @{
    HardwarePath = $hardwarePath
    CorePath = Join-Path $hardwarePath 'cores/arduino'
    VariantPath = Join-Path $hardwarePath 'variants/standard'
    AvrGccBin = Join-Path $avrGccPath 'bin'
    AvrdudePath = $avrdudePath
  }
}

function Get-SerialPorts {
  $ports = @()

  foreach ($item in @(Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue)) {
    if ($null -eq $item) {
      continue
    }

    $ports += [pscustomobject]@{
      Port = $item.DeviceID
      Caption = $item.Caption
      PnpDeviceId = $item.PNPDeviceID
    }
  }

  if ($ports.Count -eq 0) {
    foreach ($portName in @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object)) {
      if ([string]::IsNullOrWhiteSpace($portName)) {
        continue
      }

      $ports += [pscustomobject]@{
        Port = $portName
        Caption = ''
        PnpDeviceId = ''
      }
    }
  }

  $ports = @($ports | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace($_.Port) } | Sort-Object Port -Unique)
  return $ports
}

function Show-Ports {
  $ports = @(Get-SerialPorts)
  if ($ports.Count -eq 0) {
    Write-Host 'No serial ports were detected.'
    return
  }

  Write-Host 'Detected serial ports:'
  foreach ($item in $ports) {
    $label = if ([string]::IsNullOrWhiteSpace($item.Caption)) { $item.Port } else { "$($item.Port)  $($item.Caption)" }
    Write-Host ('  ' + $label)
  }
}

function Resolve-UploadPort {
  param(
    [string]$RequestedPort
  )

  $ports = @(Get-SerialPorts)
  if ($ports.Count -eq 0) {
    throw 'No serial ports were detected. Connect the board and try again.'
  }

  if (-not [string]::IsNullOrWhiteSpace($RequestedPort)) {
    $match = $ports | Where-Object { $_.Port -ieq $RequestedPort } | Select-Object -First 1
    if (-not $match) {
      Show-Ports
      throw "The requested port was not found: $RequestedPort"
    }
    return $match.Port
  }

  $preferred = @(
    $ports | Where-Object {
      $_.Caption -match 'Arduino|CH340|CH341|USB-SERIAL|USB Serial|CP210|wchusbserial|wch\.cn' -or
      $_.PnpDeviceId -match 'VID_2341|VID_2A03|VID_1A86|VID_10C4'
    }
  )

  if ($preferred.Count -eq 1) {
    return $preferred[0].Port
  }

  if ($ports.Count -eq 1) {
    return $ports[0].Port
  }

  Show-Ports
  throw 'Multiple serial ports were detected. Set ARDUINO_PORT=COMx and rerun the upload task.'
}

function Get-BuildLayout {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,

    [Parameter(Mandatory = $true)]
    [string]$SketchFile,

    [Parameter(Mandatory = $true)]
    [string]$BuildRootPath
  )

  $projectName = [System.IO.Path]::GetFileNameWithoutExtension($SketchFile)
  $projectBuildDir = Join-Path $BuildRootPath $projectName
  $objectDir = Join-Path $projectBuildDir 'obj'
  $coreObjDir = Join-Path $objectDir 'core'
  $variantObjDir = Join-Path $objectDir 'variant'
  $sketchObjDir = Join-Path $objectDir 'sketch'

  Ensure-Dir -Path $BuildRootPath
  Ensure-Dir -Path $projectBuildDir
  Ensure-Dir -Path $objectDir
  Ensure-Dir -Path $coreObjDir
  Ensure-Dir -Path $variantObjDir
  Ensure-Dir -Path $sketchObjDir

  return @{
    ProjectName = $projectName
    ProjectBuildDir = $projectBuildDir
    CoreObjDir = $coreObjDir
    VariantObjDir = $variantObjDir
    SketchObjDir = $sketchObjDir
    CoreArchive = Join-Path $projectBuildDir 'core.a'
    ElfFile = Join-Path $projectBuildDir ($projectName + '.elf')
    HexFile = Join-Path $projectBuildDir ($projectName + '.hex')
    SketchObject = Join-Path $sketchObjDir ($projectName + '.o')
  }
}

function Get-SourceFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return @(Get-ChildItem -Path $Path -File | Where-Object { $_.Extension -in @('.c', '.cpp', '.S') } | Sort-Object Name)
}

function Compile-SourceFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Compiler,

    [Parameter(Mandatory = $true)]
    [string[]]$BaseArgs,

    [Parameter(Mandatory = $true)]
    [string]$SourceFile,

    [Parameter(Mandatory = $true)]
    [string]$ObjectFile,

    [string[]]$ExtraArgs = @(),

    [switch]$Quiet
  )

  $args = @($BaseArgs) + @($ExtraArgs) + @($SourceFile, '-o', $ObjectFile)
  Invoke-LoggedCommand -Exe $Compiler -Args $args -Quiet:$Quiet | Out-Null
}

function Build-Sketch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SketchPathValue
  )

  $workspaceRoot = Get-WorkspaceRoot
  $toolchain = Get-Toolchain
  $resolvedSketch = (Resolve-Path (Join-Path $workspaceRoot $SketchPathValue)).Path
  $layout = Get-BuildLayout -WorkspaceRoot $workspaceRoot -SketchFile $resolvedSketch -BuildRootPath (Join-Path $workspaceRoot $BuildRoot)

  $avrGcc = Join-Path $toolchain.AvrGccBin 'avr-gcc.exe'
  $avrGpp = Join-Path $toolchain.AvrGccBin 'avr-g++.exe'
  $avrAr = Join-Path $toolchain.AvrGccBin 'avr-gcc-ar.exe'
  $avrObjcopy = Join-Path $toolchain.AvrGccBin 'avr-objcopy.exe'
  $avrSize = Join-Path $toolchain.AvrGccBin 'avr-size.exe'

  $buildMcu = 'atmega328p'
  $buildFcpu = '16000000L'
  $commonDefines = @(
    "-mmcu=$buildMcu",
    "-DF_CPU=$buildFcpu",
    '-DARDUINO=10819',
    '-DARDUINO_AVR_UNO',
    '-DARDUINO_ARCH_AVR'
  )
  $commonIncludes = @(
    "-I$($toolchain.CorePath)",
    "-I$($toolchain.VariantPath)"
  )
  $cppBaseArgs = @(
    '-c',
    '-g',
    '-Os',
    '-w',
    '-std=gnu++11',
    '-fpermissive',
    '-fno-exceptions',
    '-ffunction-sections',
    '-fdata-sections',
    '-fno-threadsafe-statics',
    '-Wno-error=narrowing',
    '-MMD',
    '-flto'
  ) + $commonDefines + $commonIncludes
  $cBaseArgs = @(
    '-c',
    '-g',
    '-Os',
    '-w',
    '-std=gnu11',
    '-ffunction-sections',
    '-fdata-sections',
    '-MMD',
    '-flto',
    '-fno-fat-lto-objects'
  ) + $commonDefines + $commonIncludes
  $sBaseArgs = @(
    '-c',
    '-g',
    '-x',
    'assembler-with-cpp',
    '-flto',
    '-MMD'
  ) + $commonDefines + $commonIncludes

  $coreSources = Get-SourceFiles -Path $toolchain.CorePath
  $variantSources = Get-SourceFiles -Path $toolchain.VariantPath

  $archiveObjects = New-Object System.Collections.Generic.List[string]
  $quietBuild = -not $VerboseBuild

  Write-Host '[BUILD] Compiling Arduino core...'

  foreach ($source in $coreSources) {
    $objectFile = Join-Path $layout.CoreObjDir ($source.Name + '.o')
    switch ($source.Extension) {
      '.cpp' { Compile-SourceFile -Compiler $avrGpp -BaseArgs $cppBaseArgs -SourceFile $source.FullName -ObjectFile $objectFile -Quiet:$quietBuild }
      '.c' { Compile-SourceFile -Compiler $avrGcc -BaseArgs $cBaseArgs -SourceFile $source.FullName -ObjectFile $objectFile -Quiet:$quietBuild }
      '.S' { Compile-SourceFile -Compiler $avrGcc -BaseArgs $sBaseArgs -SourceFile $source.FullName -ObjectFile $objectFile -Quiet:$quietBuild }
    }
    $archiveObjects.Add($objectFile)
  }

  Write-Host '[BUILD] Compiling variant files...'
  foreach ($source in $variantSources) {
    $objectFile = Join-Path $layout.VariantObjDir ($source.Name + '.o')
    switch ($source.Extension) {
      '.cpp' { Compile-SourceFile -Compiler $avrGpp -BaseArgs $cppBaseArgs -SourceFile $source.FullName -ObjectFile $objectFile -Quiet:$quietBuild }
      '.c' { Compile-SourceFile -Compiler $avrGcc -BaseArgs $cBaseArgs -SourceFile $source.FullName -ObjectFile $objectFile -Quiet:$quietBuild }
      '.S' { Compile-SourceFile -Compiler $avrGcc -BaseArgs $sBaseArgs -SourceFile $source.FullName -ObjectFile $objectFile -Quiet:$quietBuild }
    }
    $archiveObjects.Add($objectFile)
  }

  Write-Host '[BUILD] Compiling sketch...'
  Compile-SourceFile -Compiler $avrGpp -BaseArgs $cppBaseArgs -SourceFile $resolvedSketch -ObjectFile $layout.SketchObject -ExtraArgs @('-x', 'c++') -Quiet:$quietBuild

  if (Test-Path $layout.CoreArchive) {
    Remove-Item -Path $layout.CoreArchive -Force
  }
  Write-Host '[BUILD] Archiving core...'
  Invoke-LoggedCommand -Exe $avrAr -Args (@('rcs', $layout.CoreArchive) + $archiveObjects.ToArray()) -Quiet:$quietBuild | Out-Null

  $linkArgs = @(
    '-w',
    '-Os',
    '-g',
    '-flto',
    '-fuse-linker-plugin',
    '-Wl,--gc-sections',
    "-mmcu=$buildMcu",
    '-o',
    $layout.ElfFile,
    $layout.SketchObject,
    $layout.CoreArchive,
    '-L' + $layout.ProjectBuildDir,
    '-lm'
  )
  Write-Host '[BUILD] Linking...'
  Invoke-LoggedCommand -Exe $avrGcc -Args $linkArgs -Quiet:$quietBuild | Out-Null

  Write-Host '[BUILD] Generating HEX...'
  Invoke-LoggedCommand -Exe $avrObjcopy -Args @('-O', 'ihex', '-R', '.eeprom', $layout.ElfFile, $layout.HexFile) -Quiet:$quietBuild | Out-Null

  $sizeOutput = Invoke-LoggedCommand -Exe $avrSize -Args @('-C', "--mcu=$buildMcu", $layout.ElfFile) -Quiet
  if ($sizeOutput.Count -gt 0) {
    Write-Host '[BUILD] Size summary:'
    $sizeOutput | Out-Host
  }

  Write-Host ''
  Write-Host ('[OK] Build completed: ' + $layout.HexFile)

  return [pscustomobject]@{
    Layout = $layout
    Toolchain = $toolchain
  }
}

function Upload-Sketch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SketchPathValue,

    [string]$RequestedPort
  )

  $buildResult = Build-Sketch -SketchPathValue $SketchPathValue
  $layout = $buildResult.Layout
  $toolchain = $buildResult.Toolchain

  $resolvedPort = Resolve-UploadPort -RequestedPort $RequestedPort
  $avrdude = Join-Path $toolchain.AvrdudePath 'bin/avrdude.exe'
  $avrdudeConf = Join-Path $toolchain.AvrdudePath 'etc/avrdude.conf'

  Push-Location $layout.ProjectBuildDir
  try {
    Invoke-LoggedCommand -Exe $avrdude -Args @(
      "-C$avrdudeConf",
      '-patmega328p',
      '-carduino',
      "-P$resolvedPort",
      '-b115200',
      '-D',
      "-Uflash:w:$($layout.ProjectName).hex:i"
    )
  }
  finally {
    Pop-Location
  }

  Write-Host ''
  Write-Host ("[OK] Upload completed on $resolvedPort")
}

function Start-SerialMonitor {
  param(
    [string]$RequestedPort,
    [int]$BaudRate = 115200,
    [int]$ReadDurationSeconds = 0
  )

  $resolvedPort = Resolve-UploadPort -RequestedPort $RequestedPort
  $serial = New-Object System.IO.Ports.SerialPort $resolvedPort, $BaudRate, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
  $serial.ReadTimeout = 200
  $serial.WriteTimeout = 200
  $serial.NewLine = "`n"
  $serial.DtrEnable = $true
  $serial.RtsEnable = $false

  Write-Host ("[MONITOR] Opening $resolvedPort at ${BaudRate} baud")
  if ($ReadDurationSeconds -le 0) {
    Write-Host '[MONITOR] Press Ctrl+C to stop.'
  } else {
    Write-Host ("[MONITOR] Capturing for $ReadDurationSeconds seconds.")
  }

  try {
    $serial.Open()
  }
  catch [System.UnauthorizedAccessException] {
    throw "Access to $resolvedPort was denied. Close any app using the port, or use the X9C Console task as the only active serial session."
  }
  try {
    $serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 300

    $deadline = if ($ReadDurationSeconds -gt 0) { (Get-Date).AddSeconds($ReadDurationSeconds) } else { $null }
    while ($true) {
      if ($deadline -and (Get-Date) -ge $deadline) {
        break
      }

      $chunk = $serial.ReadExisting()
      if (-not [string]::IsNullOrEmpty($chunk)) {
        Write-Host -NoNewline $chunk
        continue
      }

      Start-Sleep -Milliseconds 50
    }

    $tail = $serial.ReadExisting()
    if (-not [string]::IsNullOrEmpty($tail)) {
      Write-Host -NoNewline $tail
    }
  }
  finally {
    if ($serial.IsOpen) {
      $serial.Close()
    }
  }

  Write-Host ''
  Write-Host ("[MONITOR] Closed $resolvedPort")
}

function New-SerialConnection {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ResolvedPort,

    [int]$BaudRate = 115200,

    [bool]$EnableDtr = $true
  )

  $serial = New-Object System.IO.Ports.SerialPort $ResolvedPort, $BaudRate, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
  $serial.ReadTimeout = 200
  $serial.WriteTimeout = 200
  $serial.NewLine = "`n"
  $serial.DtrEnable = $EnableDtr
  $serial.RtsEnable = $false
  return $serial
}

function Send-SerialCommand {
  param(
    [string]$RequestedPort,
    [string]$Command,
    [int]$BaudRate = 115200,
    [int]$ReadDurationSeconds = 2
  )

  if ([string]::IsNullOrWhiteSpace($Command)) {
    throw 'CommandText is required for the send action.'
  }

  $resolvedPort = Resolve-UploadPort -RequestedPort $RequestedPort
  $serial = New-SerialConnection -ResolvedPort $resolvedPort -BaudRate $BaudRate -EnableDtr $false

  Write-Host ("[SEND] Opening $resolvedPort at ${BaudRate} baud")
  try {
    $serial.Open()
  }
  catch [System.UnauthorizedAccessException] {
    throw "Access to $resolvedPort was denied. Close any app using the port. If you need monitor plus input together, use the X9C Console task."
  }
  try {
    Start-Sleep -Milliseconds 300
    $serial.DiscardInBuffer()

    Write-Host ("[SEND] > $Command")
    $serial.WriteLine($Command)

    $deadline = (Get-Date).AddSeconds([Math]::Max($ReadDurationSeconds, 1))
    while ((Get-Date) -lt $deadline) {
      $chunk = $serial.ReadExisting()
      if (-not [string]::IsNullOrEmpty($chunk)) {
        Write-Host -NoNewline $chunk
      } else {
        Start-Sleep -Milliseconds 50
      }
    }

    $tail = $serial.ReadExisting()
    if (-not [string]::IsNullOrEmpty($tail)) {
      Write-Host -NoNewline $tail
    }
  }
  finally {
    if ($serial.IsOpen) {
      $serial.Close()
    }
  }

  Write-Host ''
  Write-Host ("[SEND] Closed $resolvedPort")
}

function Start-InteractiveSerialConsole {
  param(
    [string]$RequestedPort,
    [int]$BaudRate = 115200
  )

  if ([Console]::IsInputRedirected) {
    throw 'Interactive console requires a terminal. Run it from the VS Code integrated terminal task.'
  }

  $resolvedPort = Resolve-UploadPort -RequestedPort $RequestedPort
  $serial = New-SerialConnection -ResolvedPort $resolvedPort -BaudRate $BaudRate -EnableDtr $true

  Write-Host ("[CONSOLE] Opening $resolvedPort at ${BaudRate} baud")
  Write-Host '[CONSOLE] Type a command and press Enter. Stop with Ctrl+C.'

  try {
    $serial.Open()
  }
  catch [System.UnauthorizedAccessException] {
    throw "Access to $resolvedPort was denied. Close any other serial monitor or uploader that is using the port."
  }
  try {
    Start-Sleep -Milliseconds 400

    $buffer = ''
    while ($true) {
      $chunk = $serial.ReadExisting()
      if (-not [string]::IsNullOrEmpty($chunk)) {
        Write-Host -NoNewline $chunk
      }

      while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)

        if ($key.Key -eq [ConsoleKey]::Enter) {
          Write-Host ''
          $serial.WriteLine($buffer)
          $buffer = ''
          continue
        }

        if ($key.Key -eq [ConsoleKey]::Backspace) {
          if ($buffer.Length -gt 0) {
            $buffer = $buffer.Substring(0, $buffer.Length - 1)
            Write-Host -NoNewline "`b `b"
          }
          continue
        }

        if ($key.Key -eq [ConsoleKey]::Escape) {
          while ($buffer.Length -gt 0) {
            $buffer = $buffer.Substring(0, $buffer.Length - 1)
            Write-Host -NoNewline "`b `b"
          }
          continue
        }

        if ([int]$key.KeyChar -gt 0) {
          $buffer += $key.KeyChar
          Write-Host -NoNewline $key.KeyChar
        }
      }

      Start-Sleep -Milliseconds 25
    }
  }
  finally {
    if ($serial.IsOpen) {
      $serial.Close()
    }
  }
}

switch ($Action) {
  'ports' {
    Show-Ports
  }
  'build' {
    Build-Sketch -SketchPathValue $SketchPath | Out-Null
  }
  'upload' {
    Upload-Sketch -SketchPathValue $SketchPath -RequestedPort $Port
  }
  'monitor' {
    Start-SerialMonitor -RequestedPort $Port -BaudRate $Baud -ReadDurationSeconds $DurationSeconds
  }
  'send' {
    Send-SerialCommand -RequestedPort $Port -Command $CommandText -BaudRate $Baud -ReadDurationSeconds $DurationSeconds
  }
  'console' {
    Start-InteractiveSerialConsole -RequestedPort $Port -BaudRate $Baud
  }
}
