
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
