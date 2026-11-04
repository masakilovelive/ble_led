# ScepTRONIC app

Consolidated Flutter app for the Sceptronic BLE stock-control workflow.

## Release Identity

- Current release source snapshot: `0.1.6 (Build 16)` (`pubspec.yaml`: `0.1.6+16`).
- App display name: `ScepTRONIC`
- Android package name: `com.FAE.ScepTRONIC`
- iOS bundle id: `com.FAE.ScepTRONIC`
- macOS bundle id: `com.masacookie.sceptronic`

This is the canonical Flutter app for the ScepTRONIC product and includes:

- Sceptronic UI screens and branding assets
- iPhone permission and Info.plist updates
- registered Stock A/B control and automatic reconnection
- the product UI, with Demo entry points and development-only inspection screens removed
- bundled `ver1_esp32c3_stock1` and `ver1_esp32c6_stock1` firmware folders

## Google Drive Distribution

The PowerShell packaging scripts below are retained as legacy tooling. The
Build 16 iOS/Android store files were built directly from the product app, not
through the inspection/debug packaging flow. See the source/artifact record
linked below before reproducing a store release. Android signed builds require
the owner's local `android/key.properties` and keystore, which are not committed.

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

## Release documentation

- [Build 8–15 change history](docs/BUILD_8_TO_15_RELEASE_HISTORY.md)
- [Build 15 App Store / Google Play release work](docs/BUILD_15_STORE_RELEASE_WORK.md)
- [Build 16 source and artifact record](docs/BUILD_16_SOURCE_ARTIFACT_RECORD.md)
