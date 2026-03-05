---
tags: [BLE, Python, Foam, 解説]
---

# [[01_scan.py]] 解説

**役割の要約**：
- BLEデバイスをスキャンして名前・アドレスを列挙します。`config.SCAN_TIMEOUT` と `config.TARGET_NAME` を参照します。

**実行例**：
```bash
例: `python 01_scan.py` を実行します。必要に応じて `config.py` を編集してください。
```

## コード全文
```python

import asyncio
from bleak import BleakScanner
import config

async def main():
    print(f"[SCAN] timeout={config.SCAN_TIMEOUT}s, looking for name contains: {config.TARGET_NAME!r}")
    devices = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
    for d in devices:
        print(f"- {d.address}  {d.name}")
    target = next((d for d in devices if d.name and config.TARGET_NAME in d.name), None)
    if target:
        print(f"[FOUND] {target.address}  {target.name}")
    else:
        print("[NOT FOUND]")

if __name__ == "__main__":
    asyncio.run(main())

```

## 行単位の読み解き（ポイント）
- スキャン: `BleakScanner.discover(timeout=...)` で周辺デバイスを取得します。
