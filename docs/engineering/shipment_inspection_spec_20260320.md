# 出荷検査仕様 2026-03-20

## 1. 目的

本書は BLE LED 製品の出荷検査仕様をまとめたものである。  
現行の基準実装は Android の `app/` だが、iPhone 実装時も同じ検査順、判定基準、記録項目を維持することを前提とする。

## 2. 対象と前提

- 対象機は Stock A / Stock B の 2 台構成を基本とする。
- BLE 接続、LED 制御、battery 読み取り、再接続確認を出荷判定の対象とする。
- `MCU Runner` を使う運用を標準とし、再起動相当試験は MCU power cycle で実施する。
- `acceleration` は対象機種でのみ実施する。非対応機種では `SKIP` を許容する。
- 外観検査と一部の機能確認は検査員の目視判定を含む。

## 3. 開始前条件

検査開始前に以下を満たしていること。

- Android 端末で `Bluetooth Scan`、`Bluetooth Connect`、`Location` 権限が許可されていること
- Bluetooth Setup で A/B デバイスが登録済みであること
- A/B の pair number が一致していること
- 奇数番号が A、偶数番号が B の役割定義に一致していること
- `MCU Runner` を使う場合、bridge の host / port が有効、または USB OTG で MCU が見えていること

## 4. 標準設定値

現行実装のデフォルト値は以下とする。

| 項目 | 既定値 | 備考 |
| --- | --- | --- |
| 接続タイムアウト | 6 秒 | 初回接続、再接続共通 |
| 接続再試行回数 | 1 回 | scan / connect の再試行 |
| RSSI 下限 | -90 dBm | A/B の両方に適用 |
| MCU boot settle | 3000 ms | `boot` 後の待機時間 |
| battery 下限 | 1.6 V | `Env.batteryMinV` |
| 最低起動電圧判定値 | 1.6 V | 初期値。実運用で固定可 |
| MCU Runner 必須 | ON | 標準運用 |
| GATT 確認 | ON | 接続後の discover を含む |
| acceleration 検査 | ON | 非対応機種は `SKIP` 可 |

## 5. 検査順と判定基準

現行アプリ実装の検査順は以下の 11 項目である。

| No. | 検査項目 | 実施方式 | 内容 | 合格条件 | 記録項目 |
| --- | --- | --- | --- | --- | --- |
| 1 | BLE接続確認 | 自動 | Android で scan / connect を行い、A/B 両方への初回接続完了を確認する | 6 秒以内に接続完了、再試行 1 回以内、RSSI A/B が下限以上 | 接続時間、retry 回数、RSSI A/B |
| 2 | LED色確認 | 目視 | `R / G / B / White` を順に点灯させ、欠色がないか確認する | 4 色すべて正常点灯 | PASS / FAIL / 検査メモ |
| 3 | heartbeat確認 | 目視 | heartbeat 動作を表示する | 5 秒間連続で正常点滅 | PASS / FAIL / 検査メモ |
| 4 | rainbow確認 | 目視 | rainbow 動作を表示する | 1 サイクル以上連続動作し、色遷移が正常 | PASS / FAIL / 検査メモ |
| 5 | battery電圧読み取り | 自動 | A/B の battery 値を読み取る | 読み取り成功、A/B とも下限以上 | Battery A/B |
| 6 | アプリ再起動 | 自動 | 現行実装ではアプリ kill / relaunch ではなく `MCU power cycle` を行う | `poff -> boot -> settle` が完了すること | power cycle 結果、settle 時間 |
| 7 | 最終再接続確認 | 自動 | 再起動相当後に再接続し、`color` コマンド再送まで確認する | 再接続成功後、`color` コマンド 1 回成功 | 再接続時間、retry 回数、RSSI A/B |
| 8 | 最低起動電圧 | 目視 | 規定下限電圧条件で起動可否を確認する | 規定下限電圧で正常起動 | PASS / FAIL / SKIP / 検査メモ |
| 9 | 記録確認 | 自動 | 必須記録項目と report ID が埋まっていることを確認する | 必須項目欠落なし | report ID、app version |
| 10 | 外観検査 | 目視 | 傷、汚れ、実装異常、発光異常を確認する | 外観不良なし | PASS / FAIL / 検査メモ |
| 11 | acceleration確認 | 目視 | acceleration 機能を実行し、規定反応を確認する | 規定動作が 1 回以上正常発生、または対象外なら `SKIP` | PASS / FAIL / SKIP / 検査メモ |

## 6. 自動判定と目視判定の区分

### 自動判定

- BLE接続確認
- battery電圧読み取り
- アプリ再起動
- 最終再接続確認
- 記録確認

### 目視判定

- LED色確認
- heartbeat確認
- rainbow確認
- 最低起動電圧
- 外観検査
- acceleration確認

目視判定では `PASS / FAIL / SKIP` を検査員が入力する。  
`SKIP` は `最低起動電圧` と `acceleration確認` で使う想定とする。

## 7. 記録確認の必須項目

`記録確認` では以下を必須とする。

- `tester_name`
- `serial_no`
- `board_id`
- `fw_version`
- `app_version`
- `report_id`
- `mcu_version`

ただし `mcu_version` は `MCU Runner` を使う場合のみ必須とする。

## 8. レポート出力

検査結果はアプリの documents 配下 `shipment_reports` フォルダへ保存する。

- 詳細 JSON: `shipment_report_YYYYMMDD_HHMMSS.json`
- ステップ一覧 CSV: `shipment_report_steps_YYYYMMDD_HHMMSS.csv`

主な出力項目は以下とする。

- `report_id`
- `started_at`
- `finished_at`
- `overall_status`
- `judge`
- `failure_class`
- `failure_detail`
- `serial_no`
- `board_id`
- `lot_no`
- `tester_name`
- `fw_version`
- `mcu_version`
- `app_version`
- `note`
- `mcu_runner_required`
- `mcu_transport_mode`
- `mcu_connected`
- `mcu_endpoint`
- `ble_name_a`
- `ble_name_b`
- `mac_a`
- `mac_b`
- 各ステップの `status`, `detail`, `failure_class`, `duration_ms`, `rssi_a_dbm`, `rssi_b_dbm`, `battery_a_v`, `battery_b_v`

## 9. MCU Runner 標準運用

### 9.1 PC Bridge

Windows PC と Android を使う標準手順は以下とする。

```powershell
powershell -ExecutionPolicy Bypass -File .\manufacturing\tools\start_mcu_android_bridge.ps1 -ListPorts
powershell -ExecutionPolicy Bypass -File .\manufacturing\tools\start_mcu_android_bridge.ps1 -ComPort COM4 -ListenPort 9876
```

アプリ側は以下で接続する。

- Transport: `PC Bridge`
- Host: `127.0.0.1`
- Port: `9876`

### 9.2 Python 直起動

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:9876 tcp:9876
python .\manufacturing\tools\mcu_android_bridge.py --serial-port COM4 --baud 115200 --listen-host 127.0.0.1 --listen-port 9876
```

### 9.3 USB OTG

Android が USB host になれる場合は USB OTG 直結を許容する。  
ただし iPhone 実装では `adb reverse` に依存できないため、bridge を使う場合は iPhone から直接到達できる transport に置き換えること。

## 10. iPhone 実装時に維持する仕様

iPhone 側は別実装としても、以下は共通仕様として維持する。

- 検査順は No.1 から No.11 まで同順とする
- BLE 接続、battery、再接続確認、記録確認は自動判定とする
- LED色、heartbeat、rainbow、最低起動電圧、外観、acceleration は目視判定とする
- RSSI 下限、battery 下限、connect timeout、retry 回数は Android と同じ既定値から開始する
- レポート項目名は Android 実装と揃える
- `アプリ再起動` は単純な画面再生成ではなく、電源再投入相当の確認を行う

## 11. 未確定項目

量産運用前に以下を最終固定する。

- RSSI 下限の正式値
- battery 下限電圧の正式値
- 最低起動電圧の正式判定値
- acceleration の正式合格条件
- iPhone 側の MCU transport 方式

## 12. 参照

- `docs/engineering/shipment_inspection_draft_20260320.md`
- `docs/engineering/issue_workplan_20260318.txt`
- `app/lib/ble/shipment_inspection_controller.dart`
- `app/lib/screens/shipment_inspection_screen.dart`
