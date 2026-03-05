
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
