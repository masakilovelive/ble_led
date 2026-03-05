# Flutter BLE Template Overlay (0x2A06 LED)

既存の Flutter アプリに **0x2A06 Alert Level LED コントロール機能** を素早く追加するためのオーバーレイ一式です。  
WS2812 LED を搭載した XIAO MG24 ファームウェアと組み合わせることを想定しています。

---

## 適用手順（新規プロジェクトに上書きする場合）
1. Flutter SDK をセットアップし、空プロジェクトを作成します。
   ```bash
   flutter create ble_led_app
   cd ble_led_app
   ```
2. 本テンプレートを展開し、`lib/`, `pubspec.yaml`, `android/`, `ios/` などをプロジェクト直下に **上書きコピー** します。
3. 依存関係を取得します。
   ```bash
   flutter pub get
   ```
4. 各プラットフォームの権限設定を反映します。
   - **Android**: `android/manifest_patch.txt` の内容を参考に `AndroidManifest.xml` を編集します。
   - **iOS**: `ios/info_plist_patch.txt` の内容を `Info.plist` に追加します。
5. 実機を接続し、動作確認します。
   ```bash
   flutter run
   ```

> 既存プロジェクトへ取り込む場合も同様に、必要なファイルをマージし権限設定を追加してください。

---

## 含まれる主な機能
- BLE スキャンとデバイス一覧表示（`lib/screens/scan_screen.dart`）
- 任意デバイスへの接続／切断管理（`lib/ble/connection_controller.dart`）
- GATT サービス／キャラクタリスティック一覧表示（`lib/screens/device_detail_screen.dart`）
- Immediate Alert サービス 0x1802 → Alert Level (0x2A06) への書き込みボタン（OFF / Mild / High）

---

## カスタマイズポイント
- `lib/env.dart`  
  - `nameHint`: スキャン一覧フィルタに利用。デフォルトは `"XIAO"`。
  - `serviceUuid`, `alertLevelUuid`: 接続後に探索するサービス／キャラ UUID。
- UI やルーティングは `lib/screens/` と `lib/router.dart` を編集してください。
- 他の UUID を追加したい場合は `lib/ble/led_controller.dart` を拡張します。

---

## 利用上の注意
- BLE はエミュレータで動作しません。必ず実機でテストしてください。
- Android 12 以降では `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` などのランタイム権限が必要です。
- iOS では MAC アドレスを取得できないため、UUID ベースでデバイスを識別してください。
- ファームウェア側で Alert Level (0x2A06) を処理する実装が行われていることが前提です。

---

## ディレクトリ構成（抜粋）
```
flutter_ble_template_overlay/
├─ lib/
│  ├─ ble/                  # BLE ロジック (scan, connection, command)
│  ├─ screens/              # 画面 UI
│  ├─ env.dart              # UUID / 名前ヒント設定
│  └─ main.dart             # エントリーポイント
├─ android/                 # AndroidManifest パッチ用ファイルを同梱
├─ ios/                     # Info.plist パッチ用ファイルを同梱
└─ pubspec.yaml             # 必要ライブラリ (flutter_reactive_ble 等)
```

---

テンプレートをベースに、UI のカスタマイズや追加キャラクタリスティックの制御などを自由に拡張してください。
