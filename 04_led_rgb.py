import argparse
import asyncio
from typing import Dict, Tuple

from bleak import BleakClient, BleakScanner

import config

CMD_SET_BRIGHTNESS = 0x01
CMD_SET_COLOR = 0x02
CMD_START_RAINBOW = 0x03
CMD_STOP_RAINBOW = 0x04
CMD_ACCEL_MODE = 0x06
CMD_SET_FRONT_COLOR = 0x07
CMD_SET_REAR_COLOR = 0x08

PALETTE: Dict[str, Tuple[int, int, int]] = {
    "red": (255, 0, 0),
    "blue": (0, 0, 255),
    "yellow": (255, 255, 0),
    "green": (0, 255, 0),
    "purple": (128, 0, 128),
}
PALETTE_HEX: Dict[str, str] = {
    "red": "#ff0000",
    "blue": "#0000ff",
    "yellow": "#ffff00",
    "green": "#00ff00",
    "purple": "#800080",
}


def parse_color(value: str) -> Tuple[int, int, int]:
    text = value.strip()
    if text.startswith("#"):
        text = text[1:]
    if "," in text:
        parts = text.split(",")
        if len(parts) != 3:
            raise ValueError("Comma separated color must have 3 components")
        nums = [int(p.strip()) for p in parts]
    else:
        if len(text) not in (6, 8):
            raise ValueError("Hex color must be RRGGBB")
        text = text[:6]
        nums = [int(text[i:i + 2], 16) for i in range(0, 6, 2)]
    for n in nums:
        if not 0 <= n <= 255:
            raise ValueError("Color components must be in 0-255")
    return nums[0], nums[1], nums[2]


def clamp_byte(value: int) -> int:
    if value < 0 or value > 255:
        raise ValueError("Value must be 0-255")
    return value


async def resolve_address() -> str:
    target_addr = getattr(config, "TARGET_ADDR", None)
    if target_addr:
        return target_addr
    devices = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
    target = next((d for d in devices if d.name and config.TARGET_NAME in d.name), None)
    if not target:
        raise RuntimeError("Target not found by name")
    return target.address


async def write_power(client: BleakClient, state: bool) -> None:
    data = b"\x01" if state else b"\x00"
    await client.write_gatt_char(config.CHR_UUID, data, response=config.WRITE_RESPONSE)
    print(f"[WRITE] LED {'ON' if state else 'OFF'} (0x2A06)")


async def write_adv(client: BleakClient, payload: bytes) -> None:
    await client.write_gatt_char(config.ADV_CHR_UUID, payload, response=config.WRITE_RESPONSE)


def parse_palette(name: str) -> Tuple[int, int, int]:
    key = name.strip().lower()
    if key not in PALETTE:
        raise ValueError(f"Unknown palette color: {name}")
    return PALETTE[key]


async def write_front_color(client: BleakClient, color: Tuple[int, int, int]) -> None:
    r, g, b = color
    payload = bytes([CMD_SET_FRONT_COLOR, r, g, b])
    await write_adv(client, payload)


async def write_rear_color(client: BleakClient, color: Tuple[int, int, int]) -> None:
    r, g, b = color
    payload = bytes([CMD_SET_REAR_COLOR, r, g, b])
    await write_adv(client, payload)


async def send_palette_color(front: bool, color: Tuple[int, int, int]) -> None:
    address = await resolve_address()
    async with BleakClient(address, timeout=config.CONNECT_TIMEOUT) as client:
        if front:
            await write_front_color(client, color)
        else:
            await write_rear_color(client, color)


async def apply_arguments(client: BleakClient, args: argparse.Namespace) -> None:
    wants_adv = any([args.brightness is not None, args.color, args.rainbow, args.stop_rainbow])
    auto_power = wants_adv and not args.no_auto_on and not args.on and not args.off

    if args.on or auto_power:
        await write_power(client, True)
    if args.off:
        await write_power(client, False)

    if args.brightness is not None:
        value = clamp_byte(args.brightness)
        print(f"[ADV] Brightness -> {value}")
        payload = bytes([CMD_SET_BRIGHTNESS, value])
        await write_adv(client, payload)

    if args.color:
        r, g, b = parse_color(args.color)
        print(f"[ADV] Color -> ({r}, {g}, {b})")
        payload = bytes([CMD_SET_COLOR, r, g, b])
        await write_adv(client, payload)

    if args.rainbow is not None:
        interval = max(1, args.rainbow)
        print(f"[ADV] Rainbow start (interval={interval} ms)")
        payload = bytes([CMD_START_RAINBOW]) + interval.to_bytes(2, "little")
        await write_adv(client, payload)

    if args.stop_rainbow:
        print("[ADV] Rainbow stop")
        payload = bytes([CMD_STOP_RAINBOW])
        await write_adv(client, payload)

    if args.accel is not None:
        enable = args.accel == "on"
        if enable:
            print("[ADV] Accel mode ON")
            await write_power(client, True)
        else:
            print("[ADV] Accel mode OFF")
        payload = bytes([CMD_ACCEL_MODE, 0x01 if enable else 0x00])
        await write_adv(client, payload)

    if args.front:
        color = parse_palette(args.front)
        print(f"[ADV] Front color -> {args.front} {color}")
        await write_front_color(client, color)

    if args.rear:
        color = parse_palette(args.rear)
        print(f"[ADV] Rear color -> {args.rear} {color}")
        await write_rear_color(client, color)


async def interactive_loop(client: BleakClient) -> None:
    print("[INTERACTIVE] Connected. Commands: on, off, brightness <0-255>, color <RRGGBB|r,g,b|r g b>,"
          " rainbow [ms], stop, accel on|off, front <color>, rear <color>, help, quit")
    while True:
        try:
            line = await asyncio.to_thread(input, "ble> ")
        except (EOFError, KeyboardInterrupt):
            print()
            break
        line = line.strip()
        if not line:
            continue
        tokens = line.split()
        cmd = tokens[0].lower()
        try:
            if cmd in {"quit", "exit"}:
                break
            if cmd == "help":
                print("  on | off | brightness <0-255> | color <RRGGBB|r,g,b|r g b> |"
                      " rainbow [ms] | stop | accel on|off | front <color> | rear <color> | quit")
                continue
            if cmd == "on":
                await write_power(client, True)
                continue
            if cmd == "off":
                await write_power(client, False)
                continue
            if cmd == "brightness":
                if len(tokens) != 2:
                    raise ValueError("Usage: brightness <0-255>")
                value = clamp_byte(int(tokens[1], 0))
                await write_power(client, True)
                print(f"[ADV] Brightness -> {value}")
                await write_adv(client, bytes([CMD_SET_BRIGHTNESS, value]))
                continue
            if cmd == "color":
                if len(tokens) < 2:
                    raise ValueError("Usage: color <RRGGBB|r,g,b|r g b>")
                color_tokens = tokens[1:]
                try:
                    color_spec = "".join(color_tokens)
                    r, g, b = parse_color(color_spec.replace(" ", ""))
                except ValueError:
                    if len(color_tokens) == 3:
                        r, g, b = [clamp_byte(int(t, 0)) for t in color_tokens]
                    elif len(color_tokens) == 1 and "," in color_tokens[0]:
                        r, g, b = parse_color(color_tokens[0])
                    else:
                        raise
                await write_power(client, True)
                print(f"[ADV] Color -> ({r}, {g}, {b})")
                await write_adv(client, bytes([CMD_SET_COLOR, r, g, b]))
                continue
            if cmd == "rainbow":
                interval = 40
                if len(tokens) >= 2:
                    interval = max(1, int(tokens[1], 0))
                await write_power(client, True)
                print(f"[ADV] Rainbow start (interval={interval} ms)")
                await write_adv(client, bytes([CMD_START_RAINBOW]) + interval.to_bytes(2, "little"))
                continue
            if cmd in {"stop", "stoprainbow"}:
                print("[ADV] Rainbow stop")
                await write_adv(client, bytes([CMD_STOP_RAINBOW]))
                continue
            if cmd == "accel":
                if len(tokens) != 2 or tokens[1].lower() not in {"on", "off"}:
                    raise ValueError("Usage: accel on|off")
                enable = tokens[1].lower() == "on"
                if enable:
                    await write_power(client, True)
                print(f"[ADV] Accel mode {'ON' if enable else 'OFF'}")
                await write_adv(client, bytes([CMD_ACCEL_MODE, 0x01 if enable else 0x00]))
                continue
            if cmd in {"front", "rear"}:
                if len(tokens) != 2:
                    raise ValueError("Usage: front <color> | rear <color>")
                color = parse_palette(tokens[1])
                print(f"[ADV] {cmd} color -> {tokens[1]} {color}")
                if cmd == "front":
                    await write_front_color(client, color)
                else:
                    await write_rear_color(client, color)
                continue
            raise ValueError("Unknown command. Type 'help'.")
        except Exception as exc:
            print(f"[ERROR] {exc}")


def run_palette_ui() -> None:
    import tkinter as tk
    from tkinter import messagebox, ttk

    root = tk.Tk()
    root.title("Front/Rear Palette")
    root.geometry("420x240")

    status_var = tk.StringVar(value="Ready")

    notebook = ttk.Notebook(root)
    tab = ttk.Frame(notebook)
    notebook.add(tab, text="Front/Rear")
    notebook.pack(fill="both", expand=True, padx=8, pady=8)

    front_frame = ttk.LabelFrame(tab, text="FRONT (D9)")
    front_frame.grid(row=0, column=0, padx=8, pady=8, sticky="nsew")
    rear_frame = ttk.LabelFrame(tab, text="REAR (D10)")
    rear_frame.grid(row=0, column=1, padx=8, pady=8, sticky="nsew")

    def send(front: bool, color_name: str) -> None:
        status_var.set(f"Sending {color_name}...")
        root.update_idletasks()
        try:
            asyncio.run(send_palette_color(front, PALETTE[color_name]))
            status_var.set(f"Sent {color_name}")
        except Exception as exc:
            status_var.set("Error")
            messagebox.showerror("BLE error", str(exc))

    def build_buttons(frame: ttk.LabelFrame, front: bool) -> None:
        for i, name in enumerate(PALETTE.keys()):
            btn = tk.Button(
                frame,
                text=name,
                width=8,
                relief="raised",
                bg=PALETTE_HEX[name],
                fg="white" if name in {"red", "blue", "purple"} else "black",
                command=lambda n=name: send(front, n),
            )
            btn.grid(row=i // 2, column=i % 2, padx=6, pady=6, sticky="nsew")

    build_buttons(front_frame, True)
    build_buttons(rear_frame, False)

    status = ttk.Label(root, textvariable=status_var)
    status.pack(side="bottom", fill="x", padx=8, pady=4)

    root.mainloop()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Advanced LED control over custom GATT")
    parser.add_argument("--brightness", type=int, help="Set brightness 0-255")
    parser.add_argument("--color", type=str, help="Set color (RRGGBB or r,g,b)")
    parser.add_argument("--rainbow", nargs="?", const=40, type=int,
                        help="Start rainbow effect (interval ms, default 40)")
    parser.add_argument("--stop-rainbow", action="store_true", help="Stop rainbow effect")
    parser.add_argument("--accel", choices=["on", "off"], help="Enable or disable acceleration mode")
    parser.add_argument("--front", choices=sorted(PALETTE.keys()),
                        help="Set FRONT (D9) color from palette")
    parser.add_argument("--rear", choices=sorted(PALETTE.keys()),
                        help="Set REAR (D10) color from palette")
    parser.add_argument("--on", action="store_true", help="Write 0x01 to 0x2A06")
    parser.add_argument("--off", action="store_true", help="Write 0x00 to 0x2A06")
    parser.add_argument("--no-auto-on", action="store_true",
                        help="Do not automatically power on when sending color/brightness/rainbow")
    parser.add_argument("--stay", action="store_true",
                        help="Keep BLE connection open for interactive commands")
    parser.add_argument("--palette-ui", action="store_true",
                        help="Open palette UI for FRONT/REAR colors")
    return parser


async def run_cli(args: argparse.Namespace) -> None:
    if args.on and args.off:
        raise SystemExit("Use either --on or --off, not both")

    try:
        address = await resolve_address()
    except Exception as exc:
        raise SystemExit(str(exc))

    print(f"[CONNECT] {address}")
    async with BleakClient(address, timeout=config.CONNECT_TIMEOUT) as client:
        await apply_arguments(client, args)
        if args.stay:
            await interactive_loop(client)
    print("[DONE]")


if __name__ == "__main__":
    parser = build_parser()
    args = parser.parse_args()
    if args.palette_ui:
        run_palette_ui()
    else:
        asyncio.run(run_cli(args))
