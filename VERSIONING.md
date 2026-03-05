# Versioning

This repository keeps app and firmware versions in tracked files, and uses Git tags for releases.

## Source of truth

- Android app: `ble_led_app/pubspec.yaml`
  - Use Flutter's standard `version: x.y.z+build` format.
  - Example: `0.1.0+1`
- Firmware: `arduino/firmware_versions.h`
  - `FW_VERSION_ALERT_LED` for `arduino/xiao_mg24_ble_alert_led.ino`
  - `FW_VERSION_D9_FRONT` for `arduino/xiao_mg24_ble_d9_front.ino`

## Tag convention

- Android app: `app/v0.1.0+1`
- Firmware alert LED: `fw/alert-led/v0.1.0`
- Firmware D9 front: `fw/d9-front/v0.1.0`

## Recommended workflow

1. Update the version in the tracked file.
2. Commit the version bump.
3. Create an annotated tag for the release.
4. Push the branch and tags.

Example:

```powershell
git add ble_led_app/pubspec.yaml arduino/firmware_versions.h
git commit -m "chore: bump app and firmware versions"
git tag -a app/v0.1.0+1 -m "Android app 0.1.0+1"
git tag -a fw/alert-led/v0.1.0 -m "Firmware alert LED 0.1.0"
git push origin main --follow-tags
```

## Helper scripts

- `scripts/show_versions.ps1`
  - Shows the current app and firmware versions from the tracked files.
- `scripts/new_release_tag.ps1 -Target <app|alert-led|d9-front>`
  - Creates the annotated tag that matches the current tracked version.
- `scripts/set_versions.ps1`
  - Updates app and firmware version values in one step.
