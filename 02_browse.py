import asyncio
from bleak import BleakClient, BleakScanner
import config

async def get_services_compat(client):
    try:
        return await client.get_services()  # bleak <=0.22
    except AttributeError:
        svcs = getattr(client, "services", None)  # bleak >=1.0
        if svcs is None:
            try:
                await client.connect()
                svcs = getattr(client, "services", None)
            except Exception:
                svcs = None
        return svcs

async def main():
    target_addr = getattr(config, "TARGET_ADDR", None)
    if target_addr:
        address = target_addr
    else:
        devs = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
        target = next((d for d in devs if d.name and config.TARGET_NAME in d.name), None)
        if not target:
            print("[ERROR] Target not found by name")
            return
        address = target.address

    svc_uuid = getattr(config, "SVC_UUID", "").lower()
    adv_svc_uuid = getattr(config, "ADV_SVC_UUID", "").lower()
    chr_uuid = getattr(config, "CHR_UUID", "").lower()
    adv_chr_uuid = getattr(config, "ADV_CHR_UUID", "").lower()

    print(f"[CONNECT] {address}")
    async with BleakClient(address, timeout=config.CONNECT_TIMEOUT) as client:
        svcs = await get_services_compat(client)
        for svc in svcs:
            marks = []
            suuid = str(svc.uuid).lower()
            if svc_uuid and suuid == svc_uuid:
                marks.append("TARGET")
            if adv_svc_uuid and suuid == adv_svc_uuid:
                marks.append("LED-ADV")
            mark_str = f" <= {'/'.join(marks)}" if marks else ""
            print(f"[SVC] {svc.uuid}{mark_str}")
            for ch in svc.characteristics:
                props = ",".join(ch.properties)
                marks_c = []
                cuuid = str(ch.uuid).lower()
                if chr_uuid and cuuid == chr_uuid:
                    marks_c.append("LED(2A06)")
                if adv_chr_uuid and cuuid == adv_chr_uuid:
                    marks_c.append("LED-ADV")
                markc = f" <= {'/'.join(marks_c)}" if marks_c else ""
                print(f"  [CHAR] {ch.uuid} props={props}{markc}")
                for d in ch.descriptors:
                    print(f"    [DESC] {d.uuid}")

if __name__ == "__main__":
    asyncio.run(main())