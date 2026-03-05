---
tags: [Arduino, BLE, Foam, 解説]
---

# [[arduino/xiao_mg24_ble_alert_led.ino]] 詳細解説

## 概要
- Seeed Studio XIAO MG24 向けの BLE 対応 LED コントローラーファームウェア。
- WS2812 系 LED ストリップ (8 灯) をコアテックス M33 の DWT サイクルカウンタでビットバンギング制御。
- LSM6DS3 IMU を利用した「振ると光る」ナイトライダー風エフェクトを BLE コマンドで有効化。
- Immediate Alert (0x1802) とカスタム 128-bit サービスにより、Python ツール群から明るさ・色・パターンを制御。

## BLE 制御コマンド定義
```cpp
static constexpr uint8_t CMD_SET_BRIGHTNESS = 0x01;
static constexpr uint8_t CMD_SET_COLOR      = 0x02;
static constexpr uint8_t CMD_START_RAINBOW  = 0x03;
static constexpr uint8_t CMD_STOP_RAINBOW   = 0x04;
static constexpr uint8_t CMD_ACCEL_MODE     = 0x06;
```
- `CMD_SET_BRIGHTNESS`: 2 バイト目の 0–255 がストリップ全体の輝度 (`g_brightness`)。
- `CMD_SET_COLOR`: RGB3 バイトで単色点灯 (`g_solid_color`)。虹/加速度モードは必ず停止。
- `CMD_START_RAINBOW` / `CMD_STOP_RAINBOW`: `g_rainbow_mode` をトグルして連続的な HSV->RGB 変換で彩度 100% のグラデーションを生成。
- `CMD_ACCEL_MODE`: LSM6DS3 の読み取りを有効化。接続と IMU 初期化が成功している場合にのみナイトライダーアニメを起動。

## LED 状態とユーティリティ
```cpp
struct RGB { uint8_t r, g, b; };
static RGB leds[LED_COUNT];
static bool g_led_enabled = false;
static bool g_rainbow_mode = false;
static bool g_accel_mode = false;
```
- `fill_all`, `hsv_to_rgb` などのヘルパーで `leds[]` バッファを更新し、`ws_show()` で物理 LED に書き込み。
- `set_led_enabled`, `set_accel_mode`, `force_led_off` が状態遷移を一元管理。アイドル時にはストリップを消灯し GPIO 出力も Low に戻す。
- `g_idle_frame` フラグで「既に消灯済みか」を追跡し、不要なリフレッシュを抑制。

## WS2812 ビットバンギング
```cpp
static inline void dwt_init() {
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  DWT->CYCCNT = 0;
  DWT->CTRL  |= DWT_CTRL_CYCCNTENA_Msk;
}
```
- `dwt_init()` で DWT サイクルカウンタを有効化、`ns_to_cycles()` で 800kHz 系列の High/Low 幅を CPU クロックから算出。
- `ws_bit()` が 1bit 分の High/Low を GPIO に出力、`ws_byte()` → `ws_grb()` → `ws_show()` の順で 24bit データを送出。
- `ws_show()` 内で割り込みを禁止 (`noInterrupts()`) し、再開後に `delayMicroseconds(g_TRESET_us)` でラッチ時間を確保。

## 加速度モードとエフェクト
- `imu_begin()` が IMU 電源ピンを High にして I2C を初期化、設定値は ±2g / 104Hz / 400kHz I2C。
- `update_accel_effect(now_ms)`:
  - `imu_read()` からの (ax, ay, az) をロータッチフィルタ (`g_tilt_lp`, `g_acc_lp`) に通し、傾きと加速度変化量を平滑化。
  - 傾き角 (`atan2f(ay, ax)`) を HSV 色相に割り当て、基準色を `fill_all(base)` で全灯に適用。
  - `g_knight_pos` を往復させながら周囲 ±3 灯に重み付きブーストを加えて、ナイトライダー風のピークを形成。
  - 加速度の強さで `interval` を短縮し、強く振るほど移動速度が上がる。

## GATT 初期化とアドバタイズ
- `initialize_gatt_db()` で 3 つのサービスを作成:
  1. `Generic Access (0x1800)`: Device Name characteristic を読み取り専用で登録。
  2. `Immediate Alert (0x1802)`: Alert Level (0x2A06) を Write オンリー。0=消灯、1=点灯。
  3. カスタム 128-bit サービス: 書き込み専用キャラクタリスティックにコマンドを送ると `handle_led_command()` が処理。
- `start_normal_advertising()` で Flags + 128-bit Service UUID + Shortened Local Name を詰め込み、スキャンレスポンス側には完全なデバイス名を設定。

## メインフロー
- `setup()`:
  - シリアルのヘルプを表示し、GPIO/DWT 初期化と `ws_clear(3)` でバスをリセット。
  - IMU 初期化に失敗した場合は警告をシリアルに出力し加速度モードを無効化。
  - BLE アドバタイズセット作成 → GATT セッション構築 → 広告開始。
- `loop()`:
  - シリアルコマンド (`HELP`, `ON`, `OFF`, `BR`, `COLOR`, `ACCEL`) を受け付けて手動操作を可能に。
  - 接続が無い間は `force_led_off()` で完全消灯。
  - `g_accel_mode` / `g_led_enabled` / `g_rainbow_mode` の状態に応じて描画関数を選択し、`ws_show()` → `delay(10)` のサイクルで更新。
- `sl_bt_on_event()`:
  - 接続イベント: ハンドル取得後に状態をリセット。
  - 切断イベント: ハンドル無効化 → LED 消灯 → 広告再開。
  - `sl_bt_evt_gatt_server_attribute_value_id`: Alert Level で on/off、カスタム characteristic で全コマンドを受理。
  - `sl_bt_evt_advertiser_timeout_id`: 広告タイムアウト時に再スタート。

## 関連ノート
- BLE スキャナ: [[01_scan.py.explain.md]], [[02_browse.py.explain.md]]
- GATT 操作用 CLI: [[03_led_cli_onoff.py.explain.md]], [[04_led_rgb.py]] (Python 版)
- UUID 調査と書き込み保持: [[uuid_detect.py.explain.md]], [[write_2a06_hold.py.explain.md]]

