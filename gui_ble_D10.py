"""GUI BLE controller for D10 (REAR) NeoPixel using a color wheel."""

import asyncio
import math
from typing import Optional, Set

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError
from PySide6.QtCore import QPoint, QSignalBlocker, Qt, Signal
from PySide6.QtGui import QColor, QImage, QPainter, QPen
from PySide6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
    QPlainTextEdit,
)
import qasync

import config

CMD_SET_REAR_COLOR = 0x08


class ColorWheel(QWidget):
    colorSelected = Signal(QColor)

    def __init__(self, diameter: int = 220, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self._diameter = diameter
        self._radius = diameter / 2 - 1
        self._center = diameter / 2
        self._image = self._build_wheel(diameter)
        self._last_pos: Optional[QPoint] = None
        self.setFixedSize(diameter, diameter)
        self.setCursor(Qt.CrossCursor)

    def _build_wheel(self, size: int) -> QImage:
        image = QImage(size, size, QImage.Format_ARGB32)
        radius = self._radius
        center = self._center
        for y in range(size):
            for x in range(size):
                dx = x - center
                dy = center - y
                dist = math.hypot(dx, dy)
                if dist > radius:
                    image.setPixelColor(x, y, QColor(0, 0, 0, 0))
                    continue
                saturation = dist / radius
                hue = math.degrees(math.atan2(dy, dx))
                hue = (hue + 360.0) % 360.0
                color = QColor.fromHsvF(hue / 360.0, saturation, 1.0, 1.0)
                image.setPixelColor(x, y, color)
        return image

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing, True)
        painter.drawImage(0, 0, self._image)
        if self._last_pos:
            painter.setPen(QPen(Qt.black, 2))
            painter.drawEllipse(self._last_pos, 6, 6)
            painter.setPen(QPen(Qt.white, 2))
            painter.drawEllipse(self._last_pos, 8, 8)
        painter.end()

    def mousePressEvent(self, event) -> None:
        if event.buttons() & Qt.LeftButton:
            self._pick_color(self._event_pos(event))

    def mouseMoveEvent(self, event) -> None:
        if event.buttons() & Qt.LeftButton:
            self._pick_color(self._event_pos(event))

    @staticmethod
    def _event_pos(event) -> QPoint:
        if hasattr(event, "position"):
            return event.position().toPoint()
        return event.pos()

    def _pick_color(self, pos: QPoint) -> None:
        if not self.isEnabled():
            return
        x, y = pos.x(), pos.y()
        if not (0 <= x < self._image.width() and 0 <= y < self._image.height()):
            return
        color = self._image.pixelColor(x, y)
        if color.alpha() == 0:
            return
        self._last_pos = QPoint(x, y)
        self.update()
        self.colorSelected.emit(color)

    def set_color(self, color: QColor, emit: bool = False) -> None:
        hue, saturation, _, _ = color.getHsvF()
        radius = saturation * self._radius
        angle = hue * 2.0 * math.pi
        x = self._center + math.cos(angle) * radius
        y = self._center - math.sin(angle) * radius
        self._last_pos = QPoint(int(round(x)), int(round(y)))
        self.update()
        if emit and self.isEnabled():
            self.colorSelected.emit(color)


class D10BleController(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("BLE D10 (REAR) Color Wheel")
        self.client: Optional[BleakClient] = None
        self.device_address: Optional[str] = None
        self._current_color = QColor(255, 0, 0)
        self._building_ui = True
        self._tasks: Set[asyncio.Task] = set()
        self._connect_lock = asyncio.Lock()
        self._setup_ui()
        self._building_ui = False

    def _setup_ui(self) -> None:
        layout = QVBoxLayout()
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        header_layout = QHBoxLayout()
        self.connect_button = QPushButton("Connect")
        self.connect_button.clicked.connect(self._on_connect_clicked)
        header_layout.addWidget(self.connect_button)
        self.disconnect_button = QPushButton("Disconnect")
        self.disconnect_button.setEnabled(False)
        self.disconnect_button.clicked.connect(self._on_disconnect_clicked)
        header_layout.addWidget(self.disconnect_button)
        header_layout.addStretch()
        layout.addLayout(header_layout)

        layout.addWidget(QLabel("REAR (D10) Color"))
        self.color_wheel = ColorWheel(220)
        self.color_wheel.setEnabled(False)
        self.color_wheel.colorSelected.connect(self._on_color_selected)
        layout.addWidget(self.color_wheel, alignment=Qt.AlignHCenter)
        self.color_wheel.set_color(self._current_color, emit=False)

        action_layout = QHBoxLayout()
        self.off_button = QPushButton("Rear OFF")
        self.off_button.setEnabled(False)
        self.off_button.clicked.connect(self._on_rear_off_clicked)
        action_layout.addWidget(self.off_button)
        action_layout.addStretch()
        layout.addLayout(action_layout)

        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        layout.addWidget(self.log_view)

        self.setLayout(layout)

    def _set_controls_enabled(self, connected: bool) -> None:
        self.disconnect_button.setEnabled(connected)
        self.color_wheel.setEnabled(connected)
        self.off_button.setEnabled(connected)
        if not connected:
            blocker = QSignalBlocker(self.color_wheel)
            _ = blocker  # keep reference to avoid unused warnings

    def log(self, message: str) -> None:
        if self.log_view is not None:
            self.log_view.appendPlainText(message)
            self.log_view.ensureCursorVisible()

    def _run_async(self, coro: asyncio.Future) -> None:
        task = asyncio.create_task(coro)
        self._tasks.add(task)
        task.add_done_callback(lambda t: self._tasks.discard(t))

    # --------------------------- BLE helpers ---------------------------
    async def _ensure_connected(self) -> bool:
        if self.client and self.client.is_connected:
            return True
        async with self._connect_lock:
            if self.client and self.client.is_connected:
                return True
            try:
                address = await self._resolve_address()
            except Exception as exc:
                self._show_error(str(exc))
                return False
            self.log(f"[CONNECT] {address}")
            client = BleakClient(address, timeout=config.CONNECT_TIMEOUT)
            try:
                await client.connect()
            except BleakError as exc:
                self._show_error(f"Connect failed: {exc}")
                return False
            self.client = client
            self.device_address = address
            self.connect_button.setEnabled(False)
            self._set_controls_enabled(True)
            await self._apply_idle_state("connect")
            self.log("[STATE] connected")
            return True

    async def _apply_idle_state(self, reason: str) -> None:
        if not self.client or not self.client.is_connected:
            return
        try:
            await self._send_primary_command("LED OFF", b"\x00")
        except BleakError as exc:
            self.log(f"[WARN] LED OFF failed ({reason}): {exc}")
        try:
            await self._send_adv_command("Rear OFF", bytes([CMD_SET_REAR_COLOR, 0x00, 0x00, 0x00]))
        except BleakError as exc:
            self.log(f"[WARN] Rear OFF failed ({reason}): {exc}")

    async def _resolve_address(self) -> str:
        if self.device_address in (None, ""):
            target_addr = getattr(config, "TARGET_ADDR", None)
            if target_addr:
                self.device_address = target_addr
            else:
                devices = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
                target = next((d for d in devices if d.name and config.TARGET_NAME in d.name), None)
                if not target:
                    raise RuntimeError("Target not found by name")
                self.device_address = target.address
        return self.device_address

    async def _disconnect(self) -> None:
        if self.client:
            try:
                if self.client.is_connected:
                    await self._apply_idle_state("disconnect")
                    await self.client.disconnect()
                    self.log("[STATE] disconnected")
            finally:
                self.client = None
        self._set_controls_enabled(False)
        self.connect_button.setEnabled(True)

    async def _send_primary_command(self, label: str, payload: bytes) -> None:
        await self.client.write_gatt_char(
            config.CHR_UUID,
            payload,
            response=config.WRITE_RESPONSE,
        )
        self.log(f"[WRITE] {label} :: {payload.hex()}")

    async def _send_adv_command(self, label: str, payload: bytes) -> None:
        await self.client.write_gatt_char(
            config.ADV_CHR_UUID,
            payload,
            response=config.WRITE_RESPONSE,
        )
        self.log(f"[ADV] {label} :: {payload.hex()}")

    async def _send_rear_color(self, color: QColor) -> None:
        if not await self._ensure_connected():
            return
        payload = bytes([CMD_SET_REAR_COLOR, color.red(), color.green(), color.blue()])
        await self._send_adv_command(
            f"Rear color = ({color.red()}, {color.green()}, {color.blue()})",
            payload,
        )

    async def _send_rear_off(self) -> None:
        if not await self._ensure_connected():
            return
        payload = bytes([CMD_SET_REAR_COLOR, 0x00, 0x00, 0x00])
        await self._send_adv_command("Rear OFF", payload)

    # --------------------------- UI events ---------------------------
    def _on_connect_clicked(self) -> None:
        self._run_async(self._ensure_connected())

    def _on_disconnect_clicked(self) -> None:
        self._run_async(self._disconnect())

    def _on_color_selected(self, color: QColor) -> None:
        if self._building_ui:
            return
        self._current_color = color
        self.color_wheel.set_color(color, emit=False)
        self._run_async(self._send_rear_color(color))

    def _on_rear_off_clicked(self) -> None:
        self._run_async(self._send_rear_off())

    def _show_error(self, message: str) -> None:
        if not self.isVisible():
            return
        self.log(f"[ERROR] {message}")
        QMessageBox.critical(self, "Error", message)

    def closeEvent(self, event):
        for task in list(self._tasks):
            task.cancel()
        self._tasks.clear()
        self._run_async(self._disconnect())
        super().closeEvent(event)


def main() -> None:
    app = QApplication.instance() or QApplication([])
    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    window = D10BleController()
    window.resize(440, 360)
    window.show()

    app.aboutToQuit.connect(loop.stop)

    with loop:
        loop.run_forever()


if __name__ == "__main__":
    main()


