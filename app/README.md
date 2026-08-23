# ScepTRONIC app

Consolidated Flutter app for the Sceptronic BLE stock-control workflow.

## Release Identity

- App display name: `ScepTRONIC`
- Android package name: `com.masacookie.sceptronic`
- iOS/macOS bundle id: `com.masacookie.sceptronic`

This is the canonical Flutter app for the ScepTRONIC product and includes:

- Sceptronic UI screens and branding assets
- iPhone permission and Info.plist updates
- stock controller, endurance, shipment inspection, and stress lab flows
- bundled `ver1_esp32c3_stock1` and `ver1_esp32c6_stock1` firmware folders

## Google Drive Distribution

Build shipment/debug package (keeps inspection/debug sources):

```powershell
powershell -ExecutionPolicy Bypass -File app\tools\build_drive_package.ps1 -BuildMode debug
```

Build release package (debug/inspection sources removed from build workspace):

```powershell
powershell -ExecutionPolicy Bypass -File app\tools\build_drive_package.ps1 -BuildMode release
```

Generated files (`debug` / `release` depending on `-BuildMode`):

- `app/dist/septronics_<mode>.apk`
- `app/dist/septronics_<mode>_drive_manifest.txt`
- `app/dist/septronics_<mode>_drive_package_<timestamp>.zip`
- `app/dist/firmware_release/*.ino` (release mode only, `SEPTRONICS_RELEASE_BUILD=1`)

Install to a connected Android device:

```powershell
powershell -ExecutionPolicy Bypass -File app\tools\install_app.ps1 -BuildMode release -Launch
```
