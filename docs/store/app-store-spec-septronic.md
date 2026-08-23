# ScepTRONIC iOS アプリ概要（App Store 提出用）

最終更新日: 2026-04-30  
対象アプリ: `ScepTRONIC`  
iOS bundle identifier（現行コード）: `com.masacookie.sceptronic`
対象バージョン: `0.1.4+5`

## 1. アプリの目的

`ScepTRONIC` は、専用 BLE LED デバイス（Stock A / Stock B）を iPhone / iPad から検出・接続し、発光状態を制御するためのアプリです。  
主用途は、LED デバイスの運用設定（色、明るさ、演出切替）と接続状態・電池状態の確認です。

## 2. 対応環境と前提

- iOS 13.0 以上（`Podfile` 設定）
- iPhone / iPad（現行プロジェクトは `TARGETED_DEVICE_FAMILY = "1,2"`）
- BLE 対応端末
- 専用 BLE デバイス（主にデバイス名に `XIAO` を含む機器を検出）
- BLE 利用時は端末側の Bluetooth 有効化と権限許可が必要

## 3. ユーザー向け主要機能

### 3-1. 初期セットアップ（Bluetooth Setting）

- 周辺 BLE デバイスをスキャン
- 検出デバイスを `STOCK A` / `STOCK B` に割り当て
- 割り当てルール:
  - 末尾番号の奇数を A、偶数を B として扱う
  - A/B は同じペア番号であることを検証
- A/B の接続・切断、全体接続・全体切断、Auto reconnect 設定

### 3-2. LED 制御（Stock Select / LED Setting）

- Stock A / Stock B ごとの制御
- `BOTH SYNCRO` による A/B 同期制御
- 制御内容:
  - 固定色（Head/Tip 個別）
  - 明るさ（0-255）
  - Heart Beat 演出（速度プリセット）
  - Rainbow 演出（開始/停止）

### 3-3. 接続安定化

- 接続状態監視（connected / connecting / disconnected）
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

## 5. iOS 権限と用途

### 5-1. `NSBluetoothAlwaysUsageDescription`

- BLE デバイスの検出・接続・制御のために使用

### 5-2. `NSBluetoothPeripheralUsageDescription`

- BLE 接続時の互換運用のために保持

### 5-3. `NSLocalNetworkUsageDescription`

- ローカルネットワーク経由の MCU bridge 接続時のみ使用
- 通常の BLE 制御機能はインターネット接続なしで利用可能

## 6. データの取り扱い

### 6-1. 端末内に保存する情報

- A/B に割り当てたデバイス ID / 名称
- Auto reconnect 設定
- LED UI 設定（色、明るさ、演出モード等）

保存先はアプリ内部ストレージ（`app_state.json` など）で、端末外への自動送信は行いません。

### 6-2. 一時的に扱う情報

- スキャン結果（デバイス名、ID、RSSI）
- 接続状態
- バッテリー電圧と充電状態

## 7. 外部送信・第三者提供

- ユーザー登録機能: なし
- 広告 SDK: なし
- 外部解析 SDK（Firebase Analytics 等）: なし
- 取得データの第三者提供: なし（法令要請時を除く）

## 8. App Store 審査向け補足

- 本アプリは専用 BLE ハードウェア制御アプリであり、ハードウェア非接続時は一部機能が利用できません。
- ログイン不要で基本機能を使用可能です。
- `SEPTRONICS_RELEASE_BUILD=1` 前提で、検査/デバッグ向け UI を無効化した提出構成を想定します。
- Bundle ID は現行コードで `com.masacookie.sceptronic` です。

## 9. 問い合わせ先

- 事業者名: `Fortuna Advanced Engineering`
- 連絡先: `fae.info@faeosaka.com`
