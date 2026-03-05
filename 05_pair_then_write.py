
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
