# released ios rejected sipment inspection

- Updated: 2026-04-29
- Branch: codex-add-sales-related-documents
- Target app: ScepTRONIC app (iOS Release/TestFlight)

## Background
Android側では shipment inspection 由来の機能と表記の削除を進めているが、iOS側には同等の残存がある。
TestFlight アップロード前に iOS 側も公開用構成へ統一する。

## Goal
公開用 iOS ビルドから shipment inspection 固有の導線・文言・権限・レポート出力を除去し、ScepTRONIC として提出可能な状態にする。

## Deletion scope (iOS)

### 1) iOS metadata / app name
- File: `app/ios/Runner/Info.plist`
- Replace:
  - `CFBundleDisplayName` = `Shipment Inspection` -> `ScepTRONIC`
  - `CFBundleName` = `shipment_inspection` -> `ScepTRONIC` (or approved product name)
- Review Bluetooth/Local Network usage strings and remove shipment-inspection-specific wording.

### 2) App entry and navigation
- File: `app/lib/main.dart`
  - Replace app title `Android Shipment Inspection` with release title.
- File: `app/lib/screens/app_root.dart`
  - Remove import of `shipment_inspection_screen.dart`.
  - Remove `AppStage.shipment` and shipment-only routing.
  - Route startup flow to release UI flow.

### 3) Shipment inspection feature code
- Remove references from release target:
  - `app/lib/screens/shipment_inspection_screen.dart`
  - `app/lib/ble/shipment_inspection_controller.dart`
- If full deletion is difficult before release, isolate this feature behind a non-release flag and ensure Release build cannot open it.

### 4) Shipment report artifacts
- In shipment controller, remove/disable shipment-specific report outputs:
  - `shipment_report_*.json`
  - `shipment_report_steps_*.csv`
  - `shipment_reports` directory generation

### 5) Permissions / capabilities
- If Release版で Local Network を使用しない場合、`NSLocalNetworkUsageDescription` を削除。
- Ensure only required permissions remain for release behavior.

### 6) Keyword cleanup
Run full-project search and remove release-visible occurrences:
- `shipment`
- `inspection`
- `shipment_inspection`
- `Shipment Inspection`
- `出荷検査`

## Acceptance criteria
- `Runner` target (Release) shows release Bundle ID/Team and no shipment-inspection naming.
- iOS app launch path does not enter shipment inspection screen.
- No shipment-inspection text is visible in app name, UI labels, or review-facing metadata.
- If Local Network is unused in Release, no Local Network permission prompt appears.
- TestFlight build installs and boots as ScepTRONIC release flow.

## Notes
- This document defines iOS-side removal requirements only.
- Android-side removal status is managed separately.
