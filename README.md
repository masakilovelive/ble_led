# ScepTRONIC

ScepTRONIC BLE LED製品のアプリ、製品ファームウェア、製造・出荷検査資料を管理する製品専用ブランチです。

## 製品ID

- 表示名: `ScepTRONIC`
- 現在のAndroidソース: `com.masacookie.sceptronic`
- 現在のiOS/macOSソース: `com.masacookie.sceptronic`
- 2026-04-27配布Android APK: `com.masacookie.septronics`
- App Store提出記録: `com.FAE.ScepTRONIC`
- Flutter version: `0.1.4+5`

最新の正式アプリ情報は現在ソースを基準とし、Android/iOSともに `com.masacookie.sceptronic` を採用します。配布済みAPKと過去のApp Store提出記録にある別IDは、変更履歴の確認用として資料に残しています。

## ディレクトリ

- `app/`: Flutterアプリと配布パッケージ作成ツール
- `app/ver1_esp32c3_stock1/`: ESP32-C3製品ファームウェア
- `app/ver1_esp32c3_stock2/`: C3 Stock B用デバイス名ラッパー
- `app/ver1_esp32c6_stock1/`: ESP32-C6製品ファームウェア
- `app/ver1_esp32c6_stock2/`: C6 Stock B用デバイス名ラッパー
- `docs/engineering/`: 開発・耐久・出荷検査仕様
- `docs/store/`: App Store / Google Play提出・サポート資料
- `manufacturing/firmware/`: UNO出荷検査・耐久試験治具
- `manufacturing/tools/`: MCUシリアルブリッジとUNO補助ツール

## アプリ検証

```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=SEPTRONICS_RELEASE_BUILD=0
```

## 配布パッケージ

リポジトリルートから実行します。

```powershell
powershell -ExecutionPolicy Bypass -File app\tools\build_drive_package.ps1 -BuildMode debug
powershell -ExecutionPolicy Bypass -File app\tools\build_drive_package.ps1 -BuildMode release
```

生成されるAPK、zip、署名情報、FlutterキャッシュはGit管理しません。

## 旧開発資産

`ble_led_app`、`ble_led_endurance_app`、`ski_led_app`、試作Python GUI、研究用コード、Loreley、DAQ関連は製品ソースではないため、このブランチには含めません。旧履歴は既存の `main` と `septronics-consolidated-20260425` ブランチに残します。
