---
tags: [BLE, Python, Foam, 解説]
---

# [[05_pair_then_write.py]] 解説

**役割の要約**：
- OSのペアリングを伴う接続〜書き込み処理を行います。

**実行例**：
```bash
例: `python 05_pair_then_write.py` を実行します。必要に応じて `config.py` を編集してください。
```

## コード全文
```python

import asyncio
from bleak import BleakClient, BleakScanner
import config

# Note: Many BLE stacks do just works pairing implicitly when required.
# This example simply connects; if pairing is needed, OS will prompt.

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
        print("[WRITE] LED ON")
        await client.write_gatt_char(config.CHR_UUID, b"\x01", response=config.WRITE_RESPONSE)
        await asyncio.sleep(0.5)
        print("[WRITE] LED OFF")
        await client.write_gatt_char(config.CHR_UUID, b"\x00", response=config.WRITE_RESPONSE)

if __name__ == "__main__":
    asyncio.run(main())

```

## 行単位の読み解き（ポイント）
- スキャン: `BleakScanner.discover(timeout=...)` で周辺デバイスを取得します。
- 接続: `BleakClient(address)` で対象に接続し、`async with` ブロックでリソースを解放します。
- 書き込み: `client.write_gatt_char(CHAR_UUID, data, response=True/False)` でGATT書き込みを行います。
- 待機: `asyncio.sleep(sec)` で非同期待機します。
