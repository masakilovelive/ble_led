"""GUI BLE LED controller using PySide6, qasync, and bleak."""

import asyncio
import math
from typing import Optional, Set

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError
from PySide6.QtCore import QPoint, QSignalBlocker, Qt, Signal, QTimer
from PySide6.QtGui import QColor, QImage, QPainter, QPen
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSlider,
    QVBoxLayout,
    QWidget,
    QPlainTextEdit,
)
import qasync

import config

CMD_SET_BRIGHTNESS = 0x01
CMD_SET_COLOR = 0x02
CMD_START_RAINBOW = 0x03
CMD_STOP_RAINBOW = 0x04
CMD_ACCEL_MODE = 0x06
CMD_SET_FRONT_COLOR = 0x07
CMD_SET_REAR_COLOR = 0x08
CMD_SET_OUTPUT_ENABLE = 0x09

PALETTE = [
    ("Red", QColor("#ff0000")),
    ("Blue", QColor("#0000ff")),
    ("Yellow", QColor("#ffff00")),
    ("Green", QColor("#00ff00")),
    ("Purple", QColor("#800080")),
]


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

class LedBleController(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("BLE LED Controller")
        self.client: Optional[BleakClient] = None
        self.device_address: Optional[str] = None
        self.accel_enabled = False
        self._current_color = QColor(255, 120, 40)
        self._front_color = QColor(0, 0, 0)
        self._rear_color = QColor(0, 0, 0)
        self._output_enabled = False
        self._pending_brightness = 128
        self._front_buttons = []
        self._rear_buttons = []
        self._building_ui = True
        self._tasks: Set[asyncio.Task] = set()
        self._connect_lock = asyncio.Lock()
        self._setup_ui()
        self._building_ui = False

    # --------------------------- UI ---------------------------
    def _setup_ui(self) -> None:
        layout = QVBoxLayout()
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        # Connection controls
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

        # Output enable
        output_layout = QHBoxLayout()
        output_layout.addWidget(QLabel("Output"))
        self.output_toggle = QCheckBox("Enable Output")
        self.output_toggle.setEnabled(False)
        self.output_toggle.toggled.connect(self._on_output_toggled)
        output_layout.addWidget(self.output_toggle)
        output_layout.addStretch()
        layout.addLayout(output_layout)

        # Power toggle (hidden)
        self.power_toggle = QCheckBox()
        self.power_toggle.setEnabled(False)
        self.power_toggle.setVisible(False)
        self.power_toggle.toggled.connect(self._on_power_toggled)

        # Brightness slider (hidden)
        self.brightness_slider = QSlider(Qt.Horizontal)
        self.brightness_slider.setRange(0, 255)
        self.brightness_slider.setValue(128)
        self.brightness_slider.setEnabled(False)
        self.brightness_slider.setVisible(False)
        self.brightness_slider.valueChanged.connect(self._on_brightness_changed)
        self._pending_brightness = self.brightness_slider.value()
        self._brightness_timer = QTimer(self)
        self._brightness_timer.setSingleShot(True)
        self._brightness_timer.timeout.connect(self._commit_pending_brightness)

        # Color wheel
        self.color_wheel = ColorWheel(220)
        self.color_wheel.setEnabled(False)
        self.color_wheel.colorSelected.connect(self._on_color_selected)
        layout.addWidget(self.color_wheel, alignment=Qt.AlignHCenter)
        self.color_wheel.set_color(self._current_color, emit=False)

        # Preset swatches
        swatch_layout = QHBoxLayout()
        swatch_layout.setSpacing(10)
        swatch_layout.setAlignment(Qt.AlignHCenter)
        self._swatch_buttons = []
        swatch_colors = [
            QColor("#ff3b30"),
            QColor("#ffd60a"),
            QColor("#34c759"),
            QColor("#0ad3ff"),
            QColor("#0a60ff"),
            QColor("#af52de"),
            QColor("#ffffff"),
        ]
        for color in swatch_colors:
            button = QPushButton()
            button.setFixedSize(36, 36)
            button.setEnabled(False)
            button.setStyleSheet(
                f"background-color: {color.name()}; "
                "border: 1px solid #666666; border-radius: 8px;"
            )
            button.clicked.connect(self._make_swatch_handler(color))
            self._swatch_buttons.append(button)
            swatch_layout.addWidget(button)
        layout.addLayout(swatch_layout)

        palette_layout = QHBoxLayout()
        front_layout = QVBoxLayout()
        front_layout.addWidget(QLabel("FRONT (D9)"))
        front_row = QHBoxLayout()
        for label, color in PALETTE:
            button = QPushButton(label)
            button.setFixedSize(72, 28)
            button.setEnabled(False)
            button.setStyleSheet(
                f"background-color: {color.name()}; "
                "border: 1px solid #666666; border-radius: 6px;"
            )
            button.clicked.connect(self._make_palette_handler(True, color))
            self._front_buttons.append(button)
            front_row.addWidget(button)
        front_layout.addLayout(front_row)
        palette_layout.addLayout(front_layout)

        rear_layout = QVBoxLayout()
        rear_layout.addWidget(QLabel("REAR (D10)"))
        rear_row = QHBoxLayout()
        for label, color in PALETTE:
            button = QPushButton(label)
            button.setFixedSize(72, 28)
            button.setEnabled(False)
            button.setStyleSheet(
                f"background-color: {color.name()}; "
                "border: 1px solid #666666; border-radius: 6px;"
            )
            button.clicked.connect(self._make_palette_handler(False, color))
            self._rear_buttons.append(button)
            rear_row.addWidget(button)
        rear_layout.addLayout(rear_row)
        palette_layout.addLayout(rear_layout)

        layout.addLayout(palette_layout)

        test_layout = QHBoxLayout()
        test_layout.addWidget(QLabel("Pin tests"))
        self.test_d8_button = QPushButton("Test D8 (MAIN)")
        self.test_d8_button.setEnabled(False)
        self.test_d8_button.clicked.connect(self._on_test_d8_clicked)
        test_layout.addWidget(self.test_d8_button)
        self.test_front_button = QPushButton("Test D9 (FRONT)")
        self.test_front_button.setEnabled(False)
        self.test_front_button.clicked.connect(self._on_test_front_clicked)
        test_layout.addWidget(self.test_front_button)
        test_layout.addStretch()
        layout.addLayout(test_layout)

        rainbow_layout = QHBoxLayout()
        self.interval_edit = QLineEdit("40")
        self.interval_edit.setEnabled(False)
        rainbow_layout.addWidget(QLabel("Rainbow interval (ms)"))
        rainbow_layout.addWidget(self.interval_edit)
        self.rainbow_button = QPushButton("Start Rainbow")
        self.rainbow_button.setEnabled(False)
        self.rainbow_button.clicked.connect(self._on_rainbow_clicked)
        rainbow_layout.addWidget(self.rainbow_button)
        self.stop_rainbow_button = QPushButton("Stop Rainbow")
        self.stop_rainbow_button.setEnabled(False)
        self.stop_rainbow_button.clicked.connect(lambda: self._run_async(self._send_rainbow(False)))
        rainbow_layout.addWidget(self.stop_rainbow_button)
        layout.addLayout(rainbow_layout)

        self.accel_button = QPushButton("Acceleration Mode: OFF")
        self.accel_button.setEnabled(False)
        self.accel_button.clicked.connect(self._on_accel_clicked)
        layout.addWidget(self.accel_button)

        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        layout.addWidget(self.log_view)

        self.setLayout(layout)

    def _set_controls_enabled(self, connected: bool) -> None:
        self.disconnect_button.setEnabled(connected)
        self.output_toggle.setEnabled(connected)
        self.power_toggle.setEnabled(connected)
        self.brightness_slider.setEnabled(connected)
        self.color_wheel.setEnabled(connected)
        for button in getattr(self, "_swatch_buttons", []):
            button.setEnabled(connected)
        for button in getattr(self, "_front_buttons", []):
            button.setEnabled(connected)
        for button in getattr(self, "_rear_buttons", []):
            button.setEnabled(connected)
        self.test_d8_button.setEnabled(connected)
        self.test_front_button.setEnabled(connected)
        self.interval_edit.setEnabled(connected)
        self.rainbow_button.setEnabled(connected)
        self.stop_rainbow_button.setEnabled(connected)
        self.accel_button.setEnabled(connected)
        if not connected:
            self._brightness_timer.stop()
            self._set_power_checked(False)
            blocker = QSignalBlocker(self.output_toggle)
            self.output_toggle.setChecked(False)
            self._output_enabled = False
            _ = blocker

    def _set_power_checked(self, state: bool) -> None:
        blocker = QSignalBlocker(self.power_toggle)
        self.power_toggle.setChecked(state)

    def _schedule_brightness_send(self, value: int) -> None:
        self._pending_brightness = int(value)
        if not self.brightness_slider.isEnabled():
            return
        # 30ms debounce keeps UI responsive while avoiding BLE flooding.
        self._brightness_timer.start(30)

    def _commit_pending_brightness(self) -> None:
        if self._building_ui or not self._output_enabled:
            return
        value = self._pending_brightness
        self._run_async(self._send_brightness(value))

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

    async def _send_output_enable(self, enabled: bool) -> None:
        payload = bytes([CMD_SET_OUTPUT_ENABLE, 0x01 if enabled else 0x00])
        label = "Output Enable" if enabled else "Output Disable"
        await self._send_adv_command(label, payload)

    async def _ensure_output_enabled(self, reason: str) -> bool:
        if self._output_enabled:
            return True
        if not await self._ensure_connected():
            return False
        try:
            await self._send_output_enable(True)
        except BleakError as exc:
            self._show_error(f"Output enable failed ({reason}): {exc}")
            return False
        self._output_enabled = True
        blocker = QSignalBlocker(self.output_toggle)
        self.output_toggle.setChecked(True)
        _ = blocker
        self.log(f"[STATE] Output enabled ({reason})")
        return True

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
            self._output_enabled = False
            blocker = QSignalBlocker(self.output_toggle)
            self.output_toggle.setChecked(False)
            _ = blocker
            self._set_controls_enabled(True)
            self.accel_enabled = False
            self.accel_button.setText("Acceleration Mode: OFF")
            self._set_power_checked(False)
            await self._apply_idle_state("connect")
            self.log("[STATE] connected")
            return True

    async def _apply_idle_state(self, reason: str) -> None:
        if not self.client or not self.client.is_connected:
            return
        try:
            await self._send_adv_command("Output Disable", bytes([CMD_SET_OUTPUT_ENABLE, 0x00]))
        except BleakError as exc:
            self.log(f"[WARN] Output disable failed ({reason}): {exc}")
        except Exception as exc:
            self.log(f"[WARN] Output disable error ({reason}): {exc}")
        try:
            await self._send_adv_command("Rainbow stop", bytes([CMD_STOP_RAINBOW]))
        except BleakError as exc:
            self.log(f"[WARN] Rainbow stop failed ({reason}): {exc}")
        except Exception as exc:
            self.log(f"[WARN] Rainbow stop error ({reason}): {exc}")
        try:
            await self._send_primary_command("LED OFF", b"\x00")
        except BleakError as exc:
            self.log(f"[WARN] LED OFF failed ({reason}): {exc}")
        except Exception as exc:
            self.log(f"[WARN] LED OFF error ({reason}): {exc}")
        try:
            await self._send_adv_command("Accel mode OFF", bytes([CMD_ACCEL_MODE, 0x00]))
        except BleakError as exc:
            self.log(f"[WARN] Accel OFF failed ({reason}): {exc}")
        except Exception as exc:
            self.log(f"[WARN] Accel OFF error ({reason}): {exc}")
        try:
            await self._send_adv_command("Front OFF", bytes([CMD_SET_FRONT_COLOR, 0x00, 0x00, 0x00]))
        except BleakError as exc:
            self.log(f"[WARN] Front OFF failed ({reason}): {exc}")
        except Exception as exc:
            self.log(f"[WARN] Front OFF error ({reason}): {exc}")
        try:
            await self._send_adv_command("Rear OFF", bytes([CMD_SET_REAR_COLOR, 0x00, 0x00, 0x00]))
        except BleakError as exc:
            self.log(f"[WARN] Rear OFF failed ({reason}): {exc}")
        except Exception as exc:
            self.log(f"[WARN] Rear OFF error ({reason}): {exc}")
        self._set_power_checked(False)

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
        self.accel_enabled = False
        self.accel_button.setText("Acceleration Mode: OFF")
        self.connect_button.setEnabled(True)

    async def _send_power(self, state: bool) -> None:
        if not await self._ensure_connected():
            return
        payload = b"\x01" if state else b"\x00"
        await self._send_primary_command(f"LED {'ON' if state else 'OFF'}", payload)
        self._set_power_checked(state)

    async def _send_brightness(self, value: int) -> None:
        if not await self._ensure_output_enabled("brightness"):
            return
        if not self.power_toggle.isChecked():
            await self._send_power(True)
        payload = bytes([CMD_SET_BRIGHTNESS, value])
        await self._send_adv_command(f"Brightness = {value}", payload)

    async def _send_color(self, r: int, g: int, b: int) -> None:
        if not await self._ensure_output_enabled("color"):
            return
        if not self.power_toggle.isChecked():
            await self._send_power(True)
        payload = bytes([CMD_SET_COLOR, r, g, b])
        await self._send_adv_command(f"Color = ({r}, {g}, {b})", payload)

    async def _send_front_color(self, color: QColor) -> None:
        self._front_color = color
        if not await self._ensure_output_enabled("front"):
            return
        payload = bytes([CMD_SET_FRONT_COLOR, color.red(), color.green(), color.blue()])
        await self._send_adv_command(
            f"Front color = ({color.red()}, {color.green()}, {color.blue()})",
            payload,
        )

    async def _send_rear_color(self, color: QColor) -> None:
        self._rear_color = color
        if not await self._ensure_output_enabled("rear"):
            return
        payload = bytes([CMD_SET_REAR_COLOR, color.red(), color.green(), color.blue()])
        await self._send_adv_command(
            f"Rear color = ({color.red()}, {color.green()}, {color.blue()})",
            payload,
        )

    async def _send_front_test(self) -> None:
        if not await self._ensure_output_enabled("front test"):
            return
        await self._send_adv_command("Rear OFF", bytes([CMD_SET_REAR_COLOR, 0x00, 0x00, 0x00]))
        await self._send_adv_command("Front test", bytes([CMD_SET_FRONT_COLOR, 0xFF, 0x00, 0x00]))

    async def _send_d8_test(self) -> None:
        if not await self._ensure_output_enabled("D8 test"):
            return
        await self._send_adv_command("Front OFF", bytes([CMD_SET_FRONT_COLOR, 0x00, 0x00, 0x00]))
        await self._send_adv_command("Rear OFF", bytes([CMD_SET_REAR_COLOR, 0x00, 0x00, 0x00]))
        if not self.power_toggle.isChecked():
            await self._send_power(True)
        payload = bytes([CMD_SET_COLOR, 0xFF, 0x00, 0x00])
        await self._send_adv_command("D8 test color", payload)

    async def _send_rainbow(self, start: bool, interval: int = 40) -> None:
        if not await self._ensure_output_enabled("rainbow"):
            return
        if start:
            await self._send_power(True)
            payload = bytes([CMD_START_RAINBOW]) + interval.to_bytes(2, "little")
            await self._send_adv_command(f"Rainbow start ({interval} ms)", payload)
        else:
            payload = bytes([CMD_STOP_RAINBOW])
            await self._send_adv_command("Rainbow stop", payload)

    async def _send_accel_mode(self, enable: bool) -> None:
        if not await self._ensure_output_enabled("accel"):
            return
        if enable:
            await self._send_power(True)
        payload = bytes([CMD_ACCEL_MODE, 0x01 if enable else 0x00])
        await self._send_adv_command(f"Accel mode {'ON' if enable else 'OFF'}", payload)
        self.accel_enabled = enable
        self.accel_button.setText(f"Acceleration Mode: {'ON' if enable else 'OFF'}")

    async def _handle_output_toggle(self, enable: bool) -> None:
        if enable:
            if not await self._ensure_connected():
                blocker = QSignalBlocker(self.output_toggle)
                self.output_toggle.setChecked(False)
                self._output_enabled = False
                _ = blocker
                return
            try:
                await self._send_output_enable(True)
                await self._send_front_color(self._front_color)
                await self._send_rear_color(self._rear_color)
                if self.power_toggle.isChecked():
                    await self._send_brightness(self._pending_brightness)
                    await self._send_color(self._current_color.red(), self._current_color.green(), self._current_color.blue())
            except BleakError as exc:
                self._show_error(f"Output enable failed: {exc}")
                blocker = QSignalBlocker(self.output_toggle)
                self.output_toggle.setChecked(False)
                self._output_enabled = False
                _ = blocker
                return
            self._output_enabled = True
            return

        if self.client and self.client.is_connected:
            try:
                await self._send_output_enable(False)
            except BleakError as exc:
                self.log(f"[WARN] Output disable failed: {exc}")
        self._output_enabled = False

    # --------------------------- UI events ---------------------------
    def _on_connect_clicked(self) -> None:
        self._run_async(self._ensure_connected())

    def _on_disconnect_clicked(self) -> None:
        self._run_async(self._disconnect())

    def _on_output_toggled(self, checked: bool) -> None:
        if self._building_ui:
            return
        self._run_async(self._handle_output_toggle(checked))

    def _on_brightness_changed(self, value: int) -> None:
        if self._building_ui:
            return
        if not self._output_enabled:
            self._pending_brightness = int(value)
            self._set_power_checked(True)
            return
        self._schedule_brightness_send(value)

    def _on_power_toggled(self, checked: bool) -> None:
        if self._building_ui:
            return
        if not self.power_toggle.isEnabled():
            self._set_power_checked(False)
            return
        if not self._output_enabled:
            return
        self._run_async(self._send_power(checked))

    def _on_color_selected(self, color: QColor) -> None:
        if self._building_ui:
            return
        self._current_color = color
        self.color_wheel.set_color(color, emit=False)
        self._run_async(self._send_color(color.red(), color.green(), color.blue()))

    def _make_swatch_handler(self, color: QColor):
        def handler() -> None:
            if not self.color_wheel.isEnabled():
                return
            self.color_wheel.set_color(color, emit=False)
            self._on_color_selected(color)

        return handler

    def _make_palette_handler(self, front: bool, color: QColor):
        def handler() -> None:
            if front:
                self._run_async(self._send_front_color(color))
            else:
                self._run_async(self._send_rear_color(color))

        return handler

    def _on_rainbow_clicked(self) -> None:
        text = self.interval_edit.text().strip()
        try:
            interval = int(text, 0) if text else 40
            interval = max(1, interval)
        except ValueError:
            self._show_error("Interval must be an integer (ms)")
            return
        self._run_async(self._send_rainbow(True, interval))

    def _on_accel_clicked(self) -> None:
        target = not self.accel_enabled
        self._run_async(self._send_accel_mode(target))

    def _on_test_d8_clicked(self) -> None:
        self._run_async(self._send_d8_test())

    def _on_test_front_clicked(self) -> None:
        self._run_async(self._send_front_test())

    # --------------------------- utilities ---------------------------
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

    window = LedBleController()
    window.resize(480, 360)
    window.show()

    app.aboutToQuit.connect(loop.stop)

    with loop:
        loop.run_forever()


if __name__ == "__main__":
    main()

