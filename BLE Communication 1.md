# BLE Communication 1

---
aliases:
  - BLE LED Controller
  - 2A06 Alert Level Write
  - BLE GATT Scripts
  - Bluetooth Low Energy Python
  - LED BLE Tools
tags:
  - Flashcards
  - Programming
  - BLE
  - Python
  - VSCode
location: local
---

## 🧠 概要
**[[fixed_led_ble_2a06_package]]** は、[[Bluetooth Low Energy|BLE]] デバイスに対して GATT 特性、特に [[Alert Level]] (0x2A06) を操作するための [[Python]] ツールセットです。スキャン・接続・UUID 検査・ペアリング・書き込み・CLI 操作を想定しており、[[VS Code]] での実験ワークフローを前提に構成されています。

## 📁 ディレクトリ構成

```
/fixed_led_ble_2a06_package/
├── [[01_scan.py]]               # BLE デバイスをスキャン
├── [[02_browse.py]]             # GATT サービス/特性を列挙
├── [[02b_enable_indication.py]] # Notification/Indication を有効化
├── [[03_led_cli_onoff.py]]      # CLI から LED を ON/OFF
├── [[03_list_writable.py]]      # 書き込み可能な特性を列挙
├── [[05_pair_then_write.py]]    # ペアリング後に 0x2A06 へ書き込み
├── [[06_read_voltage.py]]       # D3 ピン電圧を読み取り／サブスクライブ
├── [[config.py]]                # ターゲット名・UUID など共通設定
├── [[uuid_detect.py]]           # UUID から特性を検索
├── [[write_2a06_hold.py]]       # 0x2A06 に一定時間値を書き込み保持
```

## 📝 主なスクリプトの説明

- **01_scan.py** — 周囲の BLE デバイスをスキャンし、名前とアドレスを表示  
- **02_browse.py** — 指定デバイスの GATT サービスとキャラクタリスティクスを探索  
- **02b_enable_indication.py** — Notification / Indication を有効化する補助スクリプト  
- **03_led_cli_onoff.py** — CLI から Alert Level (0x2A06) を書き込み、LED を制御  
- **03_list_writable.py** — 書き込み可能な特性を一覧表示  
- **05_pair_then_write.py** — OS ペアリング完了後に 0x2A06 へ書き込み  
- **06_read_voltage.py** — XIAO D3 ピンの電圧を単発読み取り・通知監視  
- **config.py** — ターゲット名や UUID を一元管理  
- **uuid_detect.py** — UUID から該当する特性を素早く検索  
- **write_2a06_hold.py** — 0x2A06 に同じ値を送り続け、長押し風に制御

## 🎓 Flashcards

### BLE スキャン
**Q:** [[fixed_led_ble_2a06_package]] で BLE デバイスをスキャンするスクリプトはどれ？  
**A:** [[01_scan.py]]

---

### GATT サービス探索
**Q:** デバイスのサービス構成をブラウズするファイルは？  
**A:** [[02_browse.py]]

---

### Alert Level の UUID
**Q:** 操作対象の Alert Level 特性 UUID は？  
**A:** 0x2A06

---

### LED 制御 CLI
**Q:** CLI から LED を制御するためのスクリプトは？  
**A:** [[03_led_cli_onoff.py]]

---

### 設定ファイル
**Q:** ターゲット名や UUID 設定を保持するファイルは？  
**A:** [[config.py]]

---

### 電圧測定
**Q:** XIAO MG24(Sense) の D3 ピン電圧を測定するスクリプトは？  
**A:** [[06_read_voltage.py]]
