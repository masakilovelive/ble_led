
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
