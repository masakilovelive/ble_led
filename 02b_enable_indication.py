
import asyncio
from bleak import BleakClient, BleakScanner
from bleak.uuids import uuid16_dict
import config

# Attempt to enable indications if CCCD exists; 0x2A06 often doesn't support it.
CCCD_UUID = "00002902-0000-1000-8000-00805f9b34fb"

def decode_props(ch):
    try:
        return ",".join(ch.properties)
    except Exception:
        return ""

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
        ch = None
        for svc in svcs:
            for c in svc.characteristics:
                if str(c.uuid).lower() == config.CHR_UUID:
                    ch = c
                    break
        if not ch:
            print("[ERROR] 0x2A06 not found")
            return

        # Try to enable indication if CCCD exists
        cccd = next((d for d in ch.descriptors if str(d.uuid).lower() == CCCD_UUID), None)
        if cccd and ("indicate" in decode_props(ch) or "notify" in decode_props(ch)):
            try:
                # 0x0002 = Indications, 0x0001 = Notifications
                value = b"\x02" if "indicate" in decode_props(ch) else b"\x01"
                await client.write_gatt_descriptor(cccd.handle, value)
                print("[OK] CCCD enabled")
            except Exception as e:
                print(f"[WARN] CCCD enable failed: {e}")
        else:
            print("[INFO] No CCCD or no indicate/notify. Skipping.")

        # Finally, write to LED
        print("[WRITE] LED ON")
        await client.write_gatt_char(config.CHR_UUID, b"\x01", response=config.WRITE_RESPONSE)
        await asyncio.sleep(1.0)
        print("[WRITE] LED OFF")
        await client.write_gatt_char(config.CHR_UUID, b"\x00", response=config.WRITE_RESPONSE)

if __name__ == "__main__":
    asyncio.run(main())
