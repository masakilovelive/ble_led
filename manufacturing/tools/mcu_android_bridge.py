#!/usr/bin/env python3
"""Relay the Arduino MCU serial protocol to Android over TCP.

The Android app connects through adb reverse to 127.0.0.1:<listen-port>.
"""

from __future__ import annotations

import argparse
import collections
import socket
import threading
import time
from contextlib import suppress

import serial
import serial.tools.list_ports


class BridgeState:
    def __init__(self, serial_handle: serial.Serial, cache_size: int) -> None:
        self.serial_handle = serial_handle
        self.cache = collections.deque(maxlen=cache_size)
        self.stop_event = threading.Event()
        self._client_lock = threading.Lock()
        self._client_socket: socket.socket | None = None

    def attach_client(self, client: socket.socket) -> None:
        with self._client_lock:
            old_client = self._client_socket
            self._client_socket = client
        if old_client is not None:
            with suppress(OSError):
                old_client.close()
        self._send_line(client, "[BRIDGE] CLIENT_CONNECTED")
        for cached in list(self.cache):
            self._send_line(client, cached)

    def detach_client(self, client: socket.socket) -> None:
        with self._client_lock:
            if self._client_socket is client:
                self._client_socket = None
        with suppress(OSError):
            client.close()

    def append_serial_line(self, line: str) -> None:
        print(line, flush=True)
        self.cache.append(line)
        with self._client_lock:
            client = self._client_socket
        if client is not None:
            self._send_line(client, line)

    def write_serial_line(self, line: str) -> None:
        payload = f"{line}\r\n".encode("utf-8")
        self.serial_handle.write(payload)
        self.serial_handle.flush()
        print(f"[APP->MCU] {line}", flush=True)

    def stop(self) -> None:
        self.stop_event.set()
        with self._client_lock:
            client = self._client_socket
            self._client_socket = None
        if client is not None:
            with suppress(OSError):
                client.close()
        with suppress(Exception):
            self.serial_handle.close()

    @staticmethod
    def _send_line(client: socket.socket, line: str) -> None:
        data = f"{line}\r\n".encode("utf-8", errors="replace")
        client.sendall(data)


def _serial_reader(state: BridgeState) -> None:
    while not state.stop_event.is_set():
        try:
            raw = state.serial_handle.readline()
        except serial.SerialException as exc:
            state.append_serial_line(f"[ERR] serial read failed: {exc}")
            state.stop_event.set()
            return
        if not raw:
            continue
        line = raw.decode("utf-8", errors="replace").strip()
        if line:
            state.append_serial_line(line)


def _client_session(state: BridgeState, client: socket.socket, address: tuple[str, int]) -> None:
    print(f"[BRIDGE] client connected: {address[0]}:{address[1]}", flush=True)
    state.attach_client(client)
    try:
        buffer = b""
        while not state.stop_event.is_set():
            chunk = client.recv(4096)
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                raw_line, buffer = buffer.split(b"\n", 1)
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                try:
                    state.write_serial_line(line)
                except serial.SerialException as exc:
                    state.append_serial_line(f"[ERR] serial write failed: {exc}")
                    state.stop_event.set()
                    return
    finally:
        print(f"[BRIDGE] client disconnected: {address[0]}:{address[1]}", flush=True)
        state.detach_client(client)


def _serve(state: BridgeState, host: str, port: int) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((host, port))
        server.listen(1)
        server.settimeout(0.5)
        print(f"[BRIDGE] listening on {host}:{port}", flush=True)
        while not state.stop_event.is_set():
            try:
                client, address = server.accept()
            except TimeoutError:
                continue
            except OSError:
                if state.stop_event.is_set():
                    break
                raise
            thread = threading.Thread(
                target=_client_session,
                args=(state, client, address),
                daemon=True,
            )
            thread.start()


def _list_ports() -> int:
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print("No serial ports found.")
        return 1
    for port in ports:
        description = port.description or "(no description)"
        print(f"{port.device}\t{description}")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bridge Arduino MCU serial to Android over TCP.")
    parser.add_argument("--serial-port", help="Serial port, e.g. COM4")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate")
    parser.add_argument("--listen-host", default="127.0.0.1", help="TCP listen host")
    parser.add_argument("--listen-port", type=int, default=9876, help="TCP listen port")
    parser.add_argument("--cache-size", type=int, default=200, help="Replay cache lines for new clients")
    parser.add_argument("--list-ports", action="store_true", help="List available serial ports and exit")
    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    if args.list_ports:
        return _list_ports()

    if not args.serial_port:
        parser.error("--serial-port is required unless --list-ports is used")

    serial_handle = serial.Serial(
        args.serial_port,
        args.baud,
        timeout=0.2,
        write_timeout=1.0,
    )
    serial_handle.dtr = True
    serial_handle.rts = True
    serial_handle.reset_input_buffer()
    state = BridgeState(serial_handle=serial_handle, cache_size=args.cache_size)

    reader = threading.Thread(target=_serial_reader, args=(state,), daemon=True)
    reader.start()

    try:
        time.sleep(0.2)
        _serve(state, args.listen_host, args.listen_port)
    except KeyboardInterrupt:
        print("[BRIDGE] stopping", flush=True)
    finally:
        state.stop()
        reader.join(timeout=1.0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
