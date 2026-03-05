---
tags: [BLE, Python, Foam, 解説]
---

# [[uuid_detect.py]] 解説

**役割の要約**：
- 指定UUIDを探索して、対象キャラクタリスティクスの有無を検出します。

**実行例**：
```bash
例: `python uuid_detect.py` を実行します。必要に応じて `config.py` を編集してください。
```

## コード全文
```python

import asyncio
from bleak import BleakClient, BleakScanner
import config

async def main():
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
        print(f"connected: {client.is_connected}")
        svcs = await client.get_services()
        for svc in svcs:
            print(f"[SVC] {svc.uuid}")
            for ch in svc.characteristics:
                props = ",".join(ch.properties)
                line = f"  [CHAR] {ch.uuid} props={props}"
                if str(ch.uuid).lower() == config.CHR_UUID:
                    line += "  >>> WRITEここ！(0x2A06)"
                print(line)

if __name__ == "__main__":
    asyncio.run(main())

```

## 行単位の読み解き（ポイント）
- スキャン: `BleakScanner.discover(timeout=...)` で周辺デバイスを取得します。
- 接続: `BleakClient(address)` で対象に接続し、`async with` ブロックでリソースを解放します。
- 構造取得: `client.get_services()` でサービス/特性一覧を取得します。

---
## 関連: Arduinoスケッチへのリンク
- [[arduino/xiao_mg24_ble_alert_led.ino.explain.md|arduino/xiao_mg24_ble_alert_led.ino]]
