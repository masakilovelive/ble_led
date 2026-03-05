import asyncio
from bleak import BleakClient, BleakScanner
import config

async def main():
    target_addr = getattr(config, "TARGET_ADDR", None)
    if target_addr:
        address = target_addr
    else:
        devices = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
        target = next((d for d in devices if d.name and config.TARGET_NAME in d.name), None)
        if not target:
            print("[ERROR] Target not found by name")
            return
        address = target.address

    async with BleakClient(address, timeout=config.CONNECT_TIMEOUT) as client:
        print(f"connected: {client.is_connected}")
        svcs = await client.get_services()
        base_uuid = getattr(config, "CHR_UUID", "").lower()
        adv_uuid = getattr(config, "ADV_CHR_UUID", "").lower()
        for svc in svcs:
            print(f"[SVC] {svc.uuid}")
            for ch in svc.characteristics:
                props = ",".join(ch.properties)
                line = f"  [CHAR] {ch.uuid} props={props}"
                cuuid = str(ch.uuid).lower()
                if base_uuid and cuuid == base_uuid:
                    line += "  <<< LED (0x2A06)"
                if adv_uuid and cuuid == adv_uuid:
                    line += "  <<< LED-ADV"
                print(line)

if __name__ == "__main__":
    asyncio.run(main())