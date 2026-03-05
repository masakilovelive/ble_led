
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
        svcs = await client.get_services()
        for svc in svcs:
            for ch in svc.characteristics:
                props = set(ch.properties or [])
                if "write" in props or "write-without-response" in props:
                    mark = " <= LED(2A06)" if str(ch.uuid).lower() == config.CHR_UUID else ""
                    print(f"[WRITABLE] {ch.uuid} props={','.join(props)}{mark}")

if __name__ == "__main__":
    asyncio.run(main())
