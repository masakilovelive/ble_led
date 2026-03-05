import argparse
import asyncio
import re
import time
from typing import Any, Optional

from bleak import BleakClient, BleakScanner

import config


ESP32_NAME_RE = re.compile(r"XIAO-ESP32C3-LED-(?:STOCK)?\d+$")


def log(message: str) -> None:
    now = time.time()
    stamp = time.strftime("%H:%M:%S", time.localtime(now))
    millis = int((now % 1.0) * 1000.0)
    print(f"[{stamp}.{millis:03d}] {message}", flush=True)


def default_winrt_args() -> dict[str, Any]:
    winrt: dict[str, Any] = {}
    address_type = getattr(config, "WINRT_ADDRESS_TYPE", None)
    if address_type:
        winrt["address_type"] = address_type
    use_cached_services = getattr(config, "WINRT_USE_CACHED_SERVICES", None)
    if use_cached_services is not None:
        winrt["use_cached_services"] = bool(use_cached_services)
    return winrt


async def resolve_target(address: Optional[str], name: Optional[str], scan_timeout: float) -> tuple[str, str]:
    if address:
        return address, address
    if not name:
        raise RuntimeError("Target name or address is required")

    log(f"[SCAN] timeout={scan_timeout:.1f}s name contains {name!r}")
    devices = await BleakScanner.discover(timeout=scan_timeout)
    for device in devices:
        log(f"[SCAN] {device.address} name={device.name!r}")

    target = next((d for d in devices if d.name == name), None)
    if target is None:
        target = next((d for d in devices if d.name and name in d.name), None)
    if target is None:
        esp32_candidates = [
            f"{d.name} ({d.address})"
            for d in devices
            if d.name and ESP32_NAME_RE.search(d.name)
        ]
        if esp32_candidates:
            preview = ", ".join(esp32_candidates)
            raise RuntimeError(
                f"Target not found by name: {name!r}. "
                f"Available ESP32 candidates: {preview}. "
                "Run again with --name XIAO-ESP32C3-LED-STOCK3 or --name XIAO-ESP32C3-LED-STOCK4."
            )
        raise RuntimeError(f"Target not found by name: {name!r}")
    return target.address, target.name or target.address


async def get_services_compat(client: BleakClient) -> Any:
    get_services = getattr(client, "get_services", None)
    if callable(get_services):
        return await get_services()
    return getattr(client, "services", None)


async def describe_profile(client: BleakClient) -> None:
    try:
        services = await get_services_compat(client)
    except Exception as exc:
        log(f"[GATT] service discovery failed: {type(exc).__name__}: {exc}")
        return
    if not services:
        log("[GATT] no services returned")
        return

    service_uuids: list[str] = []
    char_uuids: list[str] = []
    adv_found = False
    voltage_found = False

    try:
        for service in services:
            service_uuids.append(str(getattr(service, "uuid", "")))
            for ch in getattr(service, "characteristics", []):
                uuid = str(getattr(ch, "uuid", ""))
                char_uuids.append(uuid)
                if uuid.lower() == config.ADV_CHR_UUID.lower():
                    adv_found = True
                if uuid.lower() == config.VOLTAGE_CHR_UUID.lower():
                    voltage_found = True
    except Exception as exc:
        log(f"[GATT] service parse failed: {type(exc).__name__}: {exc}")
        return

    preview = ", ".join(service_uuids[:8])
    log(f"[GATT] services={len(service_uuids)} chars={len(char_uuids)}")
    log(f"[GATT] service uuids: {preview}")
    log(
        f"[GATT] adv_char={adv_found} voltage_char={voltage_found} "
        f"target_service={config.ADV_SVC_UUID}"
    )


async def hold_connection(args: argparse.Namespace) -> int:
    target_name = args.name or config.TARGET_NAME
    disconnect_event = asyncio.Event()
    disconnected_at: Optional[float] = None

    def on_disconnect(_client: BleakClient) -> None:
        nonlocal disconnected_at
        disconnected_at = time.monotonic()
        log("[LINK] disconnect callback")
        disconnect_event.set()

    address, resolved_name = await resolve_target(args.address, target_name, args.scan_timeout)
    log(f"[TARGET] address={address} name={resolved_name}")
    winrt: dict[str, Any] = default_winrt_args()
    if args.address_type:
        winrt["address_type"] = args.address_type
    if args.no_cached_services:
        winrt["use_cached_services"] = False
    if winrt:
        log(f"[WINRT] args={winrt}")

    client = BleakClient(
        address,
        timeout=args.connect_timeout,
        pair=args.pair,
        winrt=winrt,
        disconnected_callback=on_disconnect,
    )

    connect_started = time.monotonic()
    try:
        log(f"[CONNECT] start pair={args.pair}")
        await client.connect()
        connected_at = time.monotonic()
        log(f"[CONNECT] connected in {connected_at - connect_started:.3f}s")

        if args.discover:
            await describe_profile(client)

        deadline = connected_at + args.hold_seconds
        while client.is_connected and not disconnect_event.is_set():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            step = min(args.poll_seconds, remaining)
            try:
                await asyncio.wait_for(disconnect_event.wait(), timeout=step)
            except asyncio.TimeoutError:
                elapsed = time.monotonic() - connected_at
                log(f"[HOLD] connected {elapsed:.1f}s")

        if disconnect_event.is_set():
            assert disconnected_at is not None
            log(f"[RESULT] disconnected after {disconnected_at - connected_at:.3f}s")
            return 2

        log(f"[RESULT] stayed connected for {args.hold_seconds:.1f}s")
        return 0
    finally:
        if client.is_connected:
            log("[CONNECT] disconnect request")
            await client.disconnect()
            log("[CONNECT] disconnect done")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Minimal Windows/Bleak connect-and-hold diagnostic",
    )
    parser.add_argument("--name", help="Device name or substring to scan for")
    parser.add_argument("--address", help="Device MAC/address to connect directly")
    parser.add_argument(
        "--scan-timeout",
        type=float,
        default=config.SCAN_TIMEOUT,
        help="Scan timeout in seconds",
    )
    parser.add_argument(
        "--connect-timeout",
        type=float,
        default=config.CONNECT_TIMEOUT,
        help="Connect timeout in seconds",
    )
    parser.add_argument(
        "--hold-seconds",
        type=float,
        default=15.0,
        help="How long to keep the connection open",
    )
    parser.add_argument(
        "--poll-seconds",
        type=float,
        default=1.0,
        help="Heartbeat print interval while connected",
    )
    parser.add_argument(
        "--discover",
        action="store_true",
        help="Run service discovery after connect",
    )
    parser.add_argument(
        "--pair",
        action="store_true",
        help="Request pair=True on connect",
    )
    parser.add_argument(
        "--address-type",
        choices=("public", "random"),
        help="Windows WinRT address type override",
    )
    parser.add_argument(
        "--no-cached-services",
        action="store_true",
        help="Windows WinRT: disable cached services",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    try:
        rc = asyncio.run(hold_connection(args))
    except KeyboardInterrupt:
        log("[EXIT] interrupted")
        raise SystemExit(130)
    except Exception as exc:
        log(f"[ERROR] {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    raise SystemExit(rc)


if __name__ == "__main__":
    main()
