# ScepTRONIC Android アプリ仕様説明書（Google Play 提出用）

最終更新日: 2026-08-23
対象アプリ: `ScepTRONIC`  
Android package name: `com.FAE.ScepTRONIC`
対象バージョン: `0.1.4+5`

## 1. アプリの目的

`ScepTRONIC` は、専用 BLE LED デバイス（Stock A / Stock B）を Android 端末から検出・接続し、発光状態を制御するためのアプリです。  
主な用途は、LED デバイスの運用時設定（色、明るさ、演出切替）と接続状態・電池状態の確認です。

## 2. 対応環境と前提

- Android 端末（BLE 対応必須）
- BLE デバイス（アプリ側では主にデバイス名に `XIAO` を含む機器を検出）
- BLE 機能の利用には端末側の Bluetooth 有効化と権限許可が必要

補足:

- `android.hardware.bluetooth_le` は必須機能として宣言
- `android.hardware.usb.host` は任意機能として宣言

## 3. ユーザー向け主要機能

### 3-1. 初期セットアップ（Bluetooth Setting）

- 周辺 BLE デバイスをスキャン
- 検出デバイスを `STOCK A` / `STOCK B` に割り当て
- 割り当てルール:
- 末尾番号の奇数を A、偶数を B として扱う
- A/B は同じペア番号であることを検証
- A/B の接続・切断、全体接続・全体切断、Auto reconnect 設定

### 3-2. LED 制御（Stock Setting）

- Stock A / Stock B ごとの制御
- `BOTH SYNCRO` により A/B 同期制御
- 制御内容:
- 固定色（Head/Tip 個別）
- 明るさ（0-255）
- Heart Beat 演出（速度プリセット）
- Rainbow 演出（開始/停止）

### 3-3. 接続安定化

- 接続状態の監視（connected/connecting/disconnected）
- 切断時の自動再接続（有効時）
- 再接続後の UI 状態再同期（出力 ON/OFF、輝度、色、演出モード）

### 3-4. バッテリー表示

- BLE 経由で電圧特性を読み取り
- 取得電圧からバッテリー割合を算出し UI に表示
- 接続中は定期ポーリング（10 秒間隔）

## 4. BLE 通信仕様

### 4-1. 利用サービス / Characteristic

- Alert Service: `00001802-0000-1000-8000-00805f9b34fb`
- Alert Level Char: `00002a06-0000-1000-8000-00805f9b34fb`
- ADV Service: `de8a5aac-a99b-c315-0c80-60d4cbb51001`
- ADV Command Char: `de8a5aac-a99b-c315-0c80-60d4cbb51002`
- Voltage Char: `de8a5aac-a99b-c315-0c80-60d4cbb51003`
- ACK Char: `de8a5aac-a99b-c315-0c80-60d4cbb51004`

### 4-2. ADV Command Char に送信する主なコマンド

- `0x01`: Brightness 設定
- `0x03`: Rainbow 開始（interval 指定）
- `0x04`: Rainbow 停止
- `0x06`: Accel mode ON/OFF
- `0x07`: Front color 設定
- `0x08`: Rear color 設定
- `0x09`: Output ON/OFF
- `0x0A`: Heartbeat mode 設定

## 5. Android 権限と用途

### 5-1. `BLUETOOTH_SCAN`

- 周辺 BLE デバイスの検出に使用

### 5-2. `BLUETOOTH_CONNECT`

- BLE デバイスとの接続確立、GATT 読み書きに使用

### 5-3. `ACCESS_FINE_LOCATION`

- 一部 Android バージョン / 端末仕様で BLE スキャンに必要なため要求
- 位置測位結果の取得・保存・送信は行わない

### 5-4. `INTERNET`

- アプリ本体の BLE 制御はインターネット通信なしで動作
- 本権限は、開発/検証系機能で利用する MCU bridge（ローカル接続）互換のために保持
- 本番運用で外部クラウド API への送信は想定していない

## 6. データの取り扱い

### 6-1. 端末内に保存する情報

- A/B に割り当てたデバイス ID / 名称
- Auto reconnect 設定
- LED UI 設定（色、明るさ、演出モード等）

保存先はアプリ内部ストレージ（`app_state.json` 等）で、端末外への自動送信は行いません。

### 6-2. 一時的に扱う情報

- スキャン結果（デバイス名、ID、RSSI）
- 接続状態
- バッテリー電圧と充電状態

これらは主に画面表示・制御処理に使用されます。

## 7. 外部送信・第三者提供

- ユーザー登録機能: なし
- 広告 SDK: なし
- 外部解析 SDK（Firebase Analytics 等）: なし
- 取得データの第三者提供: なし（法令要請時を除く）

## 8. Google Play 審査向け補足

- 本アプリは専用 BLE ハードウェア制御アプリであり、ハードウェア非接続時は一部機能が利用できません。
- ログイン不要で基本機能を使用可能です。
- 位置情報は BLE スキャン互換目的の権限要求のみで、位置トラッキング用途ではありません。
- 提出版 release ビルドでは `SEPTRONICS_RELEASE_BUILD=1` を指定し、検査/デバッグ向け UI は無効化した構成を前提とします。

## 9. 問い合わせ先

- 事業者名: `Fortuna Advanced Engineering`
- 連絡先: `fae.info@faeosaka.com`
