---
tags: [BLE, Python, Foam, 解説]
---

# [[03_led_cli_onoff.py]] 解説

**役割の要約**：
- CLI引数でAlert Level（0/1/2）を書き込み、LEDのON/OFF/ミドルを制御します。

**実行例**：
```bash
例: `python 03_led_cli_onoff.py --help` を実行します。必要に応じて `config.py` を編集してください。
```

## コード全文
```python

import asyncio
import argparse
from bleak import BleakClient, BleakScanner
import config

async def run(state: int):
    if config.TARGET_ADDR:
        address = config.TARGET_ADDR
    else:
        devs = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
        target = next((d for d in devs if d.name and config.TARGET_NAME in d.name), None)
        if not target:
            print("[ERROR] Target not found by name")
            return
        address = target.address

    async with BleakClient(address, timeout=config.CONNECT_TIMEOUT) as client:
        data = bytes([0x01 if state else 0x00])
        print(f"[WRITE] {data.hex()} to {config.CHR_UUID}")
        await client.write_gatt_char(config.CHR_UUID, data, response=config.WRITE_RESPONSE)
        print("[DONE]")

def main():
    ap = argparse.ArgumentParser(description="LED ON/OFF via 0x2A06")
    ap.add_argument("--on", action="store_true", help="turn LED ON")
    ap.add_argument("--off", action="store_true", help="turn LED OFF")
    args = ap.parse_args()
    if args.on == args.off:
        print("Use either --on or --off")
        return
    asyncio.run(run(1 if args.on else 0))

if __name__ == "__main__":
    main()

```

## 行単位の読み解き（ポイント）
- 引数解析: `argparse.ArgumentParser()` でCLI引数を受け取り、`asyncio.run(...)` に渡します。
- スキャン: `BleakScanner.discover(timeout=...)` で周辺デバイスを取得します。
- 接続: `BleakClient(address)` で対象に接続し、`async with` ブロックでリソースを解放します。
- 書き込み: `client.write_gatt_char(CHAR_UUID, data, response=True/False)` でGATT書き込みを行います。

---
## 関連: Arduinoスケッチへのリンク
- [[arduino/xiao_mg24_ble_alert_led.ino.explain.md|arduino/xiao_mg24_ble_alert_led.ino]]
