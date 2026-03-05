---
tags: [BLE, Python, Foam, 解説]
---

# [[write_2a06_hold.py]] 解説

**役割の要約**：
- 0x2A06（Alert Level）への書き込みを一定時間保持または点滅制御します。

**実行例**：
```bash
例: `python write_2a06_hold.py --help` を実行します。必要に応じて `config.py` を編集してください。
```

## コード全文
```python

import asyncio
import argparse
from bleak import BleakClient, BleakScanner
import config

async def main(on_ms: int, off_ms: int):
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
        print("[WRITE] ON")
        await client.write_gatt_char(config.CHR_UUID, b"\x01", response=config.WRITE_RESPONSE)
        await asyncio.sleep(on_ms/1000.0)
        print("[WRITE] OFF")
        await client.write_gatt_char(config.CHR_UUID, b"\x00", response=config.WRITE_RESPONSE)
        await asyncio.sleep(off_ms/1000.0)

def cli():
    ap = argparse.ArgumentParser()
    ap.add_argument("--on_ms", type=int, default=500)
    ap.add_argument("--off_ms", type=int, default=1000)
    args = ap.parse_args()
    asyncio.run(main(args.on_ms, args.off_ms))

if __name__ == "__main__":
    cli()

```

## 行単位の読み解き（ポイント）
- 引数解析: `argparse.ArgumentParser()` でCLI引数を受け取り、`asyncio.run(...)` に渡します。
- スキャン: `BleakScanner.discover(timeout=...)` で周辺デバイスを取得します。
- 接続: `BleakClient(address)` で対象に接続し、`async with` ブロックでリソースを解放します。
- 書き込み: `client.write_gatt_char(CHAR_UUID, data, response=True/False)` でGATT書き込みを行います。
- 待機: `asyncio.sleep(sec)` で非同期待機します。

---
## 関連: Arduinoスケッチへのリンク
- [[arduino/xiao_mg24_ble_alert_led.ino.explain.md|arduino/xiao_mg24_ble_alert_led.ino]]
