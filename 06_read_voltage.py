import argparse
import asyncio
from typing import Tuple

from bleak import BleakClient, BleakScanner

import config


def parse_voltage_payload(data: bytes) -> Tuple[int, int]:
    if len(data) < 4:
        raise ValueError(f"Expected at least 4 bytes for voltage payload, got {len(data)}")
    raw = int.from_bytes(data[0:2], "little")
    mv = int.from_bytes(data[2:4], "little")
    return raw, mv


async def resolve_address() -> str:
    target_addr = getattr(config, "TARGET_ADDR", None)
    if target_addr:
        return target_addr
    devices = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
    target = next((d for d in devices if d.name and config.TARGET_NAME in d.name), None)
    if not target:
        raise RuntimeError("Target not found by name. Adjust TARGET_NAME or set TARGET_ADDR in config.py.")
    return target.address


def format_voltage(raw: int, mv: int) -> str:
    volts = mv / 1000.0
    return f"{volts:.3f} V ({mv} mV, raw={raw})"


async def read_once(client: BleakClient) -> Tuple[int, int]:
    payload = await client.read_gatt_char(config.VOLTAGE_CHR_UUID)
    raw, mv = parse_voltage_payload(bytes(payload))
    print(f"[READ] {format_voltage(raw, mv)}")
    return raw, mv


async def monitor_notifications(client: BleakClient) -> None:
    stop_event = asyncio.Event()

    def handler(_: int, data: bytearray) -> None:
        try:
            raw, mv = parse_voltage_payload(bytes(data))
            print(f"[NOTIFY] {format_voltage(raw, mv)}")
        except Exception as exc:  # pylint: disable=broad-except
            print(f"[ERROR] Failed to parse notification: {exc}")

    await client.start_notify(config.VOLTAGE_CHR_UUID, handler)
    print("[MONITOR] Notifications started. Press Ctrl+C to stop.")
    try:
        await stop_event.wait()
    finally:
        await client.stop_notify(config.VOLTAGE_CHR_UUID)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Read Xiao MG24 D3 voltage over BLE.")
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Stay connected and print voltage notifications until interrupted.",
    )
    args = parser.parse_args()

    try:
        address = await resolve_address()
    except Exception as exc:
        raise SystemExit(str(exc))

    print(f"[CONNECT] {address}")
    async with BleakClient(address, timeout=config.CONNECT_TIMEOUT) as client:
        await read_once(client)
        if not args.stream:
            print("[DONE]")
            return
        try:
            await monitor_notifications(client)
        except KeyboardInterrupt:
            print("\n[MONITOR] Stopped by user.")


if __name__ == "__main__":
    asyncio.run(main())
