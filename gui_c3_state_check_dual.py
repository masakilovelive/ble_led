"""ESP32-C3 dual device BLE state check GUI (A/B)."""

from __future__ import annotations

import asyncio
from collections import Counter
import csv
import json
import re
import shutil
import subprocess
import time
import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError
from PySide6.QtCore import Qt, QThread, Signal, QTimer, QUrl
from PySide6.QtGui import QColor, QPen, QPainter
from PySide6.QtCharts import (
    QCategoryAxis,
    QChart,
    QChartView,
    QLineSeries,
    QValueAxis,
)
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QColorDialog,
    QButtonGroup,
    QFileDialog,
    QFrame,
    QGridLayout,
    QGraphicsScene,
    QGraphicsView,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QProgressBar,
    QPlainTextEdit,
    QRadioButton,
    QScrollArea,
    QSlider,
    QSpinBox,
    QSizePolicy,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)
import qasync
try:
    from PySide6.QtSvgWidgets import QGraphicsSvgItem
except Exception:
    QGraphicsSvgItem = None
try:
    from PySide6.QtWebEngineWidgets import QWebEngineView
except Exception:
    QWebEngineView = None

import config

DEVICE_PATTERN = re.compile(r"XIAO-ESP32C3-LED-(?:STOCK)?(\d+)$")
MAC_PATTERN = re.compile(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")
MCU_STATE_PATTERN = re.compile(r"\[STATE\]\s*([A-Z_]+)(?:\s+(.*))?$")
PAGE_SIZE = 25
COM_PORT_NONE = "-"
PREFER_WRITE_COMMAND_WHEN_AVAILABLE = True
ALLOW_WRITE_COMMAND_FALLBACK_ON_AUTH_ERROR = True
COLOR_APPLY_DEBOUNCE_MS = 60
AUTH_PAIR_RETRY_DELAY_S = 1.5
AUTH_ENABLE_RECOVER_RECONNECT = False
AUTH_ENABLE_REBOND = False
AUTH_EVENT_TIMEOUT_S = 1.0
PROFILE_DISCOVERY_GRACE_S = 3.0
PROFILE_DISCOVERY_POLL_S = 0.25
PROFILE_MISSING_BACKOFF_S = 15.0
PAIR_CONNECT_SETTLE_S = 2.5
UNEXPECTED_LINK_DROP_BACKOFF_S = 12.0
UNEXPECTED_LINK_DROP_EARLY_S = 3.0
CONNECT_PAIR_ON_INITIAL = False
FAILURE_LOG_DEBOUNCE_S = 2.0
# Calibrated against DMM readings on current stockA/stockB hardware.
BATTERY_DIVIDER_RATIO = 2.01
BATTERY_EMPTY_V = 3.2
BATTERY_FULL_V = 4.2

CONNECTION_FAILURE_NOTES = {
    "PROFILE_MISSING": "Connected but the custom BLE service/characteristic was not exposed. Often only 0x1800/0x1801 are visible.",
    "STATUS_133_GATT_ERROR": "Android/Windows GATT generic failure during connect or service use.",
    "REASON_0X0016": "Disconnect/auth/bond related reason 0x0016 was observed.",
    "API_CLOSE_EVT": "App side or platform side API close event terminated the GATT client.",
    "APP_RESET_OR_DEREGISTER": "GATT client deregistered or app BLE stack was reset/closed.",
    "SERVICE_DISCOVERY_FAIL": "Service discovery step itself failed before usable characteristics were found.",
    "CCCD_SUBSCRIBE_FAIL": "Notify/indication subscription failed.",
    "NON_BLE_LOG_MIXED": "Non-BLE Android log lines polluted the parse window.",
    "LOG_MIXED_OLD_DATA": "Old cycle data and current cycle data were mixed in one analysis window.",
    "ADV_NOT_FOUND": "Expected advertising name was not discovered.",
    "ADV_NOT_FOUND_OR_NAME_MISMATCH": "Selected device name was not present in current scan results.",
    "CONNECT_FAILED": "Connection attempt timed out or was rejected.",
    "GATT_TIMEOUT_OR_READ_FAIL": "GATT read/write stage did not complete in time.",
    "DISCONNECT_INCOMPLETE": "Disconnect sequence did not complete cleanly.",
    "INSUFFICIENT_AUTHENTICATION": "Write/read failed with Protocol Error 0x05 or explicit insufficient authentication.",
    "CHAR_NOT_FOUND": "The expected characteristic UUID was missing after reconnect or service refresh.",
    "UNEXPECTED_LINK_DROP": "Link dropped unexpectedly before profile discovery stabilized.",
    "PROFILE_MISSING_LATCHED": "Reconnect was blocked because PROFILE_MISSING had been latched earlier.",
    "SERIAL_TRIGGERED_RESET_OR_LINK_DROP": "Opening the serial monitor likely reset the MCU or dropped the BLE link.",
    "OTHER": "Failure observed but not yet classified in detail.",
}

# LED control commands (match Android app)
CMD_SET_BRIGHTNESS = 0x01
CMD_START_RAINBOW = 0x03
CMD_STOP_RAINBOW = 0x04
CMD_SET_FRONT_COLOR = 0x07
CMD_SET_REAR_COLOR = 0x08
CMD_SET_OUTPUT_ENABLE = 0x09
CMD_PATTERN_MODE = 0x0C


@dataclass
class RegisterEntry:
    n_value: int
    a_name: str
    a_port: str
    a_mac: str
    b_name: str
    b_port: str
    b_mac: str

    def to_row(self) -> list[str]:
        return [
            str(self.n_value),
            self.a_name,
            self.a_port,
            self.a_mac,
            self.b_name,
            self.b_port,
            self.b_mac,
        ]

    @classmethod
    def from_dict(cls, data: dict) -> "RegisterEntry":
        return cls(
            n_value=int(data.get("n_value", 0)),
            a_name=str(data.get("a_name", "")),
            a_port=str(data.get("a_port", "")),
            a_mac=str(data.get("a_mac", "")),
            b_name=str(data.get("b_name", "")),
            b_port=str(data.get("b_port", "")),
            b_mac=str(data.get("b_mac", "")),
        )

    def to_dict(self) -> dict:
        return {
            "n_value": self.n_value,
            "a_name": self.a_name,
            "a_port": self.a_port,
            "a_mac": self.a_mac,
            "b_name": self.b_name,
            "b_port": self.b_port,
            "b_mac": self.b_mac,
        }


class LogcatWorker(QThread):
    line_ready = Signal(str)
    error = Signal(str)

    def __init__(self, adb_path: str, filter_text: str) -> None:
        super().__init__()
        self._adb_path = adb_path
        self._filter_text = filter_text
        self._stop = False
        self._process: Optional[subprocess.Popen] = None

    def run(self) -> None:
        command = [self._adb_path, "logcat", "-v", "time", "-T", "1"]
        try:
            self._process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
        except Exception as exc:
            self.error.emit(f"adb logcat failed: {exc}")
            return
        assert self._process.stdout is not None
        for line in iter(self._process.stdout.readline, ""):
            if self._stop:
                break
            if not line:
                break
            line = line.strip()
            if self._filter_text and self._filter_text not in line:
                continue
            self.line_ready.emit(line)
        self._terminate()

    def stop(self) -> None:
        self._stop = True
        self._terminate()

    def _terminate(self) -> None:
        if self._process and self._process.poll() is None:
            try:
                self._process.terminate()
            except Exception:
                pass


class SerialWorker(QThread):
    line_ready = Signal(str)
    error = Signal(str)

    def __init__(self, port: str, baud: int) -> None:
        super().__init__()
        self._port = port
        self._baud = baud
        self._stop = False
        self._serial = None

    def run(self) -> None:
        try:
            import serial
        except Exception as exc:
            self.error.emit(f"pyserial missing: {exc}")
            return
        try:
            self._serial = serial.Serial(self._port, self._baud, timeout=0.5)
        except Exception as exc:
            self.error.emit(f"serial open failed: {exc}")
            return
        while not self._stop:
            try:
                raw = self._serial.readline()
            except Exception as exc:
                self.error.emit(f"serial read error: {exc}")
                break
            if not raw:
                continue
            try:
                line = raw.decode("utf-8", errors="replace").strip()
            except Exception:
                line = str(raw)
            if line:
                self.line_ready.emit(line)
        self._close()

    def stop(self) -> None:
        self._stop = True
        self._close()

    def _close(self) -> None:
        if self._serial:
            try:
                self._serial.close()
            except Exception:
                pass


class SvgZoomView(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self._scene = None
        self._svg_item = None
        self._zoom = 1.0
        self._use_web = QWebEngineView is not None
        self._loaded_path = ""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        if self._use_web:
            self._web_view = QWebEngineView(self)
            self._web_view.setContextMenuPolicy(Qt.NoContextMenu)
            layout.addWidget(self._web_view)
            self._graphics_view = None
        else:
            self._scene = QGraphicsScene(self)
            self._graphics_view = QGraphicsView(self)
            self._graphics_view.setScene(self._scene)
            self._graphics_view.setDragMode(QGraphicsView.ScrollHandDrag)
            self._graphics_view.setTransformationAnchor(QGraphicsView.AnchorUnderMouse)
            self._graphics_view.setResizeAnchor(QGraphicsView.AnchorViewCenter)
            self._graphics_view.setRenderHint(QPainter.Antialiasing, True)
            layout.addWidget(self._graphics_view)
            self._web_view = None

    def load_svg(self, path: str) -> bool:
        self._loaded_path = path
        if self._use_web and self._web_view is not None:
            self._web_view.setUrl(QUrl.fromLocalFile(str(Path(path).resolve())))
            self.zoom_reset_100()
            return True
        if QGraphicsSvgItem is None or self._scene is None or self._graphics_view is None:
            return False
        self._scene.clear()
        item = QGraphicsSvgItem(path)
        if not item.renderer().isValid():
            self._svg_item = None
            return False
        self._scene.addItem(item)
        self._svg_item = item
        self._scene.setSceneRect(item.boundingRect())
        self.fit_all()
        return True

    def fit_all(self) -> None:
        if self._use_web and self._web_view is not None:
            self._web_view.setZoomFactor(1.0)
            self._zoom = 1.0
            return
        if not self._svg_item or self._graphics_view is None or self._scene is None:
            return
        self._graphics_view.resetTransform()
        self._graphics_view.fitInView(self._scene.sceneRect(), Qt.KeepAspectRatio)
        self._zoom = 1.0

    def zoom_by(self, factor: float) -> None:
        if self._use_web and self._web_view is not None:
            self._zoom = max(0.1, min(8.0, self._zoom * factor))
            self._web_view.setZoomFactor(self._zoom)
            return
        if not self._svg_item or self._graphics_view is None:
            return
        self._graphics_view.scale(factor, factor)
        self._zoom *= factor

    def zoom_reset_100(self) -> None:
        if self._use_web and self._web_view is not None:
            self._zoom = 1.0
            self._web_view.setZoomFactor(1.0)
            return
        if not self._svg_item or self._graphics_view is None:
            return
        self._graphics_view.resetTransform()
        self._zoom = 1.0

    def wheelEvent(self, event) -> None:  # type: ignore[override]
        if self._use_web:
            super().wheelEvent(event)
            return
        if not self._svg_item:
            super().wheelEvent(event)
            return
        if event.angleDelta().y() > 0:
            self.zoom_by(1.15)
        else:
            self.zoom_by(1.0 / 1.15)


class DualStateCheck(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("ESP32-C3 Dual State Checklist (BLE)")
        self.resize(1920, 1080)
        self.setMinimumSize(1400, 820)

        self._tasks: set[asyncio.Task] = set()
        self._scan_lock = asyncio.Lock()
        self._connect_lock = asyncio.Lock()
        self._auto_test_task: Optional[asyncio.Task] = None
        self._endurance_task: Optional[asyncio.Task] = None
        self._endurance_stop_requested = False
        self._endurance_cycle_records: list[dict] = []
        self._endurance_report_path: Optional[Path] = None
        self._endurance_active_cycle: Optional[int] = None
        self._endurance_failure_counter: Counter = Counter()
        self._endurance_pass_count = 0
        self._endurance_fail_count = 0
        self._endurance_total_cycles = 0
        self._endurance_done_cycles = 0

        self._device_map: dict[str, str] = {}
        self._slots = ["A1", "B1", "A2", "B2"]
        self._pairs = [("A1", "B1"), ("A2", "B2")]
        self._pair_labels = ["Pair 1", "Pair 2"]
        self._desired_slot_names = {slot: "" for slot in self._slots}
        self._clients: dict[str, Optional[BleakClient]] = {
            slot: None for slot in self._slots
        }
        self._states: dict[str, str] = {slot: "DISCONNECT" for slot in self._slots}
        self._slot_last_voltage: dict[str, Optional[float]] = {
            slot: None for slot in self._slots
        }
        self._slot_output_enabled: dict[str, Optional[bool]] = {
            slot: None for slot in self._slots
        }
        self._slot_auth_state: dict[str, str] = {
            slot: "UNKNOWN" for slot in self._slots
        }
        self._slot_auth_error_latched: dict[str, bool] = {
            slot: False for slot in self._slots
        }
        self._slot_pair_tried: dict[str, bool] = {
            slot: False for slot in self._slots
        }
        self._slot_auth_recover_tried: dict[str, bool] = {
            slot: False for slot in self._slots
        }
        self._slot_rebond_tried: dict[str, bool] = {slot: False for slot in self._slots}
        self._slot_write_locks: dict[str, asyncio.Lock] = {
            slot: asyncio.Lock() for slot in self._slots
        }
        self._slot_write_pref: dict[str, bool] = {
            slot: (
                False
                if PREFER_WRITE_COMMAND_WHEN_AVAILABLE
                else bool(config.WRITE_RESPONSE)
            )
            for slot in self._slots
        }
        self._slot_write_cap_req: dict[str, bool] = {slot: True for slot in self._slots}
        self._slot_write_cap_cmd: dict[str, bool] = {slot: True for slot in self._slots}
        self._slot_adv_char_uuid: dict[str, str] = {
            slot: config.ADV_CHR_UUID for slot in self._slots
        }
        self._slot_adv_char_missing_latched: dict[str, bool] = {
            slot: False for slot in self._slots
        }
        self._slot_profile_missing_until: dict[str, float] = {
            slot: 0.0 for slot in self._slots
        }
        self._slot_profile_blocked: dict[str, bool] = {
            slot: False for slot in self._slots
        }
        self._slot_session_fixed: dict[str, bool] = {
            slot: False for slot in self._slots
        }
        self._slot_disconnect_expected: dict[str, bool] = {
            slot: False for slot in self._slots
        }
        self._slot_connected_since: dict[str, float] = {
            slot: 0.0 for slot in self._slots
        }
        self._slot_unexpected_disconnect_until: dict[str, float] = {
            slot: 0.0 for slot in self._slots
        }
        self._color_pair_index = 0
        self._color_edit_target = "A"
        self._color_zone = "TOP"
        self._color_cheat = False
        self._color_selected = QColor(255, 0, 0)
        self._color_heartbeat_color = QColor(255, 0, 0)
        self._color_hue = 0
        self._color_saturation = 255
        self._color_value = 255
        self._color_heartbeat_interval = 0.5
        self._color_heartbeat_level = "MIDDLE"
        self._color_picker_interacting = False
        self._color_apply_timer = QTimer(self)
        self._color_apply_timer.setSingleShot(True)
        self._color_apply_timer.setInterval(COLOR_APPLY_DEBOUNCE_MS)
        self._color_apply_timer.timeout.connect(self._flush_color_hsb_apply)
        self._color_apply_inflight = False
        self._color_apply_pending = False
        self._color_state: dict[str, dict] = {
            slot: {
                "front": QColor(255, 255, 255),
                "rear": QColor(255, 255, 255),
                "brightness": 200,
                "output": False,
                "mode": "off",
            }
            for slot in self._slots
        }
        self._color_heartbeat_tasks: dict[str, asyncio.Task] = {}
        self._pattern_tasks: dict[str, asyncio.Task] = {}
        self._pattern_pair_index = 0
        self._pattern_target = "A"
        self._pattern_zone = "ALL"
        self._pattern_selected = QColor(255, 0, 0)
        self._startup_wave_cycle_ms = 1000
        self._startup_wave_colors = [
            QColor(255, 0, 0),
            QColor(255, 128, 0),
            QColor(255, 255, 0),
            QColor(0, 255, 255),
            QColor(0, 128, 255),
        ]
        self._startup_wave_done_pairs = {0: False, 1: False}
        self._pair_sync_inflight = {0: False, 1: False}
        self._dpm_profile: dict[str, dict[str, Optional[float]]] = {
            "A": {"target_v": None, "pwm": None},
            "B": {"target_v": None, "pwm": None},
        }

        self._register_entries: list[RegisterEntry] = []
        self._page_index = 0
        self._sequence_events: list[dict] = []
        self._sequence_start: Optional[float] = None
        self._active_sequence_csv_path: Optional[Path] = None
        self._logcat_worker: Optional[LogcatWorker] = None
        self._serial_worker: Optional[SerialWorker] = None
        self._serial_color_handle = None
        self._serial_color_port: str = COM_PORT_NONE
        self._serial_color_baud = 115200
        self._serial_color_auto_apply = False
        self._serial_color_output_enabled = False
        self._serial_color_accel_enabled = False
        self._serial_color_pending_brightness = 255
        self._serial_color_brightness_timer = QTimer(self)
        self._serial_color_brightness_timer.setSingleShot(True)
        self._serial_color_brightness_timer.setInterval(40)
        self._serial_color_brightness_timer.timeout.connect(
            self._serial_color_commit_brightness
        )
        self._rssi_task: Optional[asyncio.Task] = None
        self._rssi_events: dict[str, list[tuple[float, Optional[int]]]] = {
            slot: [] for slot in self._slots
        }
        self._rssi_start: Optional[float] = None
        self._rssi_status_labels: dict[str, QLabel] = {}
        self._adb_path_guess = self._find_adb_path()
        self._android_conn_labels: dict[str, QLabel] = {}
        self._android_conn_status: dict[str, str] = {
            slot: "UNKNOWN" for slot in self._slots
        }
        # Android logcat sometimes omits MAC-level connect callbacks.
        # Keep a best-effort mapping from observed conn_id -> slot.
        self._android_connid_slot: dict[str, str] = {}
        self._mcu_last_slot: Optional[str] = None
        self._mcu_last_name: str = ""
        self._mcu_last_mac: str = ""
        self._no_connection_latched: dict[str, bool] = {slot: False for slot in self._slots}
        self._auth_watch_timers: dict[str, QTimer] = {}
        for slot in self._slots:
            timer = QTimer(self)
            timer.setSingleShot(True)
            timer.timeout.connect(lambda s=slot: self._on_auth_watch_timeout(s))
            self._auth_watch_timers[slot] = timer

        self._log_dir = Path(__file__).resolve().parent / "logs"
        self._log_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._log_path = self._log_dir / f"c3_state_check_{timestamp}.log"
        self._csv_log_path = self._log_dir / f"c3_state_check_{timestamp}.csv"
        self._failure_summary_path = self._log_dir / "connection_failure_summary.txt"
        self._failure_summary_state_path = self._log_dir / "connection_failure_summary_state.json"
        self._connection_failure_counter: Counter = Counter()
        self._connection_failure_first_seen: dict[str, str] = {}
        self._connection_failure_last_seen: dict[str, str] = {}
        self._connection_failure_last_message: dict[str, str] = {}
        self._connection_failure_last_detail: dict[str, str] = {}
        self._connection_failure_last_recorded_at: dict[str, float] = {}
        self._investigation_summary: dict[str, object] = (
            self._default_investigation_summary()
        )
        self._load_connection_failure_summary_state()
        self._write_connection_failure_summary()

        self._color_settings_path = Path(__file__).resolve().parent / "c3_color_settings.json"
        self._register_path = Path(__file__).resolve().parent / "c3_register.json"
        self._flash_sketch_dir = (
            Path(__file__).resolve().parent
            / "ble_led_app"
            / "ver1_esp32c3_stock1"
        )
        self._flash_cli_path = Path("C:/tools/arduino-cli/arduino-cli.exe")
        self._flash_fqbn = "esp32:esp32:XIAO_ESP32C3"

        self._load_color_settings()
        self._setup_ui()
        self._apply_pair2_no_connection_guard_ui()
        self._load_register()
        self._update_flash_names()
        self._refresh_endurance_visual_all()

    # --------------------------- UI ---------------------------
    def _setup_ui(self) -> None:
        layout = QVBoxLayout()
        self.tabs = QTabWidget()
        self.tabs.addTab(self._with_scroll(self._build_flash_tab()), "Flash")
        self.tabs.addTab(self._with_scroll(self._build_control_tab()), "Control")
        self.tabs.addTab(self._with_scroll(self._build_color_tab()), "Color")
        self.tabs.addTab(self._with_scroll(self._build_serial_color_tab()), "Serial D3D4")
        self.tabs.addTab(self._with_scroll(self._build_pattern_tab()), "Pattern")
        self.tabs.addTab(self._with_scroll(self._build_sequence_tab()), "Sequence")
        self.tabs.addTab(self._with_scroll(self._build_environment_tab()), "Environment")
        self.tabs.addTab(self._with_scroll(self._build_register_tab()), "Register")
        self.tabs.addTab(self._with_scroll(self._build_log_tab()), "Log")
        layout.addWidget(self.tabs)
        self.setLayout(layout)

    def _with_scroll(self, widget: QWidget) -> QScrollArea:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.NoFrame)
        scroll.setWidget(widget)
        return scroll

    def _build_flash_tab(self) -> QWidget:
        root = QWidget()
        layout = QVBoxLayout()

        settings_group = QGroupBox("Arduino CLI Settings")
        settings_layout = QVBoxLayout()

        cli_row = QHBoxLayout()
        cli_row.addWidget(QLabel("arduino-cli"))
        self.cli_path_edit = QLineEdit(str(self._flash_cli_path))
        cli_row.addWidget(self.cli_path_edit)
        settings_layout.addLayout(cli_row)

        fqbn_row = QHBoxLayout()
        fqbn_row.addWidget(QLabel("FQBN"))
        self.fqbn_edit = QLineEdit(self._flash_fqbn)
        fqbn_row.addWidget(self.fqbn_edit)
        settings_layout.addLayout(fqbn_row)

        sketch_row = QHBoxLayout()
        sketch_row.addWidget(QLabel("Sketch Folder"))
        self.sketch_edit = QLineEdit(str(self._flash_sketch_dir))
        sketch_row.addWidget(self.sketch_edit)
        settings_layout.addLayout(sketch_row)

        settings_group.setLayout(settings_layout)
        layout.addWidget(settings_group)

        status_group = QGroupBox("Flash Status")
        status_layout = QGridLayout()
        self.flash_slot_labels = {}
        for index, slot in enumerate(self._slots):
            status_label = QLabel(f"{slot}: IDLE")
            status_label.setAlignment(Qt.AlignCenter)
            self._set_label_style(status_label, "#444444", "#ffffff")
            status_layout.addWidget(status_label, index // 2, index % 2)
            self.flash_slot_labels[slot] = status_label
        status_group.setLayout(status_layout)
        layout.addWidget(status_group)

        pair_group = QGroupBox("Device Pairs (4 MCUs)")
        pair_layout = QVBoxLayout()

        self.pairs = []
        for idx, label in enumerate(self._pair_labels):
            row = QHBoxLayout()
            row.addWidget(QLabel(label))

            row.addWidget(QLabel("N"))
            n_edit = QLineEdit("1" if idx == 0 else "2")
            n_edit.setFixedWidth(60)
            row.addWidget(n_edit)

            a_name_label = QLabel("A: --")
            b_name_label = QLabel("B: --")
            row.addWidget(a_name_label)
            row.addWidget(b_name_label)

            a_status = QLabel("NG")
            b_status = QLabel("NG")
            self._set_label_style(a_status, "#444444", "#ffffff")
            self._set_label_style(b_status, "#444444", "#ffffff")
            row.addWidget(a_status)
            row.addWidget(b_status)

            a_port = QComboBox()
            b_port = QComboBox()
            a_port.addItem(COM_PORT_NONE)
            b_port.addItem(COM_PORT_NONE)
            row.addWidget(QLabel("A COM"))
            row.addWidget(a_port)
            row.addWidget(QLabel("B COM"))
            row.addWidget(b_port)

            n_edit.textChanged.connect(self._update_flash_names)
            self.pairs.append(
                {
                    "n_edit": n_edit,
                    "a_label": a_name_label,
                    "b_label": b_name_label,
                    "a_status": a_status,
                    "b_status": b_status,
                    "a_port": a_port,
                    "b_port": b_port,
                }
            )
            pair_layout.addLayout(row)

        pair_group.setLayout(pair_layout)
        layout.addWidget(pair_group)

        action_row = QHBoxLayout()
        self.detect_ports_button = QPushButton("Auto Detect COM")
        self.detect_ports_button.clicked.connect(self._auto_detect_ports)
        action_row.addWidget(self.detect_ports_button)

        self.refresh_all_com_button = QPushButton("Refresh All COM")
        self.refresh_all_com_button.clicked.connect(self._refresh_all_com_ports)
        action_row.addWidget(self.refresh_all_com_button)

        self.detect_ble_button = QPushButton("BLE Detect")
        self.detect_ble_button.clicked.connect(
            lambda: self._run_async(self._detect_ble_devices())
        )
        action_row.addWidget(self.detect_ble_button)

        self.auto_build_button = QPushButton("Auto Build")
        self.auto_build_button.clicked.connect(
            lambda: self._run_async(self._auto_build())
        )
        action_row.addWidget(self.auto_build_button)

        self.auto_flash_button = QPushButton("Auto Flash")
        self.auto_flash_button.clicked.connect(
            lambda: self._run_async(self._auto_flash())
        )
        action_row.addWidget(self.auto_flash_button)
        self.flash_status = QLabel("FLASH: IDLE")
        self.flash_status.setAlignment(Qt.AlignCenter)
        self._set_label_style(self.flash_status, "#444444", "#ffffff")
        action_row.addWidget(self.flash_status)
        action_row.addStretch()
        layout.addLayout(action_row)

        root.setLayout(layout)
        self._update_flash_names()
        return root

    def _build_control_tab(self) -> QWidget:
        root = QWidget()
        layout = QVBoxLayout()
        layout.setSpacing(10)

        header = QHBoxLayout()
        self.scan_button = QPushButton("Scan")
        self.scan_button.clicked.connect(self._on_scan_clicked)
        header.addWidget(self.scan_button)

        self.connect_both_button = QPushButton("Connect All")
        self.connect_both_button.clicked.connect(self._on_connect_all_clicked)
        header.addWidget(self.connect_both_button)

        self.connect_pair1_button = QPushButton("Connect Pair 1")
        self.connect_pair1_button.clicked.connect(self._on_connect_pair1_clicked)
        header.addWidget(self.connect_pair1_button)

        self.connect_pair2_button = QPushButton("Connect Pair 2")
        self.connect_pair2_button.clicked.connect(self._on_connect_pair2_clicked)
        header.addWidget(self.connect_pair2_button)

        self.connect_a2_only_button = QPushButton("Connect A2 Only")
        self.connect_a2_only_button.clicked.connect(
            self._on_connect_a2_only_clicked
        )
        header.addWidget(self.connect_a2_only_button)

        self.connect_b2_only_button = QPushButton("Connect B2 Only")
        self.connect_b2_only_button.clicked.connect(
            self._on_connect_b2_only_clicked
        )
        header.addWidget(self.connect_b2_only_button)

        self.clear_profile_latch_button = QPushButton("Clear Profile Latch")
        self.clear_profile_latch_button.clicked.connect(self._clear_profile_missing_latch)
        header.addWidget(self.clear_profile_latch_button)

        self.gatt_test_button = QPushButton("GATT Test")
        self.gatt_test_button.clicked.connect(
            lambda: self._run_async(self._gatt_test_all())
        )
        header.addWidget(self.gatt_test_button)

        self.disconnect_both_button = QPushButton("Disconnect All")
        self.disconnect_both_button.clicked.connect(self._on_disconnect_all_clicked)
        header.addWidget(self.disconnect_both_button)

        self.reconnect_test_button = QPushButton("Reconnect All Test")
        self.reconnect_test_button.clicked.connect(self._on_reconnect_all_test_clicked)
        header.addWidget(self.reconnect_test_button)

        self.auto_after_check = QCheckBox("Auto After Connect")
        header.addWidget(self.auto_after_check)

        self.auto_test_check = QCheckBox("Auto Test")
        self.auto_test_check.stateChanged.connect(self._on_auto_test_changed)
        header.addWidget(self.auto_test_check)

        header.addStretch()
        layout.addLayout(header)

        endurance_group = QGroupBox("Durability Test")
        endurance_layout = QGridLayout()
        endurance_layout.addWidget(QLabel("Cycles"), 0, 0)
        self.endurance_cycles_edit = QLineEdit("100")
        self.endurance_cycles_edit.setFixedWidth(80)
        endurance_layout.addWidget(self.endurance_cycles_edit, 0, 1)
        endurance_layout.addWidget(QLabel("Connect Wait (s)"), 0, 2)
        self.endurance_connect_wait_edit = QLineEdit("0.5")
        self.endurance_connect_wait_edit.setFixedWidth(80)
        endurance_layout.addWidget(self.endurance_connect_wait_edit, 0, 3)
        endurance_layout.addWidget(QLabel("Disconnect Wait (s)"), 0, 4)
        self.endurance_disconnect_wait_edit = QLineEdit("0.5")
        self.endurance_disconnect_wait_edit.setFixedWidth(80)
        endurance_layout.addWidget(self.endurance_disconnect_wait_edit, 0, 5)

        self.endurance_require_register_check = QCheckBox("Require Register Baseline")
        self.endurance_require_register_check.setChecked(True)
        endurance_layout.addWidget(self.endurance_require_register_check, 1, 0, 1, 2)
        self.endurance_run_gatt_check = QCheckBox("Run GATT/Battery Each Cycle")
        self.endurance_run_gatt_check.setChecked(True)
        endurance_layout.addWidget(self.endurance_run_gatt_check, 1, 2, 1, 2)
        self.endurance_ble_only_check = QCheckBox("Force BLE-only Parse")
        self.endurance_ble_only_check.setChecked(True)
        endurance_layout.addWidget(self.endurance_ble_only_check, 1, 4, 1, 2)
        self.endurance_stop_on_fail_check = QCheckBox("Stop on First Failure")
        self.endurance_stop_on_fail_check.setChecked(False)
        endurance_layout.addWidget(self.endurance_stop_on_fail_check, 1, 6, 1, 2)

        self.endurance_start_100_button = QPushButton("Start 100 Cycles")
        self.endurance_start_100_button.clicked.connect(
            lambda: self._start_endurance(100)
        )
        endurance_layout.addWidget(self.endurance_start_100_button, 2, 0, 1, 2)
        self.endurance_start_custom_button = QPushButton("Start Custom")
        self.endurance_start_custom_button.clicked.connect(
            lambda: self._start_endurance()
        )
        endurance_layout.addWidget(self.endurance_start_custom_button, 2, 2, 1, 2)
        self.endurance_stop_button = QPushButton("Stop")
        self.endurance_stop_button.clicked.connect(self._stop_endurance)
        self.endurance_stop_button.setEnabled(False)
        endurance_layout.addWidget(self.endurance_stop_button, 2, 4, 1, 2)
        self.endurance_copy_report_button = QPushButton("Copy Report Path")
        self.endurance_copy_report_button.clicked.connect(self._copy_endurance_report_path)
        self.endurance_copy_report_button.setEnabled(False)
        endurance_layout.addWidget(self.endurance_copy_report_button, 2, 6, 1, 2)

        self.endurance_status_label = QLabel("IDLE")
        endurance_layout.addWidget(self.endurance_status_label, 3, 0, 1, 2)
        self.endurance_progress_label = QLabel("Cycle: 0/0")
        endurance_layout.addWidget(self.endurance_progress_label, 3, 2, 1, 2)
        self.endurance_report_label = QLabel("Report: --")
        self.endurance_report_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        endurance_layout.addWidget(self.endurance_report_label, 3, 4, 1, 4)

        endurance_group.setLayout(endurance_layout)
        layout.addWidget(endurance_group)
        layout.addWidget(self._build_endurance_visual_group())

        collision_row = QHBoxLayout()
        self.pair_collision_labels = []
        for label in self._pair_labels:
            collision = QLabel(f"{label} Collision: --")
            collision.setAlignment(Qt.AlignCenter)
            self._set_label_style(collision, "#444444", "#FFFFFF")
            collision_row.addWidget(collision)
            self.pair_collision_labels.append(collision)
        collision_row.addStretch()
        layout.addLayout(collision_row)

        device_row = QHBoxLayout()
        self.slot_widgets = {}
        for pair_index, (slot_a, slot_b) in enumerate(self._pairs):
            pair_group = QGroupBox(self._pair_labels[pair_index])
            pair_layout = QVBoxLayout()
            self.slot_widgets[slot_a] = self._build_device_group(slot_a)
            self.slot_widgets[slot_b] = self._build_device_group(slot_b)
            pair_layout.addWidget(self.slot_widgets[slot_a]["group"])
            pair_layout.addWidget(self.slot_widgets[slot_b]["group"])
            pair_group.setLayout(pair_layout)
            device_row.addWidget(pair_group)
        layout.addLayout(device_row)

        root.setLayout(layout)
        return root

    def _build_color_tab(self) -> QWidget:
        root = QWidget()
        root.setStyleSheet("background-color: #000000; color: #FFFFFF;")
        layout = QVBoxLayout()
        layout.setSpacing(10)
        layout.setContentsMargins(8, 8, 8, 8)

        top_bar = QHBoxLayout()
        top_bar.setSpacing(8)
        top_bar.addWidget(QLabel("COLOR"))
        self.color_pair_combo = QComboBox()
        self.color_pair_combo.addItems(["Pair 1", "Pair 2"])
        self.color_pair_combo.currentIndexChanged.connect(self._on_color_pair_changed)
        self.color_pair_combo.setFixedWidth(110)
        top_bar.addWidget(self.color_pair_combo)

        self.color_auto_startup_check = QCheckBox("Auto Startup")
        # Keep this OFF by default for auth troubleshooting.
        # Auto writes right after connect can mask real pairing/root-cause issues.
        self.color_auto_startup_check.setChecked(False)
        self.color_auto_startup_check.setStyleSheet("QCheckBox { color: #d0d0d0; }")
        top_bar.addWidget(self.color_auto_startup_check)

        self.color_startup_button = QPushButton("Startup Wave")
        self.color_startup_button.clicked.connect(
            lambda: self._run_async(self._run_startup_wave_for_current_pair())
        )
        self.color_startup_button.setFixedWidth(120)
        top_bar.addWidget(self.color_startup_button)

        self.color_battery_button = QPushButton("Read Battery")
        self.color_battery_button.clicked.connect(
            lambda: self._run_async(self._read_color_pair_battery())
        )
        self.color_battery_button.setFixedWidth(120)
        top_bar.addWidget(self.color_battery_button)
        top_bar.addStretch()
        layout.addLayout(top_bar)

        startup_group = QGroupBox("Startup Wave")
        startup_group.setStyleSheet(
            "QGroupBox { border: 1px solid #666666; margin-top: 8px; padding-top: 8px; }"
            "QGroupBox::title { subcontrol-origin: margin; left: 8px; padding: 0 4px; }"
        )
        startup_layout = QGridLayout()
        startup_layout.addWidget(QLabel("Cycle (ms)"), 0, 0)
        self.color_startup_cycle_spin = QSpinBox()
        self.color_startup_cycle_spin.setRange(200, 10000)
        self.color_startup_cycle_spin.setValue(self._startup_wave_cycle_ms)
        self.color_startup_cycle_spin.valueChanged.connect(
            self._on_startup_wave_cycle_changed
        )
        startup_layout.addWidget(self.color_startup_cycle_spin, 0, 1)

        startup_note = QLabel("Set 1-5 uses the current color slider selection")
        startup_note.setStyleSheet("color:#bdbdbd;")
        startup_layout.addWidget(startup_note, 0, 2, 1, 4)

        startup_layout.addWidget(QLabel("Colors"), 1, 0)
        color_slots_row = QHBoxLayout()
        color_slots_row.setSpacing(6)
        self.color_startup_color_previews: list[QLabel] = []
        for idx in range(5):
            col = QVBoxLayout()
            col.setSpacing(4)
            preview = QLabel(f"S{idx + 1}")
            preview.setAlignment(Qt.AlignCenter)
            preview.setFixedSize(72, 40)
            preview.setStyleSheet(
                "border: 1px solid #ffffff; background-color: #202020; color: #ffffff;"
            )
            btn = QPushButton(f"Set {idx + 1}")
            btn.setFixedWidth(72)
            btn.clicked.connect(
                lambda _, i=idx: self._set_startup_wave_color_slot(
                    i, QColor(self._color_selected)
                )
            )
            col.addWidget(preview)
            col.addWidget(btn)
            color_slots_row.addLayout(col)
            self.color_startup_color_previews.append(preview)
        startup_layout.addLayout(color_slots_row, 1, 1, 1, 5)
        startup_group.setLayout(startup_layout)
        layout.addWidget(startup_group)

        def build_side_panel(label: str, target: str) -> dict:
            panel = QFrame()
            panel.setMinimumWidth(165)
            panel.setMaximumWidth(190)
            panel.setStyleSheet(
                "QFrame { border: 2px solid #ffffff; background-color: #000000; }"
            )
            panel_layout = QVBoxLayout()
            panel_layout.setSpacing(6)
            panel_layout.setContentsMargins(8, 8, 8, 8)
            title = QLabel(label)
            title.setAlignment(Qt.AlignCenter)
            title.setStyleSheet("font-size: 18px; font-weight: bold; letter-spacing: 1px;")
            panel_layout.addWidget(title)

            connect_btn = QPushButton("connect\nNG")
            connect_btn.setFixedHeight(56)
            connect_btn.setStyleSheet(
                "QPushButton { border: 1px solid #ffffff; background-color: #111111; "
                "color: #ff6666; font-weight: bold; }"
            )
            panel_layout.addWidget(connect_btn)

            disconnect_btn = QPushButton("Disconnect")
            disconnect_btn.setFixedHeight(34)
            disconnect_btn.setStyleSheet(
                "QPushButton { border: 1px solid #ffffff; background-color: #111111; "
                "color: #dddddd; font-weight: bold; }"
            )
            panel_layout.addWidget(disconnect_btn)

            batt_bar = QProgressBar()
            batt_bar.setRange(0, 100)
            batt_bar.setTextVisible(False)
            batt_bar.setFixedHeight(18)
            batt_bar.setStyleSheet(
                "QProgressBar { border: 1px solid #ffffff; background-color: #111111; }"
                "QProgressBar::chunk { background-color: #2e7d32; }"
            )
            panel_layout.addWidget(batt_bar)

            battery_label = QLabel("Battery: --.- V")
            battery_label.setAlignment(Qt.AlignCenter)
            battery_label.setStyleSheet(
                "QLabel { border: 1px solid #ffffff; background-color: #303030; color: #ffffff; }"
            )
            panel_layout.addWidget(battery_label)

            top_btn = QPushButton("TOP\nSelect")
            top_btn.setFixedHeight(44)
            top_btn.clicked.connect(
                lambda _, t=target: self._color_select_target_zone(t, "TOP")
            )
            bottom_btn = QPushButton("BOTTOM\nSelect")
            bottom_btn.setFixedHeight(44)
            bottom_btn.clicked.connect(
                lambda _, t=target: self._color_select_target_zone(t, "BOTTOM")
            )
            top_btn.setStyleSheet(
                "QPushButton { border: 1px solid #ffffff; background-color: #111111; color: #ffffff; }"
            )
            bottom_btn.setStyleSheet(
                "QPushButton { border: 1px solid #ffffff; background-color: #111111; color: #ffffff; }"
            )
            panel_layout.addWidget(top_btn)
            panel_layout.addWidget(bottom_btn)
            panel_layout.addStretch()
            panel.setLayout(panel_layout)
            return {
                "frame": panel,
                "connect_btn": connect_btn,
                "disconnect_btn": disconnect_btn,
                "battery_bar": batt_bar,
                "battery_label": battery_label,
                "top_btn": top_btn,
                "bottom_btn": bottom_btn,
            }

        main_row = QHBoxLayout()
        main_row.setSpacing(14)
        self.color_status_widgets = {}
        self.color_status_widgets["stockA"] = build_side_panel("stockA", "A")
        self.color_status_widgets["stockB"] = build_side_panel("stockB", "B")

        center_panel = QFrame()
        center_panel.setMinimumWidth(185)
        center_panel.setMaximumWidth(220)
        center_panel.setStyleSheet(
            "QFrame { border: 2px solid #c6c6c6; background-color: #d0d0d0; }"
        )
        center_layout = QVBoxLayout()
        center_layout.setSpacing(6)
        center_layout.setContentsMargins(10, 8, 10, 8)
        center_title = QLabel("COLOR SELECT")
        center_title.setAlignment(Qt.AlignCenter)
        center_title.setStyleSheet("font-size: 24px; color: #000000; font-weight: bold;")
        center_layout.addWidget(center_title)

        picker_row = QHBoxLayout()
        picker_row.setSpacing(12)

        hue_col = QVBoxLayout()
        self.color_hue_slider = QSlider(Qt.Vertical)
        self.color_hue_slider.setRange(0, 359)
        self.color_hue_slider.setValue(0)
        self.color_hue_slider.setFixedHeight(190)
        self.color_hue_slider.setFixedWidth(30)
        self.color_hue_slider.valueChanged.connect(self._on_color_hue_changed)
        self.color_hue_slider.sliderPressed.connect(
            self._on_color_picker_interaction_started
        )
        self.color_hue_slider.sliderReleased.connect(
            self._on_color_picker_interaction_finished
        )
        self.color_hue_slider.setStyleSheet(
            "QSlider::groove:vertical { width: 16px; border: 1px solid #444444; "
            "background: qlineargradient(x1:0, y1:1, x2:0, y2:0, "
            "stop:0 #ff0000, stop:0.17 #ffff00, stop:0.33 #00ff00, "
            "stop:0.50 #00ffff, stop:0.67 #0000ff, stop:0.83 #ff00ff, stop:1 #ff0000); } "
            "QSlider::handle:vertical { background: #ececec; border: 1px solid #333333; "
            "height: 10px; margin: 0 -4px; }"
        )
        hue_col.addWidget(self.color_hue_slider, 1)
        hue_label = QLabel("H")
        hue_label.setAlignment(Qt.AlignCenter)
        hue_label.setStyleSheet("color: #000000; font-size: 18px; font-weight: bold;")
        hue_col.addWidget(hue_label)
        picker_row.addLayout(hue_col)

        sat_col = QVBoxLayout()
        self.color_saturation_slider = QSlider(Qt.Vertical)
        self.color_saturation_slider.setRange(0, 255)
        self.color_saturation_slider.setValue(255)
        self.color_saturation_slider.setFixedHeight(190)
        self.color_saturation_slider.setFixedWidth(30)
        self.color_saturation_slider.valueChanged.connect(self._on_color_saturation_changed)
        self.color_saturation_slider.sliderPressed.connect(
            self._on_color_picker_interaction_started
        )
        self.color_saturation_slider.sliderReleased.connect(
            self._on_color_picker_interaction_finished
        )
        self.color_saturation_slider.setStyleSheet(
            "QSlider::groove:vertical { width: 16px; border: 1px solid #444444; background: #e6e6e6; } "
            "QSlider::sub-page:vertical { background: #66dd66; } "
            "QSlider::handle:vertical { background: #ececec; border: 1px solid #333333; "
            "height: 10px; margin: 0 -4px; }"
        )
        sat_col.addWidget(self.color_saturation_slider, 1)
        sat_label = QLabel("S")
        sat_label.setAlignment(Qt.AlignCenter)
        sat_label.setStyleSheet("color: #000000; font-size: 18px; font-weight: bold;")
        sat_col.addWidget(sat_label)
        picker_row.addLayout(sat_col)

        bright_col = QVBoxLayout()
        self.color_brightness_slider = QSlider(Qt.Vertical)
        self.color_brightness_slider.setRange(0, 255)
        self.color_brightness_slider.setValue(255)
        self.color_brightness_slider.setFixedHeight(190)
        self.color_brightness_slider.setFixedWidth(30)
        self.color_brightness_slider.valueChanged.connect(self._on_color_brightness_changed)
        self.color_brightness_slider.sliderPressed.connect(
            self._on_color_picker_interaction_started
        )
        self.color_brightness_slider.sliderReleased.connect(
            self._on_color_picker_interaction_finished
        )
        self.color_brightness_slider.setStyleSheet(
            "QSlider::groove:vertical { width: 16px; border: 1px solid #444444; background: #111111; } "
            "QSlider::sub-page:vertical { background: #17c217; } "
            "QSlider::handle:vertical { background: #ececec; border: 1px solid #333333; "
            "height: 10px; margin: 0 -4px; }"
        )
        bright_col.addWidget(self.color_brightness_slider, 1)
        bright_label = QLabel("B")
        bright_label.setAlignment(Qt.AlignCenter)
        bright_label.setStyleSheet("color: #000000; font-size: 18px; font-weight: bold;")
        bright_col.addWidget(bright_label)
        picker_row.addLayout(bright_col)

        center_layout.addLayout(picker_row)

        center_panel.setLayout(center_layout)

        main_row.addWidget(self.color_status_widgets["stockA"]["frame"], 1)
        main_row.addWidget(center_panel, 1)
        main_row.addWidget(self.color_status_widgets["stockB"]["frame"], 1)
        layout.addLayout(main_row)

        def build_figure(_label: str, top_default: str) -> dict:
            frame = QFrame()
            frame.setStyleSheet("background-color: #000000;")
            fig_layout = QVBoxLayout()
            fig_layout.setSpacing(6)
            fig_layout.setContentsMargins(10, 8, 10, 8)
            circle_top = QLabel("")
            circle_top.setFixedSize(74, 74)
            circle_top.setStyleSheet(
                f"background-color: {top_default}; border-radius: 37px; border: 2px solid #ffffff;"
            )
            body = QLabel("")
            body.setFixedSize(66, 160)
            body.setStyleSheet("background-color: #d9d9d9; border: 1px solid #ffffff;")
            circle_bottom = QLabel("")
            circle_bottom.setFixedSize(74, 74)
            circle_bottom.setStyleSheet(
                "background-color: #d9d9d9; border-radius: 37px; border: 2px solid #ffffff;"
            )
            fig_layout.addWidget(circle_top, alignment=Qt.AlignHCenter)
            fig_layout.addWidget(body, alignment=Qt.AlignHCenter)
            fig_layout.addWidget(circle_bottom, alignment=Qt.AlignHCenter)
            frame.setLayout(fig_layout)
            return {
                "frame": frame,
                "top_circle": circle_top,
                "body": body,
                "bottom_circle": circle_bottom,
            }

        bottom_row = QHBoxLayout()
        bottom_row.setSpacing(16)
        self.color_figures = {
            "stockA": build_figure("A", "#e7ff5d"),
            "stockB": build_figure("B", "#ff1f1f"),
        }
        bottom_row.addWidget(self.color_figures["stockA"]["frame"], 1)

        heartbeat_panel = QFrame()
        heartbeat_panel.setStyleSheet(
            "QFrame { border: 2px solid #ffffff; background-color: #000000; }"
        )
        heartbeat_layout = QVBoxLayout()
        heartbeat_layout.setSpacing(6)
        heartbeat_layout.setContentsMargins(8, 8, 8, 8)
        heartbeat_label = QLabel("heart beat")
        heartbeat_label.setAlignment(Qt.AlignCenter)
        heartbeat_label.setStyleSheet("font-size: 22px;")
        heartbeat_layout.addWidget(heartbeat_label)
        speed_row = QHBoxLayout()
        self.color_heartbeat_buttons = {}
        for level, interval in [
            ("LOW", 1.0),
            ("MIDDLE", 0.6),
            ("HIGH", 0.3),
        ]:
            btn = QPushButton(level)
            btn.clicked.connect(
                lambda _, lvl=level, sec=interval: self._color_set_heartbeat_speed(lvl, sec)
            )
            btn.setMinimumHeight(36)
            speed_row.addWidget(btn)
            self.color_heartbeat_buttons[level] = btn
        heartbeat_layout.addLayout(speed_row)

        self.color_heartbeat_color_preview = QLabel("")
        self.color_heartbeat_color_preview.setAlignment(Qt.AlignCenter)
        self.color_heartbeat_color_preview.setMinimumHeight(34)
        heartbeat_layout.addWidget(self.color_heartbeat_color_preview)

        self.color_heartbeat_set_button = QPushButton("SET HEART COLOR")
        self.color_heartbeat_set_button.setMinimumHeight(32)
        self.color_heartbeat_set_button.clicked.connect(
            self._set_color_heartbeat_from_slider
        )
        heartbeat_layout.addWidget(self.color_heartbeat_set_button)

        self.color_heartbeat_stop = QPushButton("STOP")
        self.color_heartbeat_stop.setMinimumHeight(32)
        self.color_heartbeat_stop.clicked.connect(
            lambda: self._run_async(self._color_stop_heartbeat())
        )
        heartbeat_layout.addWidget(self.color_heartbeat_stop)

        self.color_syncro_button = QPushButton("SYNCRO")
        self.color_syncro_button.setMinimumHeight(52)
        self.color_syncro_button.clicked.connect(self._toggle_color_cheat)
        self.color_syncro_button.setStyleSheet(
            "QPushButton { border: 2px solid #ffffff; color: #ffffff; "
            "background-color: qlineargradient(x1:0, y1:0, x2:1, y2:0, "
            "stop:0 #ff3d00, stop:0.5 #ffee58, stop:1 #00e5ff); "
            "font-weight: bold; }"
        )
        heartbeat_layout.addWidget(self.color_syncro_button)
        self.color_syncro_label = QLabel("SYNCRO: OFF")
        self.color_syncro_label.setAlignment(Qt.AlignCenter)
        heartbeat_layout.addWidget(self.color_syncro_label)

        self.color_cheat_button = QPushButton("CHEAT")
        self.color_cheat_button.setMinimumHeight(40)
        self.color_cheat_button.clicked.connect(
            lambda: self._run_async(self._toggle_color_cheat_rainbow())
        )
        heartbeat_layout.addWidget(self.color_cheat_button)
        self.color_cheat_label = QLabel("CHEAT: OFF")
        self.color_cheat_label.setAlignment(Qt.AlignCenter)
        heartbeat_layout.addWidget(self.color_cheat_label)
        heartbeat_panel.setLayout(heartbeat_layout)

        bottom_row.addWidget(heartbeat_panel, 2)
        bottom_row.addWidget(self.color_figures["stockB"]["frame"], 1)
        layout.addLayout(bottom_row)

        root.setLayout(layout)
        self._wire_color_status_buttons()
        self._refresh_startup_wave_cycle_controls()
        self._refresh_startup_wave_color_previews()
        self._refresh_color_tab()
        return root

    def _build_serial_color_tab(self) -> QWidget:
        root = QWidget()
        root.setStyleSheet("background-color: #101010; color: #f0f0f0;")
        layout = QVBoxLayout()
        layout.setSpacing(10)

        conn_group = QGroupBox("Serial Connection")
        conn_layout = QGridLayout()
        conn_layout.addWidget(QLabel("COM"), 0, 0)
        self.serial_color_port_combo = QComboBox()
        self.serial_color_port_combo.addItem(COM_PORT_NONE)
        conn_layout.addWidget(self.serial_color_port_combo, 0, 1)
        self.serial_color_refresh_button = QPushButton("Refresh")
        self.serial_color_refresh_button.clicked.connect(
            self._serial_color_refresh_ports
        )
        conn_layout.addWidget(self.serial_color_refresh_button, 0, 2)
        conn_layout.addWidget(QLabel("Baud"), 0, 3)
        self.serial_color_baud_edit = QLineEdit("115200")
        self.serial_color_baud_edit.setFixedWidth(90)
        conn_layout.addWidget(self.serial_color_baud_edit, 0, 4)
        self.serial_color_connect_button = QPushButton("Connect")
        self.serial_color_connect_button.clicked.connect(self._serial_color_connect)
        conn_layout.addWidget(self.serial_color_connect_button, 0, 5)
        self.serial_color_disconnect_button = QPushButton("Disconnect")
        self.serial_color_disconnect_button.clicked.connect(
            self._serial_color_disconnect
        )
        self.serial_color_disconnect_button.setEnabled(False)
        conn_layout.addWidget(self.serial_color_disconnect_button, 0, 6)
        self.serial_color_status_label = QLabel("NO CONNECTION")
        self.serial_color_status_label.setAlignment(Qt.AlignCenter)
        self._set_label_style(self.serial_color_status_label, "#616161", "#ffffff")
        conn_layout.addWidget(self.serial_color_status_label, 0, 7)
        self.serial_color_output_check = QCheckBox("Enable Output")
        self.serial_color_output_check.setChecked(False)
        self.serial_color_output_check.toggled.connect(
            self._on_serial_color_output_toggled
        )
        conn_layout.addWidget(self.serial_color_output_check, 0, 8)
        conn_group.setLayout(conn_layout)
        layout.addWidget(conn_group)

        color_group = QGroupBox("D3/D4 Same Color (HSB)")
        color_layout = QHBoxLayout()
        color_layout.setSpacing(16)

        sliders_col = QHBoxLayout()
        sliders_col.setSpacing(12)

        def _make_slider(title: str, minimum: int, maximum: int, value: int) -> tuple[QVBoxLayout, QSlider, QLabel]:
            col = QVBoxLayout()
            label = QLabel(title)
            label.setAlignment(Qt.AlignCenter)
            slider = QSlider(Qt.Vertical)
            slider.setRange(minimum, maximum)
            slider.setValue(value)
            slider.setFixedHeight(230)
            slider.setFixedWidth(28)
            value_label = QLabel(str(value))
            value_label.setAlignment(Qt.AlignCenter)
            col.addWidget(label)
            col.addWidget(slider, alignment=Qt.AlignCenter)
            col.addWidget(value_label)
            return col, slider, value_label

        h_col, self.serial_color_h_slider, self.serial_color_h_value = _make_slider("H", 0, 359, 0)
        s_col, self.serial_color_s_slider, self.serial_color_s_value = _make_slider("S", 0, 255, 255)
        b_col, self.serial_color_b_slider, self.serial_color_b_value = _make_slider("B", 0, 255, 255)
        sliders_col.addLayout(h_col)
        sliders_col.addLayout(s_col)
        sliders_col.addLayout(b_col)
        color_layout.addLayout(sliders_col)

        right_col = QVBoxLayout()
        right_col.setSpacing(10)
        self.serial_color_preview = QLabel("")
        self.serial_color_preview.setFixedSize(220, 120)
        self.serial_color_preview.setAlignment(Qt.AlignCenter)
        self.serial_color_preview.setStyleSheet(
            "border: 2px solid #ffffff; border-radius: 8px;"
        )
        right_col.addWidget(self.serial_color_preview, alignment=Qt.AlignLeft)

        self.serial_color_rgb_label = QLabel("RGB: 255, 0, 0")
        right_col.addWidget(self.serial_color_rgb_label)

        self.serial_color_auto_apply_check = QCheckBox("Auto Apply")
        self.serial_color_auto_apply_check.setChecked(False)
        self.serial_color_auto_apply_check.stateChanged.connect(
            self._on_serial_color_auto_apply_changed
        )
        right_col.addWidget(self.serial_color_auto_apply_check)

        brightness_row = QHBoxLayout()
        brightness_row.addWidget(QLabel("Brightness"))
        self.serial_color_brightness_slider = QSlider(Qt.Horizontal)
        self.serial_color_brightness_slider.setRange(0, 255)
        self.serial_color_brightness_slider.setValue(255)
        self.serial_color_brightness_slider.valueChanged.connect(
            self._on_serial_color_brightness_changed
        )
        brightness_row.addWidget(self.serial_color_brightness_slider, 1)
        self.serial_color_brightness_value = QLabel("255")
        self.serial_color_brightness_value.setAlignment(Qt.AlignCenter)
        self.serial_color_brightness_value.setFixedWidth(42)
        brightness_row.addWidget(self.serial_color_brightness_value)
        right_col.addLayout(brightness_row)

        rainbow_row = QHBoxLayout()
        rainbow_row.addWidget(QLabel("Rainbow ms"))
        self.serial_color_interval_edit = QLineEdit("40")
        self.serial_color_interval_edit.setFixedWidth(64)
        rainbow_row.addWidget(self.serial_color_interval_edit)
        self.serial_color_rainbow_button = QPushButton("Start Rainbow")
        self.serial_color_rainbow_button.clicked.connect(self._serial_color_start_rainbow)
        rainbow_row.addWidget(self.serial_color_rainbow_button)
        self.serial_color_stop_rainbow_button = QPushButton("Stop Rainbow")
        self.serial_color_stop_rainbow_button.clicked.connect(self._serial_color_stop_rainbow)
        rainbow_row.addWidget(self.serial_color_stop_rainbow_button)
        right_col.addLayout(rainbow_row)

        self.serial_color_accel_button = QPushButton("Accel Mode: OFF")
        self.serial_color_accel_button.clicked.connect(self._serial_color_toggle_accel)
        right_col.addWidget(self.serial_color_accel_button)

        action_row_1 = QHBoxLayout()
        self.serial_color_led_on_button = QPushButton("LED ON")
        self.serial_color_led_on_button.clicked.connect(
            lambda: self._serial_color_apply_same_color(ensure_on=True)
        )
        action_row_1.addWidget(self.serial_color_led_on_button)
        self.serial_color_apply_button = QPushButton("Apply D3+D4")
        self.serial_color_apply_button.clicked.connect(
            lambda: self._serial_color_apply_same_color(ensure_on=False)
        )
        action_row_1.addWidget(self.serial_color_apply_button)
        right_col.addLayout(action_row_1)

        action_row_2 = QHBoxLayout()
        self.serial_color_led_off_button = QPushButton("LED OFF")
        self.serial_color_led_off_button.clicked.connect(self._serial_color_led_off)
        action_row_2.addWidget(self.serial_color_led_off_button)
        self.serial_color_pick_button = QPushButton("Pick")
        self.serial_color_pick_button.clicked.connect(self._serial_color_pick_dialog)
        action_row_2.addWidget(self.serial_color_pick_button)
        right_col.addLayout(action_row_2)

        right_col.addStretch()
        color_layout.addLayout(right_col, 1)
        color_group.setLayout(color_layout)
        layout.addWidget(color_group)

        log_group = QGroupBox("Serial Command Log")
        log_layout = QVBoxLayout()
        self.serial_color_log_view = QPlainTextEdit()
        self.serial_color_log_view.setReadOnly(True)
        self.serial_color_log_view.setMinimumHeight(150)
        log_layout.addWidget(self.serial_color_log_view)
        log_group.setLayout(log_layout)
        layout.addWidget(log_group)
        layout.addStretch()

        root.setLayout(layout)

        self.serial_color_h_slider.valueChanged.connect(self._on_serial_color_hsv_changed)
        self.serial_color_s_slider.valueChanged.connect(self._on_serial_color_hsv_changed)
        self.serial_color_b_slider.valueChanged.connect(self._on_serial_color_hsv_changed)
        self._serial_color_refresh_ports()
        self._on_serial_color_hsv_changed()
        self._serial_color_set_controls_enabled(False)
        return root

    def _build_pattern_tab(self) -> QWidget:
        root = QWidget()
        root.setStyleSheet("background-color: #0b0b0b; color: #f0f0f0;")
        layout = QVBoxLayout()

        control_group = QGroupBox("LED Pattern Generator")
        grid = QGridLayout()
        grid.addWidget(QLabel("Pair"), 0, 0)
        self.pattern_pair_combo = QComboBox()
        self.pattern_pair_combo.addItems(["Pair 1", "Pair 2"])
        self.pattern_pair_combo.currentIndexChanged.connect(
            lambda idx: setattr(self, "_pattern_pair_index", idx)
        )
        grid.addWidget(self.pattern_pair_combo, 0, 1)

        grid.addWidget(QLabel("Target"), 0, 2)
        self.pattern_target_combo = QComboBox()
        self.pattern_target_combo.addItems(["stockA", "stockB", "A+B"])
        self.pattern_target_combo.currentIndexChanged.connect(
            self._on_pattern_target_changed
        )
        grid.addWidget(self.pattern_target_combo, 0, 3)

        grid.addWidget(QLabel("Zone"), 0, 4)
        self.pattern_zone_combo = QComboBox()
        self.pattern_zone_combo.addItems(["TOP", "BOTTOM", "ALL"])
        self.pattern_zone_combo.currentIndexChanged.connect(
            self._on_pattern_zone_changed
        )
        self.pattern_zone_combo.setCurrentText("ALL")
        grid.addWidget(self.pattern_zone_combo, 0, 5)

        grid.addWidget(QLabel("Pattern"), 1, 0)
        self.pattern_type_combo = QComboBox()
        self.pattern_type_combo.addItems(
            [
                "Solid",
                "Blink",
                "Alternate",
                "Pulse",
                "Breath",
                "Chase",
                "Wave",
                "Strobe",
                "Knight Rider",
                "Rainbow",
            ]
        )
        grid.addWidget(self.pattern_type_combo, 1, 1)

        grid.addWidget(QLabel("Interval (ms)"), 1, 2)
        self.pattern_interval_spin = QSpinBox()
        self.pattern_interval_spin.setRange(50, 5000)
        self.pattern_interval_spin.setValue(300)
        grid.addWidget(self.pattern_interval_spin, 1, 3)

        grid.addWidget(QLabel("Repeat (0=inf)"), 1, 4)
        self.pattern_repeat_spin = QSpinBox()
        self.pattern_repeat_spin.setRange(0, 10000)
        self.pattern_repeat_spin.setValue(0)
        grid.addWidget(self.pattern_repeat_spin, 1, 5)

        grid.addWidget(QLabel("Brightness"), 2, 0)
        self.pattern_brightness_spin = QSpinBox()
        self.pattern_brightness_spin.setRange(1, 255)
        self.pattern_brightness_spin.setValue(200)
        grid.addWidget(self.pattern_brightness_spin, 2, 1)

        self.pattern_color_preview = QLabel("   ")
        self.pattern_color_preview.setFixedWidth(70)
        self.pattern_color_preview.setAlignment(Qt.AlignCenter)
        grid.addWidget(QLabel("Color"), 2, 2)
        grid.addWidget(self.pattern_color_preview, 2, 3)

        color_row = QHBoxLayout()
        for name, color in [
            ("R", QColor(255, 0, 0)),
            ("G", QColor(0, 255, 0)),
            ("B", QColor(0, 0, 255)),
            ("Y", QColor(255, 255, 0)),
            ("W", QColor(255, 255, 255)),
        ]:
            btn = QPushButton(name)
            btn.setFixedWidth(34)
            btn.clicked.connect(lambda _, c=color: self._set_pattern_color(c))
            txt = "#000000" if color.lightness() > 140 else "#ffffff"
            btn.setStyleSheet(
                f"QPushButton {{ border: 1px solid #ffffff; background-color: {color.name()}; color: {txt}; }}"
            )
            color_row.addWidget(btn)
        self.pattern_pick_button = QPushButton("Pick")
        self.pattern_pick_button.clicked.connect(self._pick_pattern_color)
        color_row.addWidget(self.pattern_pick_button)
        grid.addLayout(color_row, 2, 4, 1, 2)

        grid.addWidget(QLabel("Startup Cycle (ms)"), 3, 0)
        self.pattern_startup_cycle_spin = QSpinBox()
        self.pattern_startup_cycle_spin.setRange(200, 10000)
        self.pattern_startup_cycle_spin.setValue(self._startup_wave_cycle_ms)
        self.pattern_startup_cycle_spin.valueChanged.connect(
            self._on_startup_wave_cycle_changed
        )
        grid.addWidget(self.pattern_startup_cycle_spin, 3, 1)

        self.pattern_startup_button = QPushButton("Startup Wave")
        self.pattern_startup_button.clicked.connect(
            lambda: self._run_async(self._run_startup_wave_from_pattern_tab())
        )
        grid.addWidget(self.pattern_startup_button, 3, 2, 1, 2)

        startup_note = QLabel("Uses Pair / 5 Startup Colors / Brightness from this tab")
        startup_note.setStyleSheet("color:#bdbdbd;")
        grid.addWidget(startup_note, 3, 4, 1, 2)

        grid.addWidget(QLabel("Startup Colors"), 4, 0)
        startup_color_row = QHBoxLayout()
        startup_color_row.setSpacing(6)
        self.pattern_startup_color_previews: list[QLabel] = []
        for idx in range(5):
            col = QVBoxLayout()
            col.setSpacing(4)
            preview = QLabel(f"S{idx + 1}")
            preview.setAlignment(Qt.AlignCenter)
            preview.setFixedSize(72, 40)
            preview.setStyleSheet(
                "border: 1px solid #ffffff; background-color: #202020; color: #ffffff;"
            )
            btn = QPushButton(f"Set {idx + 1}")
            btn.setFixedWidth(72)
            btn.clicked.connect(
                lambda _, i=idx: self._set_startup_wave_color_slot(
                    i, QColor(self._pattern_selected)
                )
            )
            col.addWidget(preview)
            col.addWidget(btn)
            startup_color_row.addLayout(col)
            self.pattern_startup_color_previews.append(preview)
        grid.addLayout(startup_color_row, 4, 1, 1, 5)

        action_row = QHBoxLayout()
        self.pattern_apply_once_btn = QPushButton("Apply Once")
        self.pattern_apply_once_btn.clicked.connect(
            lambda: self._run_async(self._pattern_apply_once())
        )
        self.pattern_start_btn = QPushButton("Start Pattern")
        self.pattern_start_btn.clicked.connect(lambda: self._run_async(self._pattern_start()))
        self.pattern_stop_btn = QPushButton("Stop Pattern")
        self.pattern_stop_btn.clicked.connect(lambda: self._run_async(self._pattern_stop()))
        action_row.addWidget(self.pattern_apply_once_btn)
        action_row.addWidget(self.pattern_start_btn)
        action_row.addWidget(self.pattern_stop_btn)
        grid.addLayout(action_row, 5, 0, 1, 6)

        control_group.setLayout(grid)
        layout.addWidget(control_group)

        self.pattern_status_label = QLabel("Pattern: IDLE")
        self._set_label_style(self.pattern_status_label, "#424242", "#ffffff")
        layout.addWidget(self.pattern_status_label)

        help_text = QLabel(
            "Use this tab to generate LED patterns on selected stock.\n"
            "Repeat=0 means continuous run until Stop. Startup colors are stored with Set 1-5."
        )
        help_text.setStyleSheet("color:#bdbdbd;")
        layout.addWidget(help_text)
        layout.addStretch()

        root.setLayout(layout)
        self._set_pattern_color(self._pattern_selected)
        self._refresh_startup_wave_cycle_controls()
        self._refresh_startup_wave_color_previews()
        return root

    def _build_register_tab(self) -> QWidget:
        root = QWidget()
        layout = QVBoxLayout()

        actions = QHBoxLayout()
        self.add_current_button = QPushButton("Add Current A/B")
        self.add_current_button.clicked.connect(self._add_current_pair)
        actions.addWidget(self.add_current_button)

        self.delete_selected_button = QPushButton("Delete Selected")
        self.delete_selected_button.clicked.connect(self._delete_selected)
        actions.addWidget(self.delete_selected_button)

        self.clear_register_button = QPushButton("Clear Memory")
        self.clear_register_button.clicked.connect(self._clear_register)
        actions.addWidget(self.clear_register_button)

        self.export_csv_button = QPushButton("Export CSV")
        self.export_csv_button.clicked.connect(self._export_register_csv)
        actions.addWidget(self.export_csv_button)

        actions.addStretch()
        layout.addLayout(actions)

        self.table = QTableWidget(0, 7)
        self.table.setHorizontalHeaderLabels(
            ["N", "A Device Name", "A Port", "A MAC", "B Device Name", "B Port", "B MAC"]
        )
        self.table.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        layout.addWidget(self.table)

        pager = QHBoxLayout()
        self.prev_page = QPushButton("<")
        self.prev_page.clicked.connect(lambda: self._change_page(-1))
        self.next_page = QPushButton(">")
        self.next_page.clicked.connect(lambda: self._change_page(1))
        self.page_label = QLabel("1 / 1")
        self.page_label.setAlignment(Qt.AlignCenter)
        pager.addStretch()
        pager.addWidget(self.prev_page)
        pager.addWidget(self.page_label)
        pager.addWidget(self.next_page)
        pager.addStretch()
        layout.addLayout(pager)

        root.setLayout(layout)
        return root

    def _build_log_tab(self) -> QWidget:
        root = QWidget()
        layout = QVBoxLayout()
        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        layout.addWidget(self.log_view)
        root.setLayout(layout)
        return root

    # --------------------------- Color Tab ---------------------------
    def _wire_color_status_buttons(self) -> None:
        for label, widgets in self.color_status_widgets.items():
            widgets["connect_btn"].clicked.connect(
                lambda _, lbl=label: self._run_async(
                    self._connect_slot(self._color_slot_for_label(lbl))
                )
            )
            widgets["disconnect_btn"].clicked.connect(
                lambda _, lbl=label: self._run_async(
                    self._disconnect_slot(self._color_slot_for_label(lbl))
                )
            )

    def _color_slot_for_label(self, label: str) -> str:
        pair_slots = self._pairs[self._color_pair_index]
        return pair_slots[0] if label == "stockA" else pair_slots[1]

    def _on_color_pair_changed(self, idx: int) -> None:
        self._color_pair_index = idx
        self._refresh_color_tab()

    def _on_color_target_changed(self, target: str) -> None:
        self._color_edit_target = target

    def _on_color_zone_changed(self, zone: str) -> None:
        self._color_zone = zone

    def _color_select_target_zone(self, target: str, zone: str) -> None:
        self._color_edit_target = target
        self._color_zone = zone
        self._refresh_color_tab()

    def _toggle_color_cheat(self) -> None:
        if self._color_cheat:
            self._disable_color_cheat()
        else:
            self._enable_color_cheat()

    def _enable_color_cheat(self) -> None:
        if self._color_cheat:
            return
        result = QMessageBox.question(
            self,
            "Enable SYNCRO",
            "Sync A+B for all color operations?",
        )
        if result != QMessageBox.Yes:
            return
        self._color_cheat = True
        self._save_color_settings()
        self._refresh_color_tab()

    def _disable_color_cheat(self) -> None:
        if not self._color_cheat:
            return
        self._color_cheat = False
        self._save_color_settings()
        self._refresh_color_tab()

    def _refresh_color_cheat_label(self) -> None:
        if self._color_cheat:
            if hasattr(self, "color_syncro_label"):
                self.color_syncro_label.setText("SYNCRO: ON (A+B)")
                self._set_label_style(self.color_syncro_label, "#1b5e20", "#ffffff")
            if hasattr(self, "color_syncro_button"):
                self.color_syncro_button.setStyleSheet(
                    "QPushButton { border: 2px solid #ffffff; color: #ffffff; "
                    "background-color: #1b5e20; font-weight: bold; }"
                )
        else:
            if hasattr(self, "color_syncro_label"):
                self.color_syncro_label.setText("SYNCRO: OFF")
                self._set_label_style(self.color_syncro_label, "#424242", "#ffffff")
            if hasattr(self, "color_syncro_button"):
                self.color_syncro_button.setStyleSheet(
                    "QPushButton { border: 2px solid #ffffff; color: #ffffff; "
                    "background-color: qlineargradient(x1:0, y1:0, x2:1, y2:0, "
                    "stop:0 #ff3d00, stop:0.5 #ffee58, stop:1 #00e5ff); "
                    "font-weight: bold; }"
                )

    def _color_rainbow_active_for_targets(self) -> bool:
        target_slots = self._color_target_slots()
        if not target_slots:
            return False
        return all(
            self._color_state.get(slot, {}).get("mode") == "rainbow"
            and bool(self._color_state.get(slot, {}).get("output", False))
            for slot in target_slots
        )

    def _refresh_color_rainbow_cheat_label(self) -> None:
        if not hasattr(self, "color_cheat_label"):
            return
        active = self._color_rainbow_active_for_targets()
        target_text = "A+B" if self._color_cheat else self._color_edit_target
        if active:
            self.color_cheat_label.setText(f"CHEAT: ON ({target_text} RAINBOW)")
            self._set_label_style(self.color_cheat_label, "#1565c0", "#ffffff")
            if hasattr(self, "color_cheat_button"):
                self.color_cheat_button.setStyleSheet(
                    "QPushButton { border: 2px solid #ffffff; color: #ffffff; "
                    "background-color: #1565c0; font-weight: bold; }"
                )
        else:
            self.color_cheat_label.setText(f"CHEAT: OFF ({target_text})")
            self._set_label_style(self.color_cheat_label, "#424242", "#ffffff")
            if hasattr(self, "color_cheat_button"):
                self.color_cheat_button.setStyleSheet(
                    "QPushButton { border: 2px solid #ffffff; color: #ffffff; "
                    "background-color: #303030; font-weight: bold; }"
                )

    async def _toggle_color_cheat_rainbow(self) -> None:
        if self._color_rainbow_active_for_targets():
            await self._color_stop_rainbow()
            return
        await self._color_start_rainbow()

    def _color_target_slots(self) -> list[str]:
        slots = list(self._pairs[self._color_pair_index])
        if self._color_cheat:
            return slots
        if self._color_edit_target == "A":
            return [slots[0]]
        return [slots[1]]

    def _color_connected_slots(self) -> tuple[list[str], list[str]]:
        connected: list[str] = []
        disconnected: list[str] = []
        for slot in self._color_target_slots():
            client = self._clients.get(slot)
            if client and client.is_connected:
                connected.append(slot)
            else:
                disconnected.append(slot)
        return connected, disconnected

    def _color_zone_flags(self) -> tuple[bool, bool]:
        if self._color_cheat:
            return True, True
        if self._color_zone == "TOP":
            return True, False
        if self._color_zone == "BOTTOM":
            return False, True
        return True, True

    def _on_color_hue_changed(self, value: int) -> None:
        self._color_hue = value
        self._schedule_color_hsb_apply()

    def _on_color_brightness_changed(self, value: int) -> None:
        self._color_value = value
        self._schedule_color_hsb_apply()

    def _on_color_saturation_changed(self, value: int) -> None:
        self._color_saturation = value
        self._schedule_color_hsb_apply()

    def _on_color_picker_interaction_started(self) -> None:
        self._color_picker_interacting = True

    def _on_color_picker_interaction_finished(self) -> None:
        self._color_picker_interacting = False
        if self._color_picker_is_active():
            return
        if hasattr(self, "_color_apply_timer") and self._color_apply_timer.isActive():
            self._color_apply_timer.stop()
        self._save_color_settings()
        self._flush_color_hsb_apply()

    def _color_picker_is_active(self) -> bool:
        for attr in (
            "color_hue_slider",
            "color_saturation_slider",
            "color_brightness_slider",
        ):
            slider = getattr(self, attr, None)
            if slider is not None and slider.isSliderDown():
                return True
        return False

    def _schedule_color_hsb_apply(self) -> None:
        color = QColor.fromHsv(
            int(self._color_hue), int(self._color_saturation), int(self._color_value)
        )
        self._color_selected = color
        for slot in self._color_target_slots():
            self._color_state[slot]["brightness"] = int(self._color_value)
        self._color_apply_pending = True
        if hasattr(self, "_color_apply_timer"):
            self._color_apply_timer.start()
            return
        self._run_async(self._flush_color_hsb_apply_async())

    def _flush_color_hsb_apply(self) -> None:
        self._run_async(self._flush_color_hsb_apply_async())

    def _current_color_picker_color(self) -> QColor:
        return QColor.fromHsv(
            int(self._color_hue), int(self._color_saturation), int(self._color_value)
        )

    def _set_color_heartbeat_from_slider(self) -> None:
        self._color_heartbeat_color = self._current_color_picker_color()
        self._refresh_color_heartbeat_preview()
        self._save_color_settings()

    async def _flush_color_hsb_apply_async(self) -> None:
        if self._color_apply_inflight:
            self._color_apply_pending = True
            return
        self._color_apply_inflight = True
        try:
            while True:
                self._color_apply_pending = False
                color = QColor.fromHsv(
                    int(self._color_hue),
                    int(self._color_saturation),
                    int(self._color_value),
                )
                self._color_selected = color
                await self._color_commit_brightness()
                await self._color_apply_color(color)
                if not self._color_apply_pending:
                    break
        finally:
            self._color_apply_inflight = False

    def _refresh_color_heartbeat_preview(self) -> None:
        if not hasattr(self, "color_heartbeat_color_preview"):
            return
        color = QColor(self._color_heartbeat_color)
        txt = "#000000" if color.lightness() > 140 else "#ffffff"
        self.color_heartbeat_color_preview.setText(
            f"HB {color.name()}"
        )
        self.color_heartbeat_color_preview.setStyleSheet(
            f"border: 1px solid #ffffff; background-color: {color.name()}; color: {txt};"
        )

    def _update_color_hsv_from_color(self, color: QColor) -> None:
        h, s, v, _ = color.getHsv()
        if h < 0:
            h = 0
        self._color_hue = h
        self._color_saturation = s
        self._color_value = v
        if hasattr(self, "color_hue_slider"):
            self.color_hue_slider.blockSignals(True)
            self.color_hue_slider.setValue(h)
            self.color_hue_slider.blockSignals(False)
        if hasattr(self, "color_saturation_slider"):
            self.color_saturation_slider.blockSignals(True)
            self.color_saturation_slider.setValue(s)
            self.color_saturation_slider.blockSignals(False)
        if hasattr(self, "color_brightness_slider"):
            self.color_brightness_slider.blockSignals(True)
            self.color_brightness_slider.setValue(v)
            self.color_brightness_slider.blockSignals(False)

    async def _color_commit_brightness(self) -> None:
        value = self.color_brightness_slider.value()
        slots, disconnected = self._color_connected_slots()
        for slot in slots:
            await self._write_led_command_live(slot, [CMD_SET_BRIGHTNESS, value])
        if disconnected:
            self.log(
                f"[COLOR] brightness skipped (not connected): {', '.join(disconnected)}"
            )
        self._save_color_settings()
        self._refresh_color_tab(sync_picker=False)

    def _on_color_selected(self, color: QColor) -> None:
        self._color_selected = color
        self._update_color_hsv_from_color(color)
        self._save_color_settings()
        self._run_async(self._color_apply_color(color))

    def _pick_custom_color(self) -> None:
        color = QColorDialog.getColor(self._color_selected, self, "Pick Color")
        if not color.isValid():
            return
        self._color_selected = color
        self._update_color_hsv_from_color(color)
        self._save_color_settings()
        self._run_async(self._color_apply_color(color))

    async def _color_apply_color(self, color: QColor) -> None:
        top_on, bottom_on = self._color_zone_flags()
        slots, disconnected = self._color_connected_slots()
        for slot in slots:
            await self._write_led_command_live(slot, [CMD_SET_OUTPUT_ENABLE, 0x01])
            self._color_state[slot]["output"] = True
            if top_on:
                await self._write_led_command_live(
                    slot, [CMD_SET_FRONT_COLOR, color.red(), color.green(), color.blue()]
                )
                self._color_state[slot]["front"] = color
            if bottom_on:
                await self._write_led_command_live(
                    slot, [CMD_SET_REAR_COLOR, color.red(), color.green(), color.blue()]
                )
                self._color_state[slot]["rear"] = color
            self._color_state[slot]["mode"] = "color"
        if disconnected:
            self.log(
                f"[COLOR] apply skipped (not connected): {', '.join(disconnected)}"
            )
        self._save_color_settings()
        self._refresh_color_tab(sync_picker=False)

    async def _color_set_output(self, enabled: bool) -> None:
        value = 0x01 if enabled else 0x00
        slots, disconnected = self._color_connected_slots()
        for slot in slots:
            await self._write_led_command_live(slot, [CMD_SET_OUTPUT_ENABLE, value])
            self._color_state[slot]["output"] = enabled
        if disconnected:
            self.log(
                f"[COLOR] output skipped (not connected): {', '.join(disconnected)}"
            )
        self._save_color_settings()
        self._refresh_color_tab()

    async def _color_start_rainbow(self) -> None:
        slots, disconnected = self._color_connected_slots()
        for slot in slots:
            self._cancel_color_heartbeat(slot)
        output_results = await asyncio.gather(
            *[
                self._write_led_command_live(slot, [CMD_SET_OUTPUT_ENABLE, 0x01])
                for slot in slots
            ]
        ) if slots else []
        rainbow_results = await asyncio.gather(
            *[
                self._write_led_command_live(slot, [CMD_START_RAINBOW, 40, 0])
                for slot in slots
            ]
        ) if slots else []
        for idx, slot in enumerate(slots):
            if (
                idx < len(output_results)
                and output_results[idx]
                and idx < len(rainbow_results)
                and rainbow_results[idx]
            ):
                self._color_state[slot]["output"] = True
                self._color_state[slot]["mode"] = "rainbow"
        if disconnected:
            self.log(
                f"[COLOR] rainbow skipped (not connected): {', '.join(disconnected)}"
            )
        if self._color_cheat and len(slots) > 1:
            self.log(f"[COLOR] rainbow sync start -> {', '.join(slots)}")
        self._save_color_settings()
        self._refresh_color_tab()

    async def _color_stop_rainbow(self) -> None:
        slots, disconnected = self._color_connected_slots()
        stop_results = await asyncio.gather(
            *[self._write_led_command_live(slot, [CMD_STOP_RAINBOW]) for slot in slots]
        ) if slots else []
        for idx, slot in enumerate(slots):
            if idx < len(stop_results) and stop_results[idx]:
                self._color_state[slot]["mode"] = "off"
        if disconnected:
            self.log(
                f"[COLOR] rainbow stop skipped (not connected): {', '.join(disconnected)}"
            )
        self._save_color_settings()
        self._refresh_color_tab()

    async def _color_start_heartbeat(self) -> None:
        slots, disconnected = self._color_connected_slots()
        heartbeat_color = QColor(self._color_heartbeat_color)
        if slots:
            await asyncio.gather(
                *[self._write_led_command_live(slot, [CMD_STOP_RAINBOW]) for slot in slots]
            )
        for slot in slots:
            self._cancel_color_heartbeat(slot)
            task = asyncio.create_task(
                self._color_heartbeat_loop(slot, heartbeat_color)
            )
            self._color_heartbeat_tasks[slot] = task
            self._color_state[slot]["output"] = True
            self._color_state[slot]["mode"] = "heartbeat"
        if disconnected:
            self.log(
                f"[COLOR] heartbeat skipped (not connected): {', '.join(disconnected)}"
            )
        if slots:
            self.log(
                f"[COLOR] heartbeat color={heartbeat_color.name()} slots={', '.join(slots)}"
            )
        self._save_color_settings()
        self._refresh_color_tab()

    async def _color_stop_heartbeat(self) -> None:
        slots, disconnected = self._color_connected_slots()
        for slot in slots:
            self._cancel_color_heartbeat(slot)
            await self._write_led_command_live(slot, [CMD_SET_FRONT_COLOR, 0, 0, 0])
            await self._write_led_command_live(slot, [CMD_SET_REAR_COLOR, 0, 0, 0])
            self._color_state[slot]["mode"] = "off"
        if disconnected:
            self.log(
                f"[COLOR] heartbeat stop skipped (not connected): {', '.join(disconnected)}"
            )
        self._save_color_settings()
        self._refresh_color_tab()

    def _color_set_heartbeat_speed(self, level: str, interval: float) -> None:
        self._color_heartbeat_level = level
        self._color_heartbeat_interval = interval
        self._run_async(self._color_start_heartbeat())
        self._refresh_color_tab()

    async def _color_heartbeat_loop(self, slot: str, color: QColor) -> None:
        top_on, bottom_on = self._color_zone_flags()
        brightness = self._color_state[slot]["brightness"]
        interval = max(0.2, float(self._color_heartbeat_interval))
        try:
            await self._write_led_command_live(slot, [CMD_SET_OUTPUT_ENABLE, 0x01])
            await self._write_led_command_live(slot, [CMD_SET_BRIGHTNESS, brightness])
            while True:
                client = self._clients.get(slot)
                if not client or not client.is_connected:
                    return
                if top_on:
                    await self._write_led_command_live(
                        slot,
                        [CMD_SET_FRONT_COLOR, color.red(), color.green(), color.blue()],
                    )
                    self._color_state[slot]["front"] = color
                if bottom_on:
                    await self._write_led_command_live(
                        slot,
                        [CMD_SET_REAR_COLOR, color.red(), color.green(), color.blue()],
                    )
                    self._color_state[slot]["rear"] = color
                await asyncio.sleep(interval / 2)
                if top_on:
                    await self._write_led_command_live(
                        slot, [CMD_SET_FRONT_COLOR, 0, 0, 0]
                    )
                if bottom_on:
                    await self._write_led_command_live(
                        slot, [CMD_SET_REAR_COLOR, 0, 0, 0]
                    )
                await asyncio.sleep(interval / 2)
        except asyncio.CancelledError:
            return

    def _cancel_color_heartbeat(self, slot: str) -> None:
        task = self._color_heartbeat_tasks.pop(slot, None)
        if task and not task.done():
            task.cancel()

    async def _color_copy(self, src: str, dst: str) -> None:
        pair = self._pairs[self._color_pair_index]
        src_slot = pair[0] if src == "A" else pair[1]
        dst_slot = pair[0] if dst == "A" else pair[1]
        src_state = self._color_state[src_slot]
        copied = {
            "front": src_state["front"],
            "rear": src_state["rear"],
            "brightness": src_state["brightness"],
            "output": src_state["output"],
            "mode": src_state["mode"],
        }
        self._color_state[dst_slot] = copied
        await self._color_apply_state_to_slot(dst_slot, copied)
        self._save_color_settings()
        self._refresh_color_tab()

    async def _color_apply_state_to_slot(self, slot: str, state: dict) -> None:
        client = self._clients.get(slot)
        if not client or not client.is_connected:
            self.log(f"[COLOR] state sync skipped ({slot} not connected)")
            return
        await self._write_led_command_live(slot, [CMD_STOP_RAINBOW])
        await self._write_led_command_live(
            slot,
            [CMD_SET_BRIGHTNESS, int(state.get("brightness", 200))],
        )
        await self._write_led_command_live(
            slot, [CMD_SET_OUTPUT_ENABLE, 0x01 if state.get("output") else 0x00]
        )
        front = state.get("front", QColor(255, 255, 255))
        rear = state.get("rear", QColor(255, 255, 255))
        await self._write_led_command_live(
            slot, [CMD_SET_FRONT_COLOR, front.red(), front.green(), front.blue()]
        )
        await self._write_led_command_live(
            slot, [CMD_SET_REAR_COLOR, rear.red(), rear.green(), rear.blue()]
        )

    async def _restore_color_state_after_connect(self, slot: str) -> None:
        pair_idx = self._slot_pair_index(slot)
        if pair_idx is not None and self._pair_connected(pair_idx):
            restore_slots = list(self._pairs[pair_idx])
        else:
            restore_slots = [slot]
        for restore_slot in restore_slots:
            client = self._clients.get(restore_slot)
            if not client or not client.is_connected:
                continue
            await self._color_apply_state_to_slot(restore_slot, self._color_state[restore_slot])
        self._save_color_settings()

    def _pair_has_saved_output(self, pair_idx: int) -> bool:
        for slot in self._pairs[pair_idx]:
            state = self._color_state.get(slot, {})
            if bool(state.get("output", False)):
                return True
            if str(state.get("mode", "off")) not in ("off", ""):
                return True
        return False

    async def _silence_slots_output(self, slots: list[str]) -> None:
        if not slots:
            return
        connected_slots = [
            slot
            for slot in slots
            if self._clients.get(slot) and self._clients[slot].is_connected
        ]
        if not connected_slots:
            return
        preserved_states = {
            slot: {
                "front": QColor(self._color_state[slot]["front"]),
                "rear": QColor(self._color_state[slot]["rear"]),
                "brightness": int(self._color_state[slot]["brightness"]),
                "output": bool(self._color_state[slot]["output"]),
                "mode": str(self._color_state[slot]["mode"]),
            }
            for slot in connected_slots
            if slot in self._color_state
        }
        for slot in connected_slots:
            self._cancel_color_heartbeat(slot)
            self._cancel_pattern_task(slot)
        await asyncio.gather(
            *[self._write_led_command_live(slot, [CMD_STOP_RAINBOW]) for slot in connected_slots],
            *[self._write_led_command_live(slot, [CMD_PATTERN_MODE, 0x00]) for slot in connected_slots],
            *[self._write_led_command_live(slot, [CMD_SET_OUTPUT_ENABLE, 0x00]) for slot in connected_slots],
        )
        for slot, state in preserved_states.items():
            self._color_state[slot] = state
        self._refresh_color_tab(sync_picker=False)

    async def _silence_pair_output(self, pair_idx: int) -> None:
        await self._silence_slots_output(list(self._pairs[pair_idx]))

    def _reset_pair_syncro_cheat_state(self, pair_idx: Optional[int]) -> None:
        self._color_cheat = False
        if pair_idx is not None:
            for slot in self._pairs[pair_idx]:
                if slot not in self._color_state:
                    continue
                state = self._color_state[slot]
                state["mode"] = "color" if bool(state.get("output", False)) else "off"
        self._save_color_settings()
        self._refresh_color_tab(sync_picker=False)

    async def _color_swap(self) -> None:
        pair = self._pairs[self._color_pair_index]
        a, b = pair
        state_a = dict(self._color_state[a])
        state_b = dict(self._color_state[b])
        self._color_state[a] = state_b
        self._color_state[b] = state_a
        await self._color_apply_state_to_slot(a, state_b)
        await self._color_apply_state_to_slot(b, state_a)
        self._save_color_settings()
        self._refresh_color_tab()

    def _color_picker_color_for_slot(self, slot: str) -> QColor:
        state = self._color_state[slot]
        front = state.get("front", QColor(255, 255, 255))
        h, s, _v, _ = front.getHsv()
        if h < 0:
            h = 0
        brightness = max(0, min(255, int(state.get("brightness", 255))))
        return QColor.fromHsv(h, s, brightness)

    def _refresh_color_tab(self, *, sync_picker: bool = True) -> None:
        if not hasattr(self, "color_status_widgets"):
            return
        self._refresh_color_cheat_label()
        self._refresh_color_rainbow_cheat_label()
        allow_picker_sync = (
            sync_picker
            and not self._color_picker_interacting
            and not self._color_picker_is_active()
            and not self._color_apply_inflight
            and not self._color_apply_timer.isActive()
        )
        if allow_picker_sync and hasattr(self, "color_brightness_slider"):
            target_slots = self._color_target_slots()
            if target_slots:
                slot = target_slots[0]
                self._color_selected = self._color_picker_color_for_slot(slot)
                self._update_color_hsv_from_color(self._color_selected)
        pair_slots = self._pairs[self._color_pair_index]
        mapping = {"stockA": pair_slots[0], "stockB": pair_slots[1]}
        for label, widgets in self.color_status_widgets.items():
            slot = mapping[label]
            connected = self._clients.get(slot) and self._clients[slot].is_connected
            no_connection = self._is_pair2_no_connection(slot)
            if no_connection:
                widgets["connect_btn"].setText("NO\nCONNECTION")
                widgets["connect_btn"].setStyleSheet(
                    "QPushButton { border: 1px solid #ffffff; background-color: #5f0f0f; "
                    "color: #ffffff; font-weight: bold; }"
                )
                widgets["connect_btn"].setEnabled(False)
                widgets["disconnect_btn"].setEnabled(False)
                widgets["disconnect_btn"].setStyleSheet(
                    "QPushButton { border: 1px solid #ffffff; background-color: #111111; "
                    "color: #777777; font-weight: bold; }"
                )
            elif connected:
                widgets["connect_btn"].setText("connect\nOK")
                widgets["connect_btn"].setStyleSheet(
                    "QPushButton { border: 1px solid #ffffff; background-color: #1b5e20; "
                    "color: #ffffff; font-weight: bold; }"
                )
                widgets["connect_btn"].setEnabled(False)
                widgets["disconnect_btn"].setEnabled(True)
                widgets["disconnect_btn"].setStyleSheet(
                    "QPushButton { border: 1px solid #ffffff; background-color: #5f0f0f; "
                    "color: #ffffff; font-weight: bold; }"
                )
            else:
                widgets["connect_btn"].setText("connect\nNG")
                widgets["connect_btn"].setStyleSheet(
                    "QPushButton { border: 1px solid #ffffff; background-color: #111111; "
                    "color: #ff6666; font-weight: bold; }"
                )
                widgets["connect_btn"].setEnabled(True)
                widgets["disconnect_btn"].setEnabled(False)
                widgets["disconnect_btn"].setStyleSheet(
                    "QPushButton { border: 1px solid #ffffff; background-color: #111111; "
                    "color: #777777; font-weight: bold; }"
                )
            voltage = self._slot_last_voltage.get(slot)
            if voltage is None:
                percent = 0
                chunk = "#555555"
                voltage_text = "Battery: --.- V"
            else:
                percent = self._battery_percent(voltage)
                chunk = self._battery_color(voltage)
                voltage_text = f"Battery: {voltage:.2f} V"
            widgets["battery_bar"].setValue(percent)
            widgets["battery_bar"].setStyleSheet(
                "QProgressBar { border: 1px solid #ffffff; background-color: #111111; }"
                f"QProgressBar::chunk {{ background-color: {chunk}; }}"
            )
            if "battery_label" in widgets:
                widgets["battery_label"].setText(voltage_text)
                widgets["battery_label"].setStyleSheet(
                    "QLabel { border: 1px solid #ffffff; "
                    "background-color: %s; color: #ffffff; }" % chunk
                )

            front = self._color_state[slot]["front"]
            rear = self._color_state[slot]["rear"]
            if hasattr(self, "color_figures") and label in self.color_figures:
                self.color_figures[label]["top_circle"].setStyleSheet(
                    f"background-color: {front.name()}; border-radius: 37px; border: 2px solid #ffffff;"
                )
                self.color_figures[label]["bottom_circle"].setStyleSheet(
                    f"background-color: {rear.name()}; border-radius: 37px; border: 2px solid #ffffff;"
                )

            is_target = self._color_cheat or (
                self._color_edit_target == ("A" if label == "stockA" else "B")
            )
            if self._color_cheat:
                top_active = is_target
                bottom_active = is_target
            else:
                top_active = is_target and self._color_zone in ("TOP", "ALL")
                bottom_active = is_target and self._color_zone in ("BOTTOM", "ALL")
            widgets["top_btn"].setStyleSheet(
                "QPushButton { border: 1px solid #ffffff; background-color: %s; color: #ffffff; }"
                % ("#2e7d32" if top_active else "#111111")
            )
            widgets["bottom_btn"].setStyleSheet(
                "QPushButton { border: 1px solid #ffffff; background-color: %s; color: #ffffff; }"
                % ("#2e7d32" if bottom_active else "#111111")
            )
            widgets["top_btn"].setEnabled(not no_connection)
            widgets["bottom_btn"].setEnabled(not no_connection)

        if hasattr(self, "color_heartbeat_buttons"):
            for level, btn in self.color_heartbeat_buttons.items():
                active = level == self._color_heartbeat_level
                btn.setStyleSheet(
                    "QPushButton { border: 1px solid #ffffff; background-color: %s; color: #ffffff; }"
                    % ("#2e7d32" if active else "#111111")
                )
        self._refresh_color_heartbeat_preview()

    async def _run_startup_wave_for_current_pair(self) -> None:
        pair_slots = list(self._pairs[self._color_pair_index])
        await self._run_startup_wave_slots(
            pair_slots,
            repeat_count=len(self._startup_wave_colors),
            cycle_seconds=max(0.2, self._startup_wave_cycle_ms / 1000.0),
            color_sequence=[QColor(color) for color in self._startup_wave_colors],
            brightness=int(self._color_value),
        )

    async def _read_color_pair_battery(self) -> None:
        pair_slots = list(self._pairs[self._color_pair_index])
        connected = [
            slot for slot in pair_slots if self._clients.get(slot) and self._clients[slot].is_connected
        ]
        disconnected = [slot for slot in pair_slots if slot not in connected]
        if connected:
            results = await asyncio.gather(
                *[self._read_battery(slot) for slot in connected]
            )
            ok_slots = [slot for slot, ok in zip(connected, results) if ok]
            fail_slots = [slot for slot, ok in zip(connected, results) if not ok]
            if ok_slots:
                self.log(f"[COLOR] battery read -> {', '.join(ok_slots)}")
            if fail_slots:
                self.log(f"[COLOR] battery read failed -> {', '.join(fail_slots)}")
        if disconnected:
            self.log(f"[COLOR] battery read skipped (not connected): {', '.join(disconnected)}")
        self._refresh_color_tab(sync_picker=False)

    # --------------------------- Serial D3/D4 Tab ---------------------------
    def _serial_color_refresh_ports(self) -> None:
        if not hasattr(self, "serial_color_port_combo"):
            return
        ports = self._list_ports()
        current = self.serial_color_port_combo.currentText()
        self._fill_port_combo(self.serial_color_port_combo, ports, current)
        if self._serial_color_is_connected() and self._serial_color_port:
            self.serial_color_port_combo.setCurrentText(self._serial_color_port)

    def _set_serial_color_status(self, text: str, bg: str = "#616161") -> None:
        if not hasattr(self, "serial_color_status_label"):
            return
        self.serial_color_status_label.setText(text)
        self._set_label_style(self.serial_color_status_label, bg, "#ffffff")

    def _serial_color_append_log(self, text: str) -> None:
        if not hasattr(self, "serial_color_log_view"):
            return
        self.serial_color_log_view.appendPlainText(text)
        self.serial_color_log_view.ensureCursorVisible()

    def _serial_color_is_connected(self) -> bool:
        if self._serial_color_handle is None:
            return False
        return bool(getattr(self._serial_color_handle, "is_open", False))

    def _serial_color_set_accel_enabled(self, enabled: bool) -> None:
        self._serial_color_accel_enabled = bool(enabled)
        if hasattr(self, "serial_color_accel_button"):
            text = "Accel Mode: ON" if enabled else "Accel Mode: OFF"
            self.serial_color_accel_button.setText(text)

    def _serial_color_set_controls_enabled(self, connected: bool) -> None:
        for attr in [
            "serial_color_output_check",
            "serial_color_h_slider",
            "serial_color_s_slider",
            "serial_color_b_slider",
            "serial_color_brightness_slider",
            "serial_color_interval_edit",
            "serial_color_rainbow_button",
            "serial_color_stop_rainbow_button",
            "serial_color_accel_button",
            "serial_color_led_on_button",
            "serial_color_apply_button",
            "serial_color_led_off_button",
            "serial_color_pick_button",
            "serial_color_auto_apply_check",
        ]:
            widget = getattr(self, attr, None)
            if widget is not None:
                widget.setEnabled(connected)
        if hasattr(self, "serial_color_connect_button"):
            self.serial_color_connect_button.setEnabled(not connected)
        if hasattr(self, "serial_color_disconnect_button"):
            self.serial_color_disconnect_button.setEnabled(connected)
        if not connected:
            self._serial_color_brightness_timer.stop()
            self._serial_color_set_accel_enabled(False)
            if hasattr(self, "serial_color_output_check"):
                self.serial_color_output_check.blockSignals(True)
                self.serial_color_output_check.setChecked(False)
                self.serial_color_output_check.blockSignals(False)
            self._serial_color_output_enabled = False

    def _serial_color_connect(self) -> None:
        if self._serial_color_is_connected():
            self._set_serial_color_status(f"CONNECTED ({self._serial_color_port})", "#2e7d32")
            return
        port = self.serial_color_port_combo.currentText().strip()
        if self._is_unconnected_port(port):
            self._show_error("Serial D3/D4: COM port is not selected")
            return
        try:
            baud = int(self.serial_color_baud_edit.text().strip())
        except ValueError:
            self._show_error("Serial D3/D4: baud must be numeric")
            return
        try:
            import serial
            handle = serial.Serial(port, baud, timeout=1.0, write_timeout=1.0)
        except Exception as exc:
            self._set_serial_color_status("CONNECT NG", "#7f1d1d")
            self._show_error(f"Serial D3/D4 connect failed: {exc}")
            return
        self._serial_color_handle = handle
        self._serial_color_port = port
        self._serial_color_baud = baud
        self._serial_color_set_controls_enabled(True)
        self._set_serial_color_status(f"CONNECTED ({port})", "#2e7d32")
        self.log(f"[SERIAL_COLOR] connected {port} @ {baud}")
        self._serial_color_append_log(f"[CONNECT] {port} @ {baud}")

    def _serial_color_disconnect(self) -> None:
        handle = self._serial_color_handle
        self._serial_color_handle = None
        if handle is not None:
            try:
                handle.close()
            except Exception:
                pass
        self._serial_color_set_controls_enabled(False)
        self._set_serial_color_status("NO CONNECTION", "#616161")
        if self._serial_color_port and hasattr(self, "serial_color_log_view"):
            self._serial_color_append_log("[DISCONNECT]")
        self._serial_color_port = COM_PORT_NONE

    def _serial_color_send_line(self, line: str) -> bool:
        if not self._serial_color_is_connected():
            self._set_serial_color_status("NO CONNECTION", "#616161")
            self.log("[SERIAL_COLOR] send skipped (not connected)")
            return False
        try:
            payload = (line.strip() + "\n").encode("utf-8")
            self._serial_color_handle.write(payload)
            self._serial_color_handle.flush()
        except Exception as exc:
            self.log(f"[SERIAL_COLOR] send failed: {exc}")
            self._serial_color_append_log(f"[ERR] {exc}")
            self._serial_color_disconnect()
            return False
        self._serial_color_append_log(f">> {line}")
        return True

    def _serial_color_current_rgb(self) -> tuple[int, int, int]:
        color = QColor.fromHsv(
            self.serial_color_h_slider.value(),
            self.serial_color_s_slider.value(),
            self.serial_color_b_slider.value(),
        )
        return color.red(), color.green(), color.blue()

    def _on_serial_color_hsv_changed(self) -> None:
        if not hasattr(self, "serial_color_h_value"):
            return
        h = self.serial_color_h_slider.value()
        s = self.serial_color_s_slider.value()
        v = self.serial_color_b_slider.value()
        self.serial_color_h_value.setText(str(h))
        self.serial_color_s_value.setText(str(s))
        self.serial_color_b_value.setText(str(v))
        r, g, b = self._serial_color_current_rgb()
        self.serial_color_preview.setStyleSheet(
            f"border: 2px solid #ffffff; border-radius: 8px; background-color: rgb({r},{g},{b});"
        )
        self.serial_color_rgb_label.setText(f"RGB: {r}, {g}, {b}")
        if self._serial_color_auto_apply and self._serial_color_is_connected():
            self._serial_color_apply_same_color(ensure_on=False)

    def _on_serial_color_auto_apply_changed(self, _state: int) -> None:
        self._serial_color_auto_apply = self.serial_color_auto_apply_check.isChecked()

    def _on_serial_color_output_toggled(self, enabled: bool) -> None:
        self._serial_color_output_enabled = bool(enabled)
        if not self._serial_color_is_connected():
            return
        line = "ON" if enabled else "OFF"
        ok = self._serial_color_send_line(line)
        if ok:
            self.log(f"[SERIAL_COLOR] output {'ON' if enabled else 'OFF'}")

    def _on_serial_color_brightness_changed(self, value: int) -> None:
        self._serial_color_pending_brightness = int(value)
        if hasattr(self, "serial_color_brightness_value"):
            self.serial_color_brightness_value.setText(str(int(value)))
        if not self._serial_color_is_connected():
            return
        self._serial_color_brightness_timer.start()

    def _serial_color_commit_brightness(self) -> None:
        if not self._serial_color_is_connected():
            return
        value = int(self._serial_color_pending_brightness)
        if self._serial_color_send_line(f"BR {value}"):
            self.log(f"[SERIAL_COLOR] brightness={value}")

    def _serial_color_start_rainbow(self) -> None:
        if not self._serial_color_is_connected():
            self._show_error("Serial D3/D4: no serial connection")
            return
        interval = 40
        try:
            interval = max(1, int(self.serial_color_interval_edit.text().strip()))
        except Exception:
            interval = 40
            self.serial_color_interval_edit.setText("40")
        cmds = [f"RAINBOW {interval}", f"RAINBOW START {interval}"]
        ok = False
        for cmd in cmds:
            ok = self._serial_color_send_line(cmd) or ok
        if ok:
            self.log(f"[SERIAL_COLOR] rainbow start interval={interval}")

    def _serial_color_stop_rainbow(self) -> None:
        if not self._serial_color_is_connected():
            self._show_error("Serial D3/D4: no serial connection")
            return
        cmds = ["RAINBOW 0", "RAINBOW STOP"]
        ok = False
        for cmd in cmds:
            ok = self._serial_color_send_line(cmd) or ok
        if ok:
            self.log("[SERIAL_COLOR] rainbow stop")

    def _serial_color_toggle_accel(self) -> None:
        if not self._serial_color_is_connected():
            self._show_error("Serial D3/D4: no serial connection")
            return
        target = not self._serial_color_accel_enabled
        if self._serial_color_send_line(f"ACCEL {1 if target else 0}"):
            self._serial_color_set_accel_enabled(target)
            self.log(f"[SERIAL_COLOR] accel {'ON' if target else 'OFF'}")

    def _serial_color_pick_dialog(self) -> None:
        current = QColor.fromHsv(
            self.serial_color_h_slider.value(),
            self.serial_color_s_slider.value(),
            self.serial_color_b_slider.value(),
        )
        color = QColorDialog.getColor(current, self, "Pick Serial Color (D3/D4)")
        if not color.isValid():
            return
        h, s, v, _ = color.getHsv()
        self.serial_color_h_slider.blockSignals(True)
        self.serial_color_s_slider.blockSignals(True)
        self.serial_color_b_slider.blockSignals(True)
        self.serial_color_h_slider.setValue(max(0, h))
        self.serial_color_s_slider.setValue(max(0, s))
        self.serial_color_b_slider.setValue(max(0, v))
        self.serial_color_h_slider.blockSignals(False)
        self.serial_color_s_slider.blockSignals(False)
        self.serial_color_b_slider.blockSignals(False)
        self._on_serial_color_hsv_changed()

    def _serial_color_apply_same_color(self, ensure_on: bool) -> None:
        if not self._serial_color_is_connected():
            self._show_error("Serial D3/D4: no serial connection")
            return
        r, g, b = self._serial_color_current_rgb()
        br_val = int(self.serial_color_brightness_slider.value())
        lines: list[str] = []
        if ensure_on or self._serial_color_output_enabled:
            lines.append("ON")
        lines.extend(["ACCEL 0", "RAINBOW 0"])
        lines.extend(
            [
                f"BR {br_val}",
                f"COLOR {r} {g} {b}",
                f"FRONT {r} {g} {b}",
                f"REAR {r} {g} {b}",
                f"TOP {r} {g} {b}",
                f"BOTTOM {r} {g} {b}",
            ]
        )
        ok = True
        for line in lines:
            ok = self._serial_color_send_line(line) and ok
        if ok:
            self._serial_color_set_accel_enabled(False)
            self.log(f"[SERIAL_COLOR] apply D3/D4 same color rgb=({r},{g},{b})")

    def _serial_color_led_off(self) -> None:
        if not self._serial_color_is_connected():
            self._show_error("Serial D3/D4: no serial connection")
            return
        lines = [
            "OFF",
            "COLOR 0 0 0",
            "FRONT 0 0 0",
            "REAR 0 0 0",
            "TOP 0 0 0",
            "BOTTOM 0 0 0",
        ]
        ok = True
        for line in lines:
            ok = self._serial_color_send_line(line) and ok
        if ok:
            if hasattr(self, "serial_color_output_check"):
                self.serial_color_output_check.blockSignals(True)
                self.serial_color_output_check.setChecked(False)
                self.serial_color_output_check.blockSignals(False)
            self._serial_color_output_enabled = False
            self._serial_color_set_accel_enabled(False)
            self.log("[SERIAL_COLOR] LED OFF")

    # --------------------------- Pattern Tab ---------------------------
    def _on_pattern_target_changed(self, _index: int) -> None:
        text = self.pattern_target_combo.currentText()
        if text == "stockA":
            self._pattern_target = "A"
        elif text == "stockB":
            self._pattern_target = "B"
        else:
            self._pattern_target = "BOTH"

    def _on_pattern_zone_changed(self, _index: int) -> None:
        self._pattern_zone = self.pattern_zone_combo.currentText()

    def _set_pattern_color(self, color: QColor) -> None:
        self._pattern_selected = color
        if hasattr(self, "pattern_color_preview"):
            self.pattern_color_preview.setText(color.name())
            self.pattern_color_preview.setStyleSheet(
                f"background-color: {color.name()}; color: #000000; border: 1px solid #ffffff;"
            )
        self._save_color_settings()

    def _on_startup_wave_cycle_changed(self, value: int) -> None:
        self._startup_wave_cycle_ms = int(value)
        self._refresh_startup_wave_cycle_controls()
        self._save_color_settings()

    def _refresh_startup_wave_cycle_controls(self) -> None:
        for attr in ("pattern_startup_cycle_spin", "color_startup_cycle_spin"):
            spin = getattr(self, attr, None)
            if spin is None:
                continue
            if spin.value() == self._startup_wave_cycle_ms:
                continue
            spin.blockSignals(True)
            spin.setValue(self._startup_wave_cycle_ms)
            spin.blockSignals(False)

    def _set_startup_wave_color_slot(self, index: int, color: QColor) -> None:
        if index < 0 or index >= len(self._startup_wave_colors):
            return
        self._startup_wave_colors[index] = QColor(color)
        self._refresh_startup_wave_color_previews()
        self._save_color_settings()

    def _refresh_startup_wave_color_previews(self) -> None:
        for attr in ("pattern_startup_color_previews", "color_startup_color_previews"):
            previews = getattr(self, attr, None)
            if previews is None:
                continue
            for idx, preview in enumerate(previews):
                if idx >= len(self._startup_wave_colors):
                    continue
                color = self._startup_wave_colors[idx]
                txt = "#000000" if color.lightness() > 140 else "#ffffff"
                preview.setText(f"S{idx + 1}\n{color.name()}")
                preview.setStyleSheet(
                    f"border: 1px solid #ffffff; background-color: {color.name()}; color: {txt};"
                )

    def _pick_pattern_color(self) -> None:
        color = QColorDialog.getColor(self._pattern_selected, self, "Pick Pattern Color")
        if color.isValid():
            self._set_pattern_color(color)

    def _pattern_target_slots(self) -> list[str]:
        pair_slots = list(self._pairs[self._pattern_pair_index])
        if self._pattern_target == "A":
            return [pair_slots[0]]
        if self._pattern_target == "B":
            return [pair_slots[1]]
        return pair_slots

    def _pattern_connected_slots(self) -> tuple[list[str], list[str]]:
        targets = self._pattern_target_slots()
        connected: list[str] = []
        disconnected: list[str] = []
        for slot in targets:
            client = self._clients.get(slot)
            if client and client.is_connected:
                connected.append(slot)
            else:
                disconnected.append(slot)
        return connected, disconnected

    def _pattern_zone_flags(self) -> tuple[bool, bool]:
        if self._pattern_zone == "TOP":
            return True, False
        if self._pattern_zone == "BOTTOM":
            return False, True
        return True, True

    async def _run_startup_wave_from_pattern_tab(self) -> None:
        pair_slots = list(self._pairs[self._pattern_pair_index])
        cycle_seconds = max(0.2, self._startup_wave_cycle_ms / 1000.0)
        brightness = self.pattern_brightness_spin.value()
        color_sequence = [QColor(color) for color in self._startup_wave_colors]
        self._set_label_style(self.pattern_status_label, "#263238", "#ffffff")
        self.pattern_status_label.setText(
            f"Pattern: STARTUP WAVE 5 colors cycle={int(cycle_seconds * 1000)}ms"
        )
        ok = await self._run_startup_wave_slots(
            pair_slots,
            repeat_count=len(color_sequence),
            cycle_seconds=cycle_seconds,
            color_sequence=color_sequence,
            brightness=brightness,
        )
        if ok:
            self._set_label_style(self.pattern_status_label, "#1b5e20", "#ffffff")
            self.pattern_status_label.setText(
                f"Pattern: startup wave done ({len(color_sequence)} colors)"
            )
            self.log(
                f"[PATTERN] startup wave pair={self._pattern_pair_index + 1} "
                f"colors={','.join(color.name() for color in color_sequence)} "
                f"cycle_ms={int(cycle_seconds * 1000)} brightness={brightness}"
            )
        else:
            self._set_label_style(self.pattern_status_label, "#7f1d1d", "#ffffff")
            self.pattern_status_label.setText("Pattern: startup wave failed")
            self.log("[PATTERN] startup wave failed (no connected targets or write failure)")

    async def _pattern_apply_once(self) -> None:
        slots, disconnected = self._pattern_connected_slots()
        if not slots:
            self._set_label_style(self.pattern_status_label, "#7f1d1d", "#ffffff")
            self.pattern_status_label.setText("Pattern: no connected target")
            self.log(
                "[PATTERN] apply once skipped (no connected targets)"
            )
            return
        pattern = self.pattern_type_combo.currentText()
        interval_s = max(0.05, self.pattern_interval_spin.value() / 1000.0)
        brightness = self.pattern_brightness_spin.value()
        top_on, bottom_on = self._pattern_zone_flags()
        color = self._pattern_selected
        for slot in slots:
            self._cancel_pattern_task(slot)
            self._cancel_color_heartbeat(slot)
            if pattern != "Rainbow":
                await self._write_led_command_live(slot, [CMD_STOP_RAINBOW])
            await self._pattern_run_once(
                slot,
                pattern,
                color,
                top_on,
                bottom_on,
                interval_s,
                brightness,
            )
        self._set_label_style(self.pattern_status_label, "#263238", "#ffffff")
        self.pattern_status_label.setText(
            f"Pattern: once ({pattern}) on {', '.join(slots)}"
        )
        msg = f"[PATTERN] apply once {pattern} -> {','.join(slots)}"
        if disconnected:
            msg += f" (skip disconnected: {','.join(disconnected)})"
        self.log(msg)

    async def _pattern_start(self) -> None:
        slots, disconnected = self._pattern_connected_slots()
        if not slots:
            self._set_label_style(self.pattern_status_label, "#7f1d1d", "#ffffff")
            self.pattern_status_label.setText("Pattern: no connected target")
            self.log("[PATTERN] start skipped (no connected targets)")
            return
        pattern = self.pattern_type_combo.currentText()
        interval_s = max(0.05, self.pattern_interval_spin.value() / 1000.0)
        repeat = self.pattern_repeat_spin.value()
        brightness = self.pattern_brightness_spin.value()
        top_on, bottom_on = self._pattern_zone_flags()
        color = self._pattern_selected

        for slot in slots:
            self._cancel_pattern_task(slot)
            self._cancel_color_heartbeat(slot)
            task = asyncio.create_task(
                self._pattern_run_loop(
                    slot,
                    pattern,
                    color,
                    top_on,
                    bottom_on,
                    interval_s,
                    brightness,
                    repeat,
                )
            )
            self._pattern_tasks[slot] = task
            task.add_done_callback(lambda _t, s=slot: self._pattern_tasks.pop(s, None))

        self._set_label_style(self.pattern_status_label, "#1b5e20", "#ffffff")
        self.pattern_status_label.setText(
            f"Pattern: RUNNING ({pattern}) on {', '.join(slots)}"
        )
        msg = (
            f"[PATTERN] start type={pattern} slots={','.join(slots)} "
            f"interval={interval_s:.2f}s repeat={repeat}"
        )
        if disconnected:
            msg += f" (skip disconnected: {','.join(disconnected)})"
        self.log(msg)

    async def _pattern_stop(self) -> None:
        slots = self._pattern_target_slots()
        if not slots:
            return
        stopped = []
        skipped = []
        for slot in slots:
            self._cancel_pattern_task(slot)
            ok1 = await self._write_led_command_live(slot, [CMD_STOP_RAINBOW])
            ok2 = await self._write_led_command_live(slot, [CMD_SET_FRONT_COLOR, 0, 0, 0])
            ok3 = await self._write_led_command_live(slot, [CMD_SET_REAR_COLOR, 0, 0, 0])
            if ok1 and ok2 and ok3:
                stopped.append(slot)
            else:
                skipped.append(slot)
        self._set_label_style(self.pattern_status_label, "#424242", "#ffffff")
        self.pattern_status_label.setText("Pattern: STOPPED")
        msg = f"[PATTERN] stop slots={','.join(stopped) if stopped else 'none'}"
        if skipped:
            msg += f" (failed/skipped: {','.join(skipped)})"
        self.log(msg)

    def _cancel_pattern_task(self, slot: str) -> None:
        task = self._pattern_tasks.pop(slot, None)
        if task and not task.done():
            task.cancel()

    async def _pattern_run_loop(
        self,
        slot: str,
        pattern: str,
        color: QColor,
        top_on: bool,
        bottom_on: bool,
        interval_s: float,
        brightness: int,
        repeat: int,
    ) -> None:
        try:
            await self._write_led_command_live(slot, [CMD_SET_OUTPUT_ENABLE, 0x01])
            await self._write_led_command_live(slot, [CMD_SET_BRIGHTNESS, brightness])
            if pattern == "Rainbow":
                await self._write_led_command_live(
                    slot, [CMD_START_RAINBOW, max(5, min(255, int(interval_s * 100)))]
                )
                if repeat == 0:
                    while True:
                        await asyncio.sleep(interval_s)
                else:
                    for _ in range(repeat):
                        await asyncio.sleep(interval_s)
                await self._write_led_command_live(slot, [CMD_STOP_RAINBOW])
                return
            else:
                await self._write_led_command_live(slot, [CMD_STOP_RAINBOW])

            cycle = 0
            while repeat == 0 or cycle < repeat:
                client = self._clients.get(slot)
                if not client or not client.is_connected:
                    return
                await self._pattern_run_once(
                    slot,
                    pattern,
                    color,
                    top_on,
                    bottom_on,
                    interval_s,
                    brightness,
                )
                cycle += 1
        except asyncio.CancelledError:
            return

    async def _pattern_run_once(
        self,
        slot: str,
        pattern: str,
        color: QColor,
        top_on: bool,
        bottom_on: bool,
        interval_s: float,
        brightness: int,
    ) -> None:
        await self._write_led_command_live(slot, [CMD_SET_OUTPUT_ENABLE, 0x01])
        await self._write_led_command_live(slot, [CMD_SET_BRIGHTNESS, brightness])
        r, g, b = color.red(), color.green(), color.blue()
        scale = lambda v, f: max(0, min(255, int(v * f)))

        async def set_top(rr: int, gg: int, bb: int) -> None:
            if top_on:
                await self._write_led_command_live(slot, [CMD_SET_FRONT_COLOR, rr, gg, bb])

        async def set_bottom(rr: int, gg: int, bb: int) -> None:
            if bottom_on:
                await self._write_led_command_live(slot, [CMD_SET_REAR_COLOR, rr, gg, bb])

        if pattern == "Solid":
            await set_top(r, g, b)
            await set_bottom(r, g, b)
            await asyncio.sleep(interval_s)
            return

        if pattern == "Blink":
            await set_top(r, g, b)
            await set_bottom(r, g, b)
            await asyncio.sleep(interval_s / 2)
            await set_top(0, 0, 0)
            await set_bottom(0, 0, 0)
            await asyncio.sleep(interval_s / 2)
            return

        if pattern == "Pulse":
            for factor in (0.25, 0.55, 0.85, 1.0, 0.85, 0.55):
                await set_top(scale(r, factor), scale(g, factor), scale(b, factor))
                await set_bottom(scale(r, factor), scale(g, factor), scale(b, factor))
                await asyncio.sleep(interval_s / 6)
            return

        if pattern == "Breath":
            factors = (0.08, 0.15, 0.25, 0.4, 0.55, 0.72, 0.9, 1.0, 0.9, 0.72, 0.55, 0.35)
            for factor in factors:
                await set_top(scale(r, factor), scale(g, factor), scale(b, factor))
                await set_bottom(scale(r, factor), scale(g, factor), scale(b, factor))
                await asyncio.sleep(interval_s / len(factors))
            return

        if pattern == "Strobe":
            flash_gap = max(0.02, interval_s / 8)
            for _ in range(3):
                await set_top(r, g, b)
                await set_bottom(r, g, b)
                await asyncio.sleep(flash_gap)
                await set_top(0, 0, 0)
                await set_bottom(0, 0, 0)
                await asyncio.sleep(flash_gap)
            await asyncio.sleep(max(0.02, interval_s - flash_gap * 6))
            return

        if pattern == "Chase":
            if top_on and bottom_on:
                await set_top(r, g, b)
                await set_bottom(0, 0, 0)
                await asyncio.sleep(interval_s / 3)
                await set_top(0, 0, 0)
                await set_bottom(r, g, b)
                await asyncio.sleep(interval_s / 3)
                await set_top(0, 0, 0)
                await set_bottom(0, 0, 0)
                await asyncio.sleep(interval_s / 3)
                return
            # single-zone fallback
            await set_top(r, g, b)
            await set_bottom(r, g, b)
            await asyncio.sleep(interval_s / 2)
            await set_top(0, 0, 0)
            await set_bottom(0, 0, 0)
            await asyncio.sleep(interval_s / 2)
            return

        if pattern == "Wave":
            if top_on and bottom_on:
                await set_top(r, g, b)
                await set_bottom(0, 0, 0)
                await asyncio.sleep(interval_s / 4)
                await set_top(r, g, b)
                await set_bottom(r, g, b)
                await asyncio.sleep(interval_s / 4)
                await set_top(0, 0, 0)
                await set_bottom(r, g, b)
                await asyncio.sleep(interval_s / 4)
                await set_top(0, 0, 0)
                await set_bottom(0, 0, 0)
                await asyncio.sleep(interval_s / 4)
                return
            await set_top(r, g, b)
            await set_bottom(r, g, b)
            await asyncio.sleep(interval_s / 2)
            await set_top(0, 0, 0)
            await set_bottom(0, 0, 0)
            await asyncio.sleep(interval_s / 2)
            return

        if pattern == "Knight Rider":
            if top_on and bottom_on:
                # 2-zone "scanner": TOP -> CENTER -> BOTTOM -> CENTER
                await set_top(r, g, b)
                await set_bottom(0, 0, 0)
                await asyncio.sleep(interval_s / 4)

                await set_top(scale(r, 0.35), scale(g, 0.35), scale(b, 0.35))
                await set_bottom(scale(r, 0.35), scale(g, 0.35), scale(b, 0.35))
                await asyncio.sleep(interval_s / 4)

                await set_top(0, 0, 0)
                await set_bottom(r, g, b)
                await asyncio.sleep(interval_s / 4)

                await set_top(scale(r, 0.35), scale(g, 0.35), scale(b, 0.35))
                await set_bottom(scale(r, 0.35), scale(g, 0.35), scale(b, 0.35))
                await asyncio.sleep(interval_s / 4)
                return
            # single-zone fallback
            await set_top(r, g, b)
            await set_bottom(r, g, b)
            await asyncio.sleep(interval_s / 2)
            await set_top(0, 0, 0)
            await set_bottom(0, 0, 0)
            await asyncio.sleep(interval_s / 2)
            return

        # Alternate (default)
        if top_on and bottom_on:
            await set_top(r, g, b)
            await set_bottom(0, 0, 0)
            await asyncio.sleep(interval_s / 2)
            await set_top(0, 0, 0)
            await set_bottom(r, g, b)
            await asyncio.sleep(interval_s / 2)
            return

        # If only one zone selected, fallback to blink behavior
        await set_top(r, g, b)
        await set_bottom(r, g, b)
        await asyncio.sleep(interval_s / 2)
        await set_top(0, 0, 0)
        await set_bottom(0, 0, 0)
        await asyncio.sleep(interval_s / 2)


    def _build_endurance_visual_group(self) -> QWidget:
        group = QGroupBox("Durability Visual Dashboard")
        layout = QVBoxLayout()
        pages = QTabWidget()

        diagram_page = QWidget()
        diagram_layout = QVBoxLayout()

        status_row = QHBoxLayout()
        self.endurance_side_status_labels: dict[str, dict[str, QLabel]] = {}
        for side in ("A", "B"):
            status_group = QGroupBox(f"Status {side}")
            status_layout = QVBoxLayout()
            onoff_label = QLabel("ON/OFF: UNKNOWN")
            volt_label = QLabel("Battery: --.- V")
            for label in (onoff_label, volt_label):
                label.setAlignment(Qt.AlignCenter)
                label.setMinimumHeight(30)
                self._set_label_style(label, "#424242", "#FFFFFF")
                status_layout.addWidget(label)
            status_group.setLayout(status_layout)
            status_row.addWidget(status_group)
            self.endurance_side_status_labels[side] = {
                "onoff": onoff_label,
                "volt": volt_label,
            }
        diagram_layout.addLayout(status_row)

        flow_grid = QGridLayout()
        self.endurance_diagram_labels: dict[str, dict[str, QLabel]] = {}
        self.endurance_stock_on_labels: dict[str, QLabel] = {}
        self.endurance_stock_off_labels: dict[str, QLabel] = {}
        for col, side in enumerate(("A", "B")):
            side_group = QGroupBox(f"{side} Side Line")
            side_layout = QVBoxLayout()
            acdc_label = QLabel("AC / DC")
            arrow1 = QLabel("↓")
            dpm_label = QLabel("DPM + Regulator")
            arrow2 = QLabel("↓")
            mcu_label = QLabel("MCU: DISCONNECT")
            arrow3 = QLabel("↓")
            stock_title = QLabel(f"Stock {side}")
            stock_state = QLabel("LED: UNKNOWN")
            on_label = QLabel("ON")
            or_label = QLabel("or")
            off_label = QLabel("OFF")
            for label in (
                acdc_label,
                arrow1,
                dpm_label,
                arrow2,
                mcu_label,
                arrow3,
                stock_title,
                stock_state,
                on_label,
                or_label,
                off_label,
            ):
                label.setAlignment(Qt.AlignCenter)
            for label in (acdc_label, dpm_label, mcu_label, stock_title, stock_state):
                label.setMinimumHeight(32)
            for label in (on_label, off_label):
                label.setMinimumHeight(30)
                label.setMinimumWidth(90)
            for arrow in (arrow1, arrow2, arrow3):
                arrow.setMinimumHeight(20)
                arrow.setStyleSheet("font-size: 18px; color: #90a4ae;")
            self._set_label_style(acdc_label, "#37474f", "#FFFFFF")
            self._set_label_style(dpm_label, "#6a1b9a", "#FFFFFF")
            self._set_label_style(mcu_label, "#455a64", "#FFFFFF")
            self._set_label_style(stock_title, "#263238", "#FFFFFF")
            self._set_label_style(stock_state, "#424242", "#FFFFFF")
            self._set_label_style(on_label, "#b71c1c", "#FFFFFF")
            self._set_label_style(off_label, "#0d47a1", "#FFFFFF")
            or_label.setStyleSheet("color: #b0bec5;")
            side_layout.addWidget(acdc_label)
            side_layout.addWidget(arrow1)
            side_layout.addWidget(dpm_label)
            side_layout.addWidget(arrow2)
            side_layout.addWidget(mcu_label)
            side_layout.addWidget(arrow3)
            side_layout.addWidget(stock_title)
            side_layout.addWidget(stock_state)
            side_layout.addWidget(on_label)
            side_layout.addWidget(or_label)
            side_layout.addWidget(off_label)
            side_group.setLayout(side_layout)
            flow_grid.addWidget(side_group, 0, col * 2)
            self.endurance_diagram_labels[side] = {
                "dpm": dpm_label,
                "mcu": mcu_label,
                "stock": stock_state,
            }
            self.endurance_stock_on_labels[side] = on_label
            self.endurance_stock_off_labels[side] = off_label

        center_group = QGroupBox("PC / Android")
        center_layout = QVBoxLayout()
        self.endurance_pc_status_label = QLabel("PC: IDLE")
        self.endurance_android_summary_label = QLabel("Android: UNKNOWN")
        self.endurance_link_status_label = QLabel("Status: OK / NG")
        self.endurance_stock_center_a = QLabel("Stock A: --")
        self.endurance_stock_center_b = QLabel("Stock B: --")
        for label in (
            self.endurance_pc_status_label,
            self.endurance_android_summary_label,
            self.endurance_link_status_label,
            self.endurance_stock_center_a,
            self.endurance_stock_center_b,
        ):
            label.setAlignment(Qt.AlignCenter)
            label.setMinimumHeight(30)
            self._set_label_style(label, "#1e88e5", "#FFFFFF")
            center_layout.addWidget(label)
        center_group.setLayout(center_layout)
        flow_grid.addWidget(center_group, 0, 1)
        flow_grid.setColumnStretch(0, 3)
        flow_grid.setColumnStretch(1, 2)
        flow_grid.setColumnStretch(2, 3)
        diagram_layout.addLayout(flow_grid)

        dpm_group = QGroupBox("DPM Scenario (Pseudo Battery Marker)")
        dpm_layout = QGridLayout()
        dpm_layout.addWidget(QLabel("A target (V)"), 0, 0)
        self.dpm_a_voltage_edit = QLineEdit("4.00")
        self.dpm_a_voltage_edit.setFixedWidth(80)
        dpm_layout.addWidget(self.dpm_a_voltage_edit, 0, 1)
        dpm_layout.addWidget(QLabel("A PWM (%)"), 0, 2)
        self.dpm_a_pwm_edit = QLineEdit("50")
        self.dpm_a_pwm_edit.setFixedWidth(80)
        dpm_layout.addWidget(self.dpm_a_pwm_edit, 0, 3)
        dpm_layout.addWidget(QLabel("B target (V)"), 0, 4)
        self.dpm_b_voltage_edit = QLineEdit("4.00")
        self.dpm_b_voltage_edit.setFixedWidth(80)
        dpm_layout.addWidget(self.dpm_b_voltage_edit, 0, 5)
        dpm_layout.addWidget(QLabel("B PWM (%)"), 0, 6)
        self.dpm_b_pwm_edit = QLineEdit("50")
        self.dpm_b_pwm_edit.setFixedWidth(80)
        dpm_layout.addWidget(self.dpm_b_pwm_edit, 0, 7)
        self.dpm_apply_button = QPushButton("Apply + Log Marker")
        self.dpm_apply_button.clicked.connect(self._apply_dpm_profile)
        dpm_layout.addWidget(self.dpm_apply_button, 0, 8)
        self.dpm_status_label = QLabel("DPM marker: not set")
        dpm_layout.addWidget(self.dpm_status_label, 1, 0, 1, 9)
        dpm_group.setLayout(dpm_layout)
        diagram_layout.addWidget(dpm_group)

        display_group = QGroupBox("Display Content (Test Summary)")
        display_layout = QVBoxLayout()
        self.endurance_display_view = QPlainTextEdit()
        self.endurance_display_view.setReadOnly(True)
        self.endurance_display_view.setMaximumBlockCount(200)
        self.endurance_display_view.setMinimumHeight(140)
        display_layout.addWidget(self.endurance_display_view)
        display_group.setLayout(display_layout)
        diagram_layout.addWidget(display_group)

        diagram_page.setLayout(diagram_layout)

        details_page = QWidget()
        details_layout = QVBoxLayout()

        card_grid = QGridLayout()
        self.endurance_visual_slots: dict[str, dict[str, QLabel]] = {}
        for index, slot in enumerate(self._slots):
            side = "A" if slot.startswith("A") else "B"
            slot_group = QGroupBox(f"{slot} / Stock {side}")
            slot_layout = QVBoxLayout()
            name_label = QLabel("Name: --")
            conn_label = QLabel("BLE: DISCONNECT")
            android_label = QLabel("Android: UNKNOWN")
            output_label = QLabel("LED: UNKNOWN")
            battery_label = QLabel("Battery: --.- V")
            dpm_label = QLabel("DPM: -- V / -- PWM")
            for label in (
                conn_label,
                android_label,
                output_label,
                battery_label,
                dpm_label,
            ):
                label.setAlignment(Qt.AlignCenter)
                self._set_label_style(label, "#424242", "#FFFFFF")
                slot_layout.addWidget(label)
            slot_layout.insertWidget(0, name_label)
            slot_group.setLayout(slot_layout)
            self.endurance_visual_slots[slot] = {
                "name": name_label,
                "conn": conn_label,
                "android": android_label,
                "output": output_label,
                "battery": battery_label,
                "dpm": dpm_label,
            }
            card_grid.addWidget(slot_group, index // 2, index % 2)
        details_layout.addLayout(card_grid)

        summary_row = QGridLayout()
        self.endurance_visual_cycle_label = QLabel("Cycles: 0/0")
        summary_row.addWidget(self.endurance_visual_cycle_label, 0, 0)
        self.endurance_visual_pass_label = QLabel("PASS: 0")
        self._set_label_style(self.endurance_visual_pass_label, "#2e7d32", "#FFFFFF")
        summary_row.addWidget(self.endurance_visual_pass_label, 0, 1)
        self.endurance_visual_fail_label = QLabel("FAIL: 0")
        self._set_label_style(self.endurance_visual_fail_label, "#d32f2f", "#FFFFFF")
        summary_row.addWidget(self.endurance_visual_fail_label, 0, 2)
        self.endurance_visual_last_label = QLabel("Last: --")
        summary_row.addWidget(self.endurance_visual_last_label, 0, 3)
        self.endurance_visual_progress = QProgressBar()
        self.endurance_visual_progress.setRange(0, 100)
        self.endurance_visual_progress.setValue(0)
        summary_row.addWidget(self.endurance_visual_progress, 1, 0, 1, 4)
        details_layout.addLayout(summary_row)

        self.endurance_failure_table = QTableWidget(0, 2)
        self.endurance_failure_table.setHorizontalHeaderLabels(["Failure Class", "Count"])
        self.endurance_failure_table.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self.endurance_failure_table.setFixedHeight(140)
        details_layout.addWidget(self.endurance_failure_table)

        details_page.setLayout(details_layout)

        pages.addTab(diagram_page, "Diagram")
        pages.addTab(details_page, "Details")
        layout.addWidget(pages)

        group.setLayout(layout)
        return group

    def _build_environment_tab(self) -> QWidget:
        root = QWidget()
        layout = QVBoxLayout()

        control_group = QGroupBox("RSSI Monitor")
        control_layout = QGridLayout()
        control_layout.addWidget(QLabel("Scan Interval (s)"), 0, 0)
        self.rssi_interval_edit = QLineEdit("2.0")
        self.rssi_interval_edit.setFixedWidth(80)
        control_layout.addWidget(self.rssi_interval_edit, 0, 1)
        control_layout.addWidget(QLabel("Scan Timeout (s)"), 0, 2)
        self.rssi_timeout_edit = QLineEdit("2.0")
        self.rssi_timeout_edit.setFixedWidth(80)
        control_layout.addWidget(self.rssi_timeout_edit, 0, 3)
        self.rssi_start_button = QPushButton("Start")
        self.rssi_start_button.clicked.connect(
            lambda: self._run_async(self._start_rssi_monitor())
        )
        control_layout.addWidget(self.rssi_start_button, 0, 4)
        self.rssi_stop_button = QPushButton("Stop")
        self.rssi_stop_button.clicked.connect(self._stop_rssi_monitor)
        self.rssi_stop_button.setEnabled(False)
        control_layout.addWidget(self.rssi_stop_button, 0, 5)
        self.rssi_clear_button = QPushButton("Clear")
        self.rssi_clear_button.clicked.connect(self._clear_rssi_data)
        control_layout.addWidget(self.rssi_clear_button, 0, 6)
        self.rssi_export_button = QPushButton("Export CSV")
        self.rssi_export_button.clicked.connect(self._export_rssi_csv)
        control_layout.addWidget(self.rssi_export_button, 0, 7)
        self.rssi_status = QLabel("IDLE")
        control_layout.addWidget(self.rssi_status, 0, 8)
        control_layout.setColumnStretch(9, 1)
        control_group.setLayout(control_layout)
        layout.addWidget(control_group)

        status_group = QGroupBox("RSSI Status")
        status_layout = QGridLayout()
        for index, slot in enumerate(self._slots):
            label = QLabel(f"{slot}: -- dBm")
            label.setAlignment(Qt.AlignCenter)
            self._set_label_style(label, "#424242", "#ffffff")
            status_layout.addWidget(label, index // 2, index % 2)
            self._rssi_status_labels[slot] = label
        status_group.setLayout(status_layout)
        layout.addWidget(status_group)

        self.rssi_chart = QChart()
        self.rssi_chart.setTitle("RSSI vs Time")
        self.rssi_series = {}
        colors = {
            "A1": "#1e88e5",
            "B1": "#43a047",
            "A2": "#f9a825",
            "B2": "#8e24aa",
        }
        for slot in self._slots:
            series = QLineSeries()
            series.setName(slot)
            pen = QPen(QColor(colors.get(slot, "#ffffff")))
            pen.setWidth(2)
            series.setPen(pen)
            self.rssi_chart.addSeries(series)
            self.rssi_series[slot] = series

        self.rssi_axis_x = QValueAxis()
        self.rssi_axis_x.setTitleText("Time (s)")
        self.rssi_axis_x.setRange(0, 60)
        self.rssi_axis_y = QValueAxis()
        self.rssi_axis_y.setTitleText("RSSI (dBm)")
        self.rssi_axis_y.setRange(-100, -20)
        self.rssi_chart.addAxis(self.rssi_axis_x, Qt.AlignBottom)
        self.rssi_chart.addAxis(self.rssi_axis_y, Qt.AlignLeft)
        for series in self.rssi_series.values():
            series.attachAxis(self.rssi_axis_x)
            series.attachAxis(self.rssi_axis_y)

        chart_view = QChartView(self.rssi_chart)
        chart_view.setRenderHint(QPainter.Antialiasing)
        layout.addWidget(chart_view)

        root.setLayout(layout)
        return root

    def _build_sequence_tab(self) -> QWidget:
        root = QWidget()
        layout = QVBoxLayout()
        sub_tabs = QTabWidget()

        expected_group = QGroupBox("Expected BLE Sequence (from diagram)")
        expected_layout = QVBoxLayout()
        self.sequence_expected_table = QTableWidget(0, 3)
        self.sequence_expected_table.setHorizontalHeaderLabels(
            ["Phase", "Step", "Notes"]
        )
        self.sequence_expected_table.setSizePolicy(
            QSizePolicy.Expanding, QSizePolicy.Expanding
        )
        self.sequence_expected_table.setSelectionBehavior(QTableWidget.SelectRows)
        expected_layout.addWidget(self.sequence_expected_table)
        expected_actions = QHBoxLayout()
        self.sequence_expected_reload_button = QPushButton("Sync Endurance Steps")
        self.sequence_expected_reload_button.clicked.connect(
            self._populate_expected_sequence
        )
        expected_actions.addWidget(self.sequence_expected_reload_button)
        expected_actions.addStretch()
        expected_layout.addLayout(expected_actions)
        expected_group.setLayout(expected_layout)
        timing_group = QGroupBox("Timing Estimate")
        timing_layout = QGridLayout()
        self.adv_interval_edit = QLineEdit("100")
        self.adv_timeout_edit = QLineEdit("60")
        self.scan_interval_edit = QLineEdit("100")
        self.scan_window_edit = QLineEdit("50")
        self.connect_timeout_edit = QLineEdit(str(config.CONNECT_TIMEOUT))
        self.gatt_timeout_edit = QLineEdit("5")
        timing_layout.addWidget(QLabel("Adv Interval (ms)"), 0, 0)
        timing_layout.addWidget(self.adv_interval_edit, 0, 1)
        timing_layout.addWidget(QLabel("Adv Timeout (s)"), 0, 2)
        timing_layout.addWidget(self.adv_timeout_edit, 0, 3)
        timing_layout.addWidget(QLabel("Scan Interval (ms)"), 1, 0)
        timing_layout.addWidget(self.scan_interval_edit, 1, 1)
        timing_layout.addWidget(QLabel("Scan Window (ms)"), 1, 2)
        timing_layout.addWidget(self.scan_window_edit, 1, 3)
        timing_layout.addWidget(QLabel("Connect Timeout (s)"), 2, 0)
        timing_layout.addWidget(self.connect_timeout_edit, 2, 1)
        timing_layout.addWidget(QLabel("GATT Timeout (s)"), 2, 2)
        timing_layout.addWidget(self.gatt_timeout_edit, 2, 3)
        self.timing_calc_button = QPushButton("Estimate")
        self.timing_calc_button.clicked.connect(self._estimate_timing)
        timing_layout.addWidget(self.timing_calc_button, 3, 0)
        self.timing_output = QPlainTextEdit()
        self.timing_output.setReadOnly(True)
        timing_layout.addWidget(self.timing_output, 3, 1, 1, 3)
        timing_group.setLayout(timing_layout)
        expected_page = QWidget()
        expected_layout_page = QVBoxLayout()
        expected_layout_page.addWidget(expected_group)
        expected_page.setLayout(expected_layout_page)

        timing_page = QWidget()
        timing_layout_page = QVBoxLayout()
        timing_layout_page.addWidget(timing_group)
        timing_page.setLayout(timing_layout_page)

        monitor_group = QGroupBox("External Monitor (Android / MCU)")
        monitor_layout = QVBoxLayout()

        android_row = QGridLayout()
        android_row.addWidget(QLabel("adb"), 0, 0)
        self.adb_path_edit = QLineEdit(self._adb_path_guess or "adb")
        android_row.addWidget(self.adb_path_edit, 0, 1)
        android_row.addWidget(QLabel("Filter"), 0, 2)
        self.logcat_filter_edit = QLineEdit("")
        android_row.addWidget(self.logcat_filter_edit, 0, 3)
        self.logcat_start_button = QPushButton("Start Logcat")
        self.logcat_start_button.clicked.connect(self._start_logcat)
        android_row.addWidget(self.logcat_start_button, 0, 4)
        self.logcat_stop_button = QPushButton("Stop")
        self.logcat_stop_button.clicked.connect(self._stop_logcat)
        self.logcat_stop_button.setEnabled(False)
        android_row.addWidget(self.logcat_stop_button, 0, 5)
        self.android_add_sequence_check = QCheckBox("Add to Sequence")
        self.android_add_sequence_check.setChecked(True)
        android_row.addWidget(self.android_add_sequence_check, 0, 6)
        self.android_ble_only_check = QCheckBox("BLE only")
        self.android_ble_only_check.setChecked(True)
        android_row.addWidget(self.android_ble_only_check, 0, 7)
        self.logcat_status = QLabel("IDLE")
        android_row.addWidget(self.logcat_status, 0, 8)
        monitor_layout.addLayout(android_row)

        serial_row = QGridLayout()
        serial_row.addWidget(QLabel("Serial Port"), 0, 0)
        self.serial_port_combo = QComboBox()
        self.serial_port_combo.addItem(COM_PORT_NONE)
        serial_row.addWidget(self.serial_port_combo, 0, 1)
        self.serial_refresh_button = QPushButton("Refresh")
        self.serial_refresh_button.clicked.connect(self._refresh_monitor_ports)
        serial_row.addWidget(self.serial_refresh_button, 0, 2)
        serial_row.addWidget(QLabel("Baud"), 0, 3)
        self.serial_baud_edit = QLineEdit("115200")
        self.serial_baud_edit.setFixedWidth(80)
        serial_row.addWidget(self.serial_baud_edit, 0, 4)
        self.serial_start_button = QPushButton("Start Serial")
        self.serial_start_button.clicked.connect(self._start_serial)
        serial_row.addWidget(self.serial_start_button, 0, 5)
        self.serial_stop_button = QPushButton("Stop")
        self.serial_stop_button.clicked.connect(self._stop_serial)
        self.serial_stop_button.setEnabled(False)
        serial_row.addWidget(self.serial_stop_button, 0, 6)
        self.mcu_add_sequence_check = QCheckBox("Add to Sequence")
        self.mcu_add_sequence_check.setChecked(True)
        serial_row.addWidget(self.mcu_add_sequence_check, 0, 7)
        self.serial_status = QLabel("IDLE")
        serial_row.addWidget(self.serial_status, 0, 8)
        monitor_layout.addLayout(serial_row)

        self.log_tabs = QTabWidget()
        self.ble_log_view = QPlainTextEdit()
        self.ble_log_view.setReadOnly(True)
        self.other_log_view = QPlainTextEdit()
        self.other_log_view.setReadOnly(True)
        self.mcu_log_view = QPlainTextEdit()
        self.mcu_log_view.setReadOnly(True)
        self.log_tabs.addTab(self.ble_log_view, "BLE Log")
        self.log_tabs.addTab(self.other_log_view, "Other Log")
        self.log_tabs.addTab(self.mcu_log_view, "MCU Log")
        self.log_tabs.setMinimumHeight(140)
        monitor_layout.addWidget(self.log_tabs)

        monitor_group.setLayout(monitor_layout)
        monitor_group.setMinimumHeight(280)
        android_status_group = QGroupBox("Android Connection Summary (auto)")
        android_status_layout = QVBoxLayout()
        status_grid = QGridLayout()
        for index, slot in enumerate(self._slots):
            label = QLabel(f"{slot}: UNKNOWN")
            label.setAlignment(Qt.AlignCenter)
            label.setMinimumHeight(30)
            label.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
            self._set_label_style(label, "#616161", "#ffffff")
            status_grid.addWidget(label, index // 2, index % 2)
            self._android_conn_labels[slot] = label
        android_status_layout.addLayout(status_grid)

        status_row = QHBoxLayout()
        self.android_status_reset_button = QPushButton("Reset Status")
        self.android_status_reset_button.clicked.connect(
            self._reset_android_conn_status
        )
        status_row.addWidget(self.android_status_reset_button)
        status_row.addStretch()
        android_status_layout.addLayout(status_row)

        csv_row = QHBoxLayout()
        csv_row.addWidget(QLabel("CSV"))
        self.android_csv_path_edit = QLineEdit(self._latest_sequence_csv())
        self.android_csv_path_edit.setPlaceholderText(
            "C:\\...\\sequence_events_*.csv"
        )
        csv_row.addWidget(self.android_csv_path_edit)
        self.android_csv_copy_button = QPushButton("Copy Path")
        self.android_csv_copy_button.clicked.connect(
            lambda: self._copy_text_to_clipboard(
                self.android_csv_path_edit.text().strip().strip("\""),
                "Analyze CSV",
            )
        )
        csv_row.addWidget(self.android_csv_copy_button)
        self.android_csv_analyze_button = QPushButton("Analyze CSV")
        self.android_csv_analyze_button.clicked.connect(self._analyze_android_csv)
        csv_row.addWidget(self.android_csv_analyze_button)
        android_status_layout.addLayout(csv_row)

        android_status_group.setLayout(android_status_layout)
        android_status_group.setMinimumHeight(170)

        timing_chart_group = QGroupBox("Sequence Time Chart (CSV analysis)")
        timing_chart_layout = QVBoxLayout()

        timing_chart_row = QHBoxLayout()
        timing_chart_row.addWidget(QLabel("CSV"))
        self.sequence_timing_csv_edit = QLineEdit(self._latest_sequence_csv())
        self.sequence_timing_csv_edit.setPlaceholderText(
            "C:\\...\\sequence_events_*.csv"
        )
        timing_chart_row.addWidget(self.sequence_timing_csv_edit)
        self.sequence_timing_copy_button = QPushButton("Copy Path")
        self.sequence_timing_copy_button.clicked.connect(
            lambda: self._copy_text_to_clipboard(
                self.sequence_timing_csv_edit.text().strip().strip("\""),
                "Timing CSV",
            )
        )
        timing_chart_row.addWidget(self.sequence_timing_copy_button)
        self.sequence_timing_csv_button = QPushButton("Analyze CSV")
        self.sequence_timing_csv_button.clicked.connect(
            self._analyze_sequence_timing_csv
        )
        timing_chart_row.addWidget(self.sequence_timing_csv_button)
        self.sequence_timing_current_button = QPushButton("Analyze Current")
        self.sequence_timing_current_button.clicked.connect(
            self._analyze_sequence_timing_current
        )
        timing_chart_row.addWidget(self.sequence_timing_current_button)
        timing_chart_row.addStretch()
        timing_chart_layout.addLayout(timing_chart_row)

        self.sequence_timing_chart = QChart()
        self.sequence_timing_chart.setTitle("Sequence Timing")
        self.sequence_timing_series = {}
        phase_colors = {
            "scan": "#1e88e5",
            "connect": "#43a047",
            "gatt": "#f9a825",
        }
        for phase, color in phase_colors.items():
            series = QLineSeries()
            series.setName(phase.upper())
            pen = QPen(QColor(color))
            pen.setWidth(6)
            series.setPen(pen)
            self.sequence_timing_chart.addSeries(series)
            self.sequence_timing_series[phase] = series

        self.sequence_timing_thresholds = {}
        for name in ("detect", "total"):
            series = QLineSeries()
            pen = QPen(QColor("#9e9e9e"))
            pen.setWidth(2)
            pen.setStyle(Qt.DashLine)
            series.setPen(pen)
            series.setName(f"{name.upper()} LIMIT")
            self.sequence_timing_chart.addSeries(series)
            self.sequence_timing_thresholds[name] = series

        self.sequence_timing_axis_x = QValueAxis()
        self.sequence_timing_axis_x.setTitleText("Time (s)")
        self.sequence_timing_axis_x.setRange(0, 5)
        self.sequence_timing_axis_y = QCategoryAxis()
        self.sequence_timing_axis_y.append("GATT", 1)
        self.sequence_timing_axis_y.append("CONNECT", 2)
        self.sequence_timing_axis_y.append("SCAN", 3)
        self.sequence_timing_axis_y.setRange(0.5, 3.5)
        self.sequence_timing_chart.addAxis(self.sequence_timing_axis_x, Qt.AlignBottom)
        self.sequence_timing_chart.addAxis(self.sequence_timing_axis_y, Qt.AlignLeft)
        for series in (
            list(self.sequence_timing_series.values())
            + list(self.sequence_timing_thresholds.values())
        ):
            series.attachAxis(self.sequence_timing_axis_x)
            series.attachAxis(self.sequence_timing_axis_y)

        timing_chart_view = QChartView(self.sequence_timing_chart)
        timing_chart_view.setRenderHint(QPainter.Antialiasing)
        timing_chart_view.setMinimumHeight(250)
        timing_chart_layout.addWidget(timing_chart_view)

        summary_grid = QGridLayout()
        summary_grid.addWidget(QLabel("Phase"), 0, 0)
        summary_grid.addWidget(QLabel("Actual (ms)"), 0, 1)
        summary_grid.addWidget(QLabel("Limit (ms)"), 0, 2)
        summary_grid.addWidget(QLabel("Result"), 0, 3)
        self.sequence_timing_labels = {}
        phases = [("scan", "Scan"), ("connect", "Connect"), ("gatt", "GATT"), ("total", "Total")]
        for row, (key, label) in enumerate(phases, start=1):
            summary_grid.addWidget(QLabel(label), row, 0)
            actual_label = QLabel("--")
            limit_label = QLabel("--")
            result_label = QLabel("N/A")
            result_label.setAlignment(Qt.AlignCenter)
            result_label.setMinimumHeight(30)
            self._set_label_style(result_label, "#616161", "#ffffff")
            summary_grid.addWidget(actual_label, row, 1)
            summary_grid.addWidget(limit_label, row, 2)
            summary_grid.addWidget(result_label, row, 3)
            self.sequence_timing_labels[key] = {
                "actual": actual_label,
                "limit": limit_label,
                "result": result_label,
            }
        timing_chart_layout.addLayout(summary_grid)

        timing_chart_group.setLayout(timing_chart_layout)
        timing_chart_group.setMinimumHeight(390)

        event_group = QGroupBox("Sequence Event Log")
        event_layout = QVBoxLayout()
        event_actions = QHBoxLayout()
        self.sequence_clear_button = QPushButton("Clear Events")
        self.sequence_clear_button.clicked.connect(self._clear_sequence_events)
        event_actions.addWidget(self.sequence_clear_button)
        self.sequence_export_button = QPushButton("Export CSV")
        self.sequence_export_button.clicked.connect(self._export_sequence_csv)
        event_actions.addWidget(self.sequence_export_button)
        self.sequence_export_mermaid_button = QPushButton("Export Mermaid")
        self.sequence_export_mermaid_button.clicked.connect(
            self._export_sequence_mermaid
        )
        event_actions.addWidget(self.sequence_export_mermaid_button)
        event_actions.addStretch()
        event_layout.addLayout(event_actions)

        self.sequence_table = QTableWidget(0, 4)
        self.sequence_table.setHorizontalHeaderLabels(
            ["Time (s)", "Delta (ms)", "Slot", "Event"]
        )
        self.sequence_table.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.sequence_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.sequence_table.horizontalHeader().setStretchLastSection(True)
        self.sequence_table.setMinimumHeight(180)
        event_layout.addWidget(self.sequence_table)
        event_group.setLayout(event_layout)
        event_group.setMinimumHeight(260)

        monitor_page = QWidget()
        monitor_layout = QVBoxLayout()
        monitor_layout.addWidget(monitor_group)
        monitor_layout.addWidget(android_status_group)
        monitor_layout.addWidget(timing_chart_group)
        monitor_layout.addWidget(event_group)
        monitor_page.setLayout(monitor_layout)

        sub_tabs.addTab(expected_page, "Expected")
        sub_tabs.addTab(timing_page, "Timing")
        sub_tabs.addTab(monitor_page, "Monitor")
        layout.addWidget(sub_tabs)

        root.setLayout(layout)
        self._populate_expected_sequence()
        self._refresh_monitor_ports()
        return root

    def _build_device_group(self, slot: str) -> dict:
        group = QGroupBox(f"Device {slot}")
        layout = QVBoxLayout()
        layout.setSpacing(6)

        self_name = QComboBox()
        self_name.setMinimumWidth(240)
        self_name.currentIndexChanged.connect(self._update_collision_status)
        layout.addWidget(self_name)

        button_row = QHBoxLayout()
        connect_button = QPushButton("Connect")
        disconnect_button = QPushButton("Disconnect")
        disconnect_button.setEnabled(False)
        connect_button.clicked.connect(
            lambda: self._run_async(self._connect_slot(slot))
        )
        disconnect_button.clicked.connect(
            lambda: self._run_async(self._disconnect_slot(slot))
        )
        button_row.addWidget(connect_button)
        button_row.addWidget(disconnect_button)
        layout.addLayout(button_row)

        status_label = QLabel("Status: disconnected")
        layout.addWidget(status_label)

        state_row = QHBoxLayout()
        state_labels = {}
        for state in ["ADV", "CONNECT", "GATT", "DISCONNECT"]:
            label_widget = QLabel(state)
            label_widget.setAlignment(Qt.AlignCenter)
            label_widget.setFixedHeight(22)
            label_widget.setMinimumWidth(70)
            self._set_label_style(label_widget, "#333333", "#aaaaaa")
            state_labels[state] = label_widget
            state_row.addWidget(label_widget)
        layout.addLayout(state_row)

        battery_label = QLabel("Battery: --.- V")
        layout.addWidget(battery_label)

        port_row = QHBoxLayout()
        port_label = QLabel("Port")
        port_combo = QComboBox()
        port_combo.addItem(COM_PORT_NONE)
        refresh_port = QPushButton("Refresh Ports")
        refresh_port.clicked.connect(self._refresh_ports)
        port_row.addWidget(port_label)
        port_row.addWidget(port_combo)
        port_row.addWidget(refresh_port)
        layout.addLayout(port_row)

        group.setLayout(layout)
        return {
            "group": group,
            "combo": self_name,
            "connect_button": connect_button,
            "disconnect_button": disconnect_button,
            "status_label": status_label,
            "state_labels": state_labels,
            "battery_label": battery_label,
            "port_combo": port_combo,
        }

    # --------------------------- Sequence ---------------------------
    def _populate_expected_sequence(self) -> None:
        steps = [
            ("Advertising", "Start Advertising", "BLE stack init, start ADV"),
            ("Advertising", "Set Scan Response + Device Name", "Include device name"),
            ("Advertising", "Broadcast Service UUIDs", "Primary service UUID"),
            ("Advertising", "Wait for BLE Connect Event", "ADV running"),
            ("Connect", "Central Initiates Connection", "Phone/app connects"),
            ("Connect", "MCU A-side Connected", "A1/B1 connected"),
            ("Connect", "MCU B-side Connected", "A2/B2 connected"),
            ("Startup", "LED Wave 1s x 5 colors", "After B-side connect, all sides wave"),
            ("Startup", "LED ON steady", "After wave, keep lit"),
            ("Connect", "onConnect Callback", "Connection event callback"),
            ("Connect", "Create / Activate ConnInfo", "Connection context"),
            ("Connect", "Update Connection Params (optional)", "Interval/latency"),
            ("Security", "Pairing Requested?", "If security enabled"),
            ("Security", "Auth Complete Callback", "Pairing finished"),
            ("Security", "Bond Stored (if enabled)", "Bond saved"),
            ("GATT", "GATT Server Active", "Services available"),
            ("GATT", "Service UUID Exposed", "Service ready"),
            ("GATT", "Characteristic UUID Exposed", "Characteristics ready"),
            ("GATT", "Client Discovers Service", "Service discovery"),
            ("GATT", "Client Discovers Characteristics", "Char discovery"),
            ("GATT", "Client Writes Command", "WRITE/WRITE_NR"),
            ("GATT", "ACK/Status Notify", "App protocol ACK/Retry"),
            ("GATT", "onWrite -> handle_command()", "Handle command"),
            ("GATT", "Client Reads Voltage (READ)", "Battery read"),
            ("GATT", "onRead -> build_voltage_payload()", "Build payload"),
            ("GATT", "Client Subscribes to Notify", "Enable notify"),
            ("GATT", "Notify Voltage/Status", "Notify updates"),
            ("Reliability", "App Protocol: ACK/Retry/Seq/CRC/Version", "App-layer reliability"),
            ("Reliability", "ACK Timeout -> Retry (backoff)", "Resend on timeout"),
            ("Reliability", "Auto Reconnect on Link Loss", "OS may drop BLE"),
            ("Reliability", "Resubscribe CCCD on Reconnect", "Re-enable notify"),
            ("Reliability", "Resync App State", "Re-send current mode"),
            ("Reliability", "Resync Status (ok/failed)", "Shown in UI"),
            ("OS Strategy", "Android: CDM + (optional) FGS", "Stabilize auto connect"),
            ("OS Strategy", "iOS: Background + State Restoration", "Stabilize auto connect"),
            ("Disconnect", "BLE Disconnect Event", "Link lost"),
            ("Disconnect", "handle_output_enable(false)", "Output off"),
            ("Disconnect", "LED OFF + Clear State", "Reset state"),
            ("Disconnect", "Restart Advertising", "Back to ADV"),
            ("Error", "Error/Timeout -> Reset & Restart ADV", "Timeout handling"),
            ("Endurance", "Start new sequence_events CSV", "Isolate from old logs"),
            ("Endurance", "Validate register baseline", "N/pair + register entries"),
            ("Endurance", "Record REGISTER_BASELINE_OK / REGISTER_PAIR", "Baseline trace"),
            ("Endurance", "CYCLE_START i/N", "Cycle marker"),
            ("Endurance", "Optional DPM_MARKER", "Pseudo battery profile"),
            ("Endurance", "Scan -> Connect -> GATT/Battery -> Disconnect", "One cycle flow"),
            ("Endurance", "CYCLE_END + classify", "PASS/FAIL + failure class"),
            ("Endurance", "Stop on fail (optional)", "Break on first fail"),
            ("Endurance", "Export endurance_report + summary", "Auto output CSV"),
        ]
        self.sequence_expected_table.setRowCount(0)
        for row, (phase, step, note) in enumerate(steps):
            self.sequence_expected_table.insertRow(row)
            for col, value in enumerate([phase, step, note]):
                item = QTableWidgetItem(value)
                item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.sequence_expected_table.setItem(row, col, item)
        self.sequence_expected_table.resizeColumnsToContents()

    def _default_sequence_svg_path(self) -> str:
        preferred = [
            self._log_dir / "endurance_sequence_current.svg",
            self._log_dir / "sequence_tab_overview.svg",
            self._log_dir / "sequence_diagram_latest.svg",
        ]
        for path in preferred:
            if path.exists():
                return str(path)
        candidates = sorted(
            self._log_dir.glob("*.svg"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        return str(candidates[0]) if candidates else ""

    def _browse_sequence_svg(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "Open SVG",
            str(self._log_dir),
            "SVG Files (*.svg);;All Files (*.*)",
        )
        if not path:
            return
        self.sequence_svg_path_edit.setText(path)
        self._load_sequence_svg()

    def _load_sequence_svg(self, silent: bool = False) -> None:
        if not hasattr(self, "sequence_svg_view"):
            return
        path_text = self.sequence_svg_path_edit.text().strip().strip("\"")
        if not path_text:
            self.sequence_svg_status_label.setText("SVG: path not set")
            return
        path = Path(path_text)
        if not path.exists():
            self.sequence_svg_status_label.setText("SVG: file not found")
            if not silent:
                self._show_error(f"SVG not found: {path}")
            return
        ok = self.sequence_svg_view.load_svg(str(path))
        if not ok:
            self.sequence_svg_status_label.setText("SVG: load failed")
            if not silent:
                self._show_error("SVG load failed (QtSvg unavailable or invalid SVG)")
            return
        self.sequence_svg_status_label.setText(f"SVG: loaded {path.name}")
        self.log(f"[SEQ] svg loaded {path}")

    def _record_sequence(self, event: str, slot: Optional[str] = None) -> None:
        if not hasattr(self, "sequence_table"):
            return
        self._update_auth_watch(event, slot)
        event_text = event
        if self._endurance_active_cycle is not None:
            event_text = f"[CYCLE {self._endurance_active_cycle:03d}] {event}"
        now = time.perf_counter()
        if self._sequence_start is None:
            self._sequence_start = now
        elapsed = now - self._sequence_start
        if self._sequence_events:
            delta_ms = (now - self._sequence_events[-1]["time"]) * 1000
        else:
            delta_ms = 0.0
        entry = {
            "time": now,
            "elapsed": elapsed,
            "delta_ms": delta_ms,
            "slot": slot or "",
            "event": event_text,
        }
        self._sequence_events.append(entry)
        self._append_sequence_row(entry)
        self._append_active_sequence_csv(entry)

    def _append_sequence_row(self, entry: dict) -> None:
        if self.sequence_table.rowCount() > 2000:
            self.sequence_table.removeRow(0)
            if self._sequence_events:
                self._sequence_events.pop(0)
        row = self.sequence_table.rowCount()
        self.sequence_table.insertRow(row)
        values = [
            f"{entry['elapsed']:.3f}",
            f"{entry['delta_ms']:.1f}",
            entry["slot"],
            entry["event"],
        ]
        for col, value in enumerate(values):
            item = QTableWidgetItem(str(value))
            item.setFlags(item.flags() & ~Qt.ItemIsEditable)
            self.sequence_table.setItem(row, col, item)
        self.sequence_table.scrollToBottom()

    def _clear_sequence_events(self) -> None:
        self._sequence_events.clear()
        self._sequence_start = None
        self.sequence_table.setRowCount(0)
        for timer in self._auth_watch_timers.values():
            timer.stop()

    def _update_auth_watch(self, event: str, slot: Optional[str]) -> None:
        if not slot or slot not in self._slots:
            return
        timer = self._auth_watch_timers.get(slot)
        if timer is None:
            return
        upper = (event or "").strip().upper()
        # CONNECTED alone should not trigger auth timeout because many firmware
        # builds run with STRICT_BLE_SECURITY=0 and never emit AUTH_* callbacks.
        if upper == "CONNECTED":
            timer.stop()
            return

        # Arm timeout only when pairing/auth flow actually started.
        if upper in ("PAIR_REQ", "PAIR_REQ_PENDING"):
            timer.start(int(AUTH_EVENT_TIMEOUT_S * 1000))
            return

        # Stop watch on final/terminal auth related states.
        if upper in ("DISCONNECTED", "PAIR_FAIL", "PAIR_UNSUPPORTED", "NO_CONNECTION"):
            timer.stop()
            return
        if upper.startswith("AUTH_"):
            timer.stop()

    def _on_auth_watch_timeout(self, slot: str) -> None:
        self.log(
            f"[AUTH] {slot} timeout: no AUTH result within {AUTH_EVENT_TIMEOUT_S:.1f}s after PAIR_REQ"
        )
        # Persist as sequence event so it is included in CSV/reporting.
        self._record_sequence("AUTH_TIMEOUT", slot)

    def _export_sequence_csv(self) -> None:
        path = self._log_dir / f"sequence_events_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["time_sec", "delta_ms", "slot", "event"])
            for entry in self._sequence_events:
                writer.writerow(
                    [
                        f"{entry['elapsed']:.3f}",
                        f"{entry['delta_ms']:.1f}",
                        entry["slot"],
                        entry["event"],
                    ]
                )
        self._sync_sequence_csv_edits(path)
        self._copy_path_to_clipboard(path, "Sequence CSV")
        self.log(f"[SEQ] saved {path}")

    def _export_sequence_mermaid(self) -> None:
        if not self._sequence_events:
            self._show_error("No sequence events to export")
            return

        def _clean(text: str) -> str:
            cleaned = re.sub(r"[\r\n\t]+", " ", text)
            cleaned = cleaned.replace("|", "/").replace("<", "(").replace(">", ")")
            cleaned = cleaned.replace(";", ",")
            cleaned = cleaned.replace("->>", " to ").replace("-->", " to ").replace("->", " to ")
            cleaned = cleaned.replace("`", "'")
            cleaned = "".join(
                ch if 32 <= ord(ch) <= 126 else " " for ch in cleaned
            )
            cleaned = re.sub(r"\s+", " ", cleaned).strip()
            if len(cleaned) > 160:
                cleaned = cleaned[:157] + "..."
            return cleaned

        participants = ["TOOL", "ANDROID", "MCU"] + self._slots
        lines = ["sequenceDiagram"]
        for name in participants:
            lines.append(f"participant {name}")

        for entry in self._sequence_events:
            slot = entry.get("slot") or "TOOL"
            event = _clean(str(entry.get("event", "")))
            if not event:
                continue
            ts = float(entry.get("elapsed", 0.0))
            message = f"{ts:.3f}s {event}" if event else f"{ts:.3f}s"
            if slot in ("ANDROID", "MCU"):
                lines.append(f"{slot}->>TOOL: {message}")
            elif slot in self._slots:
                lines.append(f"TOOL->>{slot}: {message}")
            else:
                lines.append(f"TOOL->>TOOL: {message}")

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        mmd_path = self._log_dir / f"sequence_diagram_{timestamp}.mmd"
        md_path = self._log_dir / f"sequence_diagram_{timestamp}.md"
        content = "\n".join(lines)
        mmd_path.write_text(content, encoding="utf-8")
        md_path.write_text(f"```mermaid\n{content}\n```", encoding="utf-8")
        self.log(f"[SEQ] saved {mmd_path}")

    def _estimate_timing(self) -> None:
        def _to_float(edit: QLineEdit, fallback: float) -> float:
            try:
                return float(edit.text().strip())
            except ValueError:
                return fallback

        thresholds = self._compute_timing_thresholds()
        adv_interval = thresholds["adv_interval_ms"]
        adv_timeout = thresholds["adv_timeout_s"]
        scan_interval = thresholds["scan_interval_ms"]
        scan_window = thresholds["scan_window_ms"]
        connect_timeout = thresholds["connect_timeout_s"]
        gatt_timeout = thresholds["gatt_timeout_s"]
        detect_best = thresholds["detect_best_ms"]
        detect_worst = thresholds["detect_worst_ms"]
        total_best = thresholds["total_best_ms"]
        total_worst = thresholds["total_worst_ms"]

        adv_rate = 1000.0 / adv_interval if adv_interval > 0 else 0.0
        scan_duty = (
            (scan_window / scan_interval) if scan_interval > 0 else 0.0
        )

        lines = [
            f"Adv interval: {adv_interval:.1f} ms",
            f"Adv timeout: {adv_timeout:.1f} s ({adv_timeout * 1000:.0f} ms)",
            f"Adv packets/sec (approx): {adv_rate:.2f}",
            f"Scan interval: {scan_interval:.1f} ms",
            f"Scan window: {scan_window:.1f} ms",
            f"Scan duty: {scan_duty * 100:.1f} %",
            f"Detection (best): ~{detect_best:.1f} ms",
            f"Detection (worst): ~{detect_worst:.1f} ms",
            f"Connect timeout: {connect_timeout:.1f} s",
            f"GATT timeout: {gatt_timeout:.1f} s",
            f"Total (best): ~{total_best:.1f} ms",
            f"Total (worst): ~{total_worst:.1f} ms",
        ]
        self.timing_output.setPlainText("\n".join(lines))

    def _compute_timing_thresholds(self) -> dict:
        def _to_float(edit: QLineEdit, fallback: float) -> float:
            try:
                return float(edit.text().strip())
            except ValueError:
                return fallback

        adv_interval = _to_float(self.adv_interval_edit, 100.0)
        adv_timeout = _to_float(self.adv_timeout_edit, 60.0)
        scan_interval = _to_float(self.scan_interval_edit, 100.0)
        scan_window = _to_float(self.scan_window_edit, 50.0)
        connect_timeout = _to_float(self.connect_timeout_edit, config.CONNECT_TIMEOUT)
        gatt_timeout = _to_float(self.gatt_timeout_edit, 5.0)

        detect_best = adv_interval
        detect_worst = adv_interval + scan_interval
        total_best = detect_best + connect_timeout * 1000 + gatt_timeout * 1000
        total_worst = detect_worst + connect_timeout * 1000 + gatt_timeout * 1000
        return {
            "adv_interval_ms": adv_interval,
            "adv_timeout_s": adv_timeout,
            "scan_interval_ms": scan_interval,
            "scan_window_ms": scan_window,
            "connect_timeout_s": connect_timeout,
            "gatt_timeout_s": gatt_timeout,
            "detect_best_ms": detect_best,
            "detect_worst_ms": detect_worst,
            "total_best_ms": total_best,
            "total_worst_ms": total_worst,
        }

    def _analyze_sequence_timing_csv(self) -> None:
        path_text = self.sequence_timing_csv_edit.text().strip().strip("\"")
        if not path_text:
            self._show_error("Set CSV path")
            return
        path = Path(path_text)
        if not path.exists():
            self._show_error(f"CSV not found: {path}")
            return
        try:
            events = self._load_sequence_events_from_csv(path)
        except Exception as exc:
            self._show_error(f"Analyze CSV failed: {exc}")
            return
        self._analyze_sequence_timing(events)
        self.log(f"[SEQ] timing analyzed {path}")

    def _analyze_sequence_timing_current(self) -> None:
        if not self._sequence_events:
            self._show_error("No sequence events")
            return
        events = [
            (entry.get("elapsed", 0.0), str(entry.get("event", "")))
            for entry in self._sequence_events
        ]
        self._analyze_sequence_timing(events)

    def _analyze_sequence_timing(self, events: list[tuple[float, str]]) -> None:
        if not events:
            self._show_error("No events for timing analysis")
            return
        events.sort(key=lambda item: item[0])
        t_scan_start = None
        t_scan_end = None
        t_connect_start = None
        t_connect = None

        def _normalize_event(text: str) -> str:
            return re.sub(r"^\[CYCLE\s+\d+\]\s*", "", text or "")

        def _is_scan_start(event_text: str, lower_text: str) -> bool:
            if "scan_start" in lower_text:
                return True
            if "onscannerregistered" in lower_text or "startscan" in lower_text:
                return True
            if "lescan" in lower_text:
                return True
            if "btm_ble_process_adv_addr" in lower_text:
                return True
            if "waiting for scan response" in lower_text:
                return True
            return False

        def _is_connect_start(event_text: str, lower_text: str) -> bool:
            if (
                "gatt_connect" in lower_text
                or "btif_gattc_open" in lower_text
                or "api_open_evt" in lower_text
                or "bta_gattc_api_open_evt" in lower_text
                or "direct_connect_add" in lower_text
                or event_text == "CONNECT_START"
            ):
                return True
            if "ble_conn_state" in lower_text and "state=connecting" in lower_text:
                return True
            if "acl_connected" in lower_text:
                return True
            if "connection action: android.bluetooth.device.action.acl_connected" in lower_text:
                return True
            return False

        def _is_connect_done(event_text: str, lower_text: str) -> bool:
            if event_text == "CONNECTED" or event_text.endswith(" CONNECTED"):
                return True
            if "connected: 1" in lower_text:
                return True
            if " is connected" in lower_text:
                return True
            if "acl_connected" in lower_text:
                return True
            return False

        for time_sec, raw_event in events:
            event = _normalize_event(raw_event)
            lower = event.lower()
            if t_scan_start is None and _is_scan_start(event, lower):
                t_scan_start = time_sec
            if t_scan_end is None and ("scan_done" in lower or "scan_fail" in lower):
                t_scan_end = time_sec
            if t_connect_start is None and _is_connect_start(event, lower):
                t_connect_start = time_sec
            if t_connect is None and _is_connect_done(event, lower):
                t_connect = time_sec

        def _is_gatt_event(event_text: str, lower_text: str) -> bool:
            if event_text == "GATT" or "BATTERY_READ" in event_text:
                return True
            if "gatt_ready" in lower_text:
                return True
            if "service discovery finished" in lower_text:
                return True
            if "notify_on" in lower_text or "notify_off" in lower_text:
                return True
            if "cmd_rx" in lower_text or "cmd_unknown" in lower_text:
                return True
            if "ack" in lower_text and "notify" in lower_text:
                return True
            if "gattc_start_discover" in lower_text or "gattc_discover" in lower_text:
                return True
            if "gatt" in lower_text and "discover" in lower_text:
                return True
            if "gatt_disconnect" in lower_text or "gatt_deregister" in lower_text:
                return True
            if "gatt" in lower_text and ("read" in lower_text or "write" in lower_text or "notify" in lower_text):
                return True
            if "gatt" in lower_text and "att protocol channel" in lower_text and "connected" in lower_text:
                return True
            return False

        t_gatt = None
        if t_connect is not None:
            for time_sec, raw_event in events:
                if time_sec < t_connect:
                    continue
                event = _normalize_event(raw_event)
                lower = event.lower()
                if _is_gatt_event(event, lower):
                    t_gatt = time_sec
                    break

        if t_scan_start is None:
            t_scan_start = events[0][0]
        if t_scan_end is None:
            if t_connect_start is not None:
                t_scan_end = t_connect_start
            elif t_connect is not None:
                t_scan_end = t_connect
        if t_connect_start is None:
            if t_scan_end is not None:
                t_connect_start = t_scan_end
            elif t_connect is not None:
                t_connect_start = t_connect
        if t_connect is None and t_scan_end is not None:
            t_connect = t_scan_end
        if t_gatt is None:
            t_gatt = t_connect

        if t_scan_end is None:
            t_scan_end = t_scan_start

        # Guard against out-of-order/noisy logs so durations do not go negative.
        if t_connect_start is not None and t_scan_start is not None and t_connect_start < t_scan_start:
            t_scan_start = t_connect_start
        if t_scan_end is not None and t_scan_start is not None and t_scan_end < t_scan_start:
            t_scan_end = t_scan_start
        if t_connect_start is not None and t_scan_end is not None and t_connect_start < t_scan_end:
            t_scan_end = t_connect_start
        if t_connect is not None and t_connect_start is not None and t_connect < t_connect_start:
            t_connect = t_connect_start
        if t_gatt is not None and t_connect is not None and t_gatt < t_connect:
            t_gatt = t_connect

        thresholds = self._compute_timing_thresholds()
        detect_worst_ms = thresholds["detect_worst_ms"]
        connect_limit_ms = thresholds["connect_timeout_s"] * 1000.0
        gatt_limit_ms = thresholds["gatt_timeout_s"] * 1000.0
        total_worst_ms = thresholds["total_worst_ms"]

        scan_ms = (t_scan_end - t_scan_start) * 1000.0 if t_scan_start is not None else None
        connect_ms = (
            (t_connect - t_connect_start) * 1000.0
            if (t_connect is not None and t_connect_start is not None)
            else None
        )
        gatt_ms = (
            (t_gatt - t_connect) * 1000.0 if (t_gatt is not None and t_connect is not None) else None
        )
        total_ms = (
            (t_gatt - t_scan_start) * 1000.0 if (t_gatt is not None and t_scan_start is not None) else None
        )

        self._update_sequence_timing_summary(
            scan_ms,
            connect_ms,
            gatt_ms,
            total_ms,
            detect_worst_ms,
            connect_limit_ms,
            gatt_limit_ms,
            total_worst_ms,
        )
        self._update_sequence_timing_chart(
            t_scan_start,
            t_scan_end,
            t_connect,
            t_gatt,
            detect_worst_ms / 1000.0,
            total_worst_ms / 1000.0,
        )

    def _update_sequence_timing_summary(
        self,
        scan_ms: Optional[float],
        connect_ms: Optional[float],
        gatt_ms: Optional[float],
        total_ms: Optional[float],
        scan_limit_ms: float,
        connect_limit_ms: float,
        gatt_limit_ms: float,
        total_limit_ms: float,
    ) -> None:
        def _update(key: str, actual: Optional[float], limit: float) -> None:
            labels = self.sequence_timing_labels.get(key)
            if not labels:
                return
            if actual is None:
                labels["actual"].setText("--")
                labels["limit"].setText(f"{limit:.0f}")
                labels["result"].setText("N/A")
                self._set_label_style(labels["result"], "#616161", "#ffffff")
                return
            labels["actual"].setText(f"{actual:.0f}")
            labels["limit"].setText(f"{limit:.0f}")
            if actual <= limit:
                labels["result"].setText("PASS")
                self._set_label_style(labels["result"], "#2e7d32", "#ffffff")
            else:
                labels["result"].setText("FAIL")
                self._set_label_style(labels["result"], "#d32f2f", "#ffffff")

        _update("scan", scan_ms, scan_limit_ms)
        _update("connect", connect_ms, connect_limit_ms)
        _update("gatt", gatt_ms, gatt_limit_ms)
        _update("total", total_ms, total_limit_ms)

    def _update_sequence_timing_chart(
        self,
        t_scan_start: Optional[float],
        t_scan_end: Optional[float],
        t_connect: Optional[float],
        t_gatt: Optional[float],
        detect_limit_s: float,
        total_limit_s: float,
    ) -> None:
        for series in self.sequence_timing_series.values():
            series.clear()
        for series in self.sequence_timing_thresholds.values():
            series.clear()

        if t_scan_start is None:
            return
        t0 = t_scan_start

        def rel(value: Optional[float]) -> Optional[float]:
            if value is None:
                return None
            return max(0.0, value - t0)

        scan_start = rel(t_scan_start)
        scan_end = rel(t_scan_end)
        connect_end = rel(t_connect)
        gatt_end = rel(t_gatt)

        if scan_start is not None and scan_end is not None:
            self.sequence_timing_series["scan"].append(scan_start, 3)
            self.sequence_timing_series["scan"].append(scan_end, 3)
        if scan_end is not None and connect_end is not None:
            self.sequence_timing_series["connect"].append(scan_end, 2)
            self.sequence_timing_series["connect"].append(connect_end, 2)
        if connect_end is not None and gatt_end is not None:
            self.sequence_timing_series["gatt"].append(connect_end, 1)
            self.sequence_timing_series["gatt"].append(gatt_end, 1)

        for key, limit in [("detect", detect_limit_s), ("total", total_limit_s)]:
            series = self.sequence_timing_thresholds[key]
            series.append(limit, 0.5)
            series.append(limit, 3.5)

        max_time = max(
            [value for value in [scan_end, connect_end, gatt_end, total_limit_s] if value]
            or [5.0]
        )
        self.sequence_timing_axis_x.setRange(0, max_time * 1.2)

    def _latest_sequence_csv(self) -> str:
        try:
            candidates = sorted(
                self._log_dir.glob("sequence_events_*.csv"),
                key=lambda path: path.stat().st_mtime,
                reverse=True,
            )
        except Exception:
            return ""
        return str(candidates[0]) if candidates else ""

    def _load_sequence_events_from_csv(
        self, path: Path
    ) -> list[tuple[float, str]]:
        events: list[tuple[float, str]] = []
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            reader = csv.reader(handle)
            _ = next(reader, None)
            for row in reader:
                if len(row) < 4:
                    continue
                try:
                    time_sec = float(row[0])
                except ValueError:
                    continue
                # Join tail columns to tolerate logs that contain commas.
                events.append((time_sec, ",".join(row[3:])))
        return events

    def _reset_android_conn_status(self) -> None:
        for slot in self._slots:
            self._android_conn_status[slot] = "UNKNOWN"
            label = self._android_conn_labels.get(slot)
            if label:
                label.setText(f"{slot}: UNKNOWN")
                self._set_label_style(label, "#616161", "#ffffff")
        self._android_connid_slot.clear()
        self._refresh_endurance_visual_all()

    def _apply_android_status(
        self, slot: str, status: str, mac: str = "", reason: str = ""
    ) -> None:
        label = self._android_conn_labels.get(slot)
        if label:
            text = f"{slot}: {status}"
            if mac:
                text += f" ({mac})"
            if reason:
                text += f" [{reason}]"
            label.setText(text)
            color = "#616161"
            if status == "CONNECTED":
                color = "#2e7d32"
            elif status == "FAILED":
                color = "#d32f2f"
            elif status == "DISCONNECTED":
                color = "#455a64"
            self._set_label_style(label, color, "#ffffff")
        self._refresh_endurance_visual_slot(slot)

    def _slot_mac_map(self) -> dict[str, str]:
        mapping: dict[str, str] = {}
        for slot in self._slots:
            name = ""
            if hasattr(self, "slot_widgets"):
                name = self._current_name(slot)
            if name and name in self._device_map:
                mapping[slot] = self._device_map[name].lower()
                continue
            desired = self._desired_slot_names.get(slot, "")
            if desired and desired in self._device_map:
                mapping[slot] = self._device_map[desired].lower()
                continue
            if name:
                mac = self._mac_from_register(slot, name)
                if mac:
                    mapping[slot] = mac.lower()
                    continue
            if desired:
                mac = self._mac_from_register(slot, desired)
                if mac:
                    mapping[slot] = mac.lower()
        return mapping

    def _mac_from_register(self, slot: str, name: str) -> str:
        if not name:
            return ""
        for entry in reversed(self._register_entries):
            if slot.startswith("A") and entry.a_name == name and entry.a_mac:
                return entry.a_mac
            if slot.startswith("B") and entry.b_name == name and entry.b_mac:
                return entry.b_mac
        return ""

    def _slot_for_name(self, name: str) -> Optional[str]:
        if not name:
            return None
        if hasattr(self, "slot_widgets"):
            for slot in self._slots:
                current = self._current_name(slot)
                if current and current == name:
                    return slot
        for slot in self._slots:
            desired = self._desired_slot_names.get(slot, "")
            if desired and desired == name:
                return slot
        return None

    def _slot_for_mac(self, mac: str) -> Optional[str]:
        mac_lower = mac.lower()
        slot_map = self._slot_mac_map()
        for slot, slot_mac in slot_map.items():
            if slot_mac.lower() == mac_lower:
                return slot
        # fallback to register entries (best effort)
        for entry in reversed(self._register_entries):
            if entry.a_mac.lower() == mac_lower:
                return "A1" if self._android_conn_status.get("A1") == "UNKNOWN" else "A2"
            if entry.b_mac.lower() == mac_lower:
                return "B1" if self._android_conn_status.get("B1") == "UNKNOWN" else "B2"
        return None

    def _slot_for_side_hint(self, side_hint: str) -> Optional[str]:
        hint = side_hint.strip().upper()
        if hint in self._slots:
            return hint
        if hint == "A":
            if self._android_conn_status.get("A1") == "CONNECTED":
                return "A1"
            if self._android_conn_status.get("A2") == "CONNECTED":
                return "A2"
            return "A1"
        if hint == "B":
            if self._android_conn_status.get("B1") == "CONNECTED":
                return "B1"
            if self._android_conn_status.get("B2") == "CONNECTED":
                return "B2"
            return "B1"
        return None

    def _slot_for_conn_id(self, conn_id: str, create_if_missing: bool = False) -> Optional[str]:
        cid = conn_id.lower()
        if cid in self._android_connid_slot:
            return self._android_connid_slot[cid]
        if not create_if_missing:
            return None
        # Prefer slots that are not already connected.
        for slot in self._slots:
            if self._android_conn_status.get(slot) in ("UNKNOWN", "FAILED", "DISCONNECTED"):
                self._android_connid_slot[cid] = slot
                return slot
        return None

    def _update_mcu_from_line(self, line: str, to_sequence: bool) -> bool:
        match = MCU_STATE_PATTERN.search(line)
        if not match:
            return False
        state = match.group(1)
        detail = (match.group(2) or "").strip()
        slot = self._mcu_last_slot

        if state == "DEVICE_NAME" and detail:
            self._mcu_last_name = detail
            slot = self._slot_for_name(detail) or slot
            if slot:
                self._mcu_last_slot = slot
            if to_sequence:
                self._record_sequence(f"DEVICE_NAME {detail}", slot or "MCU")
            return True

        if state == "MAC":
            mac_match = MAC_PATTERN.search(detail) or MAC_PATTERN.search(line)
            if mac_match:
                self._mcu_last_mac = mac_match.group(0)
                slot = self._slot_for_mac(self._mcu_last_mac) or slot
                if slot:
                    self._mcu_last_slot = slot
                if to_sequence:
                    self._record_sequence(f"MAC {self._mcu_last_mac}", slot or "MCU")
                return True

        state_to_ui = {
            "ADV_START": "ADV",
            "ADV_WAIT_CONNECT": "ADV",
            "CONNECTED": "CONNECT",
            "DISCONNECTED": "DISCONNECT",
            "GATT_READY": "GATT",
        }
        if slot and state in state_to_ui:
            self._set_state(slot, state_to_ui[state])
        if slot and state == "DISCONNECTED":
            self._slot_output_enabled[slot] = None
            self._refresh_endurance_visual_slot(slot)
        if slot and state in ("OUTPUT_ON", "LED_ON", "OUTPUT_ENABLE_ON"):
            self._slot_output_enabled[slot] = True
            self._refresh_endurance_visual_slot(slot)
        if slot and state in ("OUTPUT_OFF", "LED_OFF", "OUTPUT_ENABLE_OFF"):
            self._slot_output_enabled[slot] = False
            self._refresh_endurance_visual_slot(slot)
        if slot and state == "VOLTAGE_READ":
            voltage_match = re.search(r"([0-9]+(?:\\.[0-9]+)?)\\s*V", detail, re.IGNORECASE)
            if voltage_match:
                try:
                    self._set_battery(slot, float(voltage_match.group(1)))
                except ValueError:
                    pass

        event_text = state
        if state == "VOLTAGE_READ":
            event_text = "BATTERY_READ"
        if to_sequence:
            self._record_sequence(event_text, slot or "MCU")
        return True

    def _update_android_conn_from_line(self, line: str) -> None:
        lower = line.lower()
        macs = MAC_PATTERN.findall(line)
        conn_ids = re.findall(r"conn_id=0x([0-9a-f]+)", lower)
        conn_ids_primary = re.findall(
            r"gattc_(?:read|write)\s*:\s*conn_id=0x([0-9a-f]+)", lower
        )
        side_match = re.search(r"side=([a-z0-9]+)", lower)
        side_hint = side_match.group(1) if side_match else ""
        status: Optional[str] = None
        reason = ""
        reason_eq_match = re.search(r"reason=([^\\s\\]]+)", lower)
        if reason_eq_match:
            reason = reason_eq_match.group(1)
        connected_match = re.search(r"connected:\s*(\d)", lower)
        if "ble_conn_state" in lower:
            state_match = re.search(r"state=([a-z_]+)", lower)
            state_text = state_match.group(1) if state_match else ""
            if "connected" in state_text:
                status = "CONNECTED"
            elif "disconnected" in state_text:
                status = "DISCONNECTED"
            failure_match = re.search(r"failure=([^\\]]+)$", lower)
            if failure_match and not reason:
                failure_text = failure_match.group(1).strip()
                if failure_text and failure_text != "-":
                    reason = failure_text
        elif "ble_conn_error" in lower:
            status = "FAILED"
            error_match = re.search(r"error=(.+)$", line, re.IGNORECASE)
            if error_match:
                reason = error_match.group(1).strip()
        if "acl_connected" in lower:
            status = "CONNECTED"
        elif "ble_app_close" in lower:
            status = "DISCONNECTED"
            if not reason:
                reason = "app_close"
        elif "bta_gattc_api_close_evt" in lower:
            status = "DISCONNECTED"
            if not reason:
                reason = "api_close_evt"
        elif "gatt_deregister" in lower:
            status = "DISCONNECTED"
            if not reason:
                reason = "gatt_deregister"
        elif "acl_disconnected" in lower:
            status = "DISCONNECTED"
            reason_match = re.search(r"reason:\s*([0-9a-fx]+)", lower)
            if reason_match:
                reason = reason_match.group(1)
        elif connected_match:
            is_connected = connected_match.group(1) == "1"
            status = "CONNECTED" if is_connected else "FAILED"
            reason_match = re.search(r"reason:\s*([0-9a-fx]+)", lower)
            if reason_match:
                reason = reason_match.group(1)
        elif "status 133" in lower or "gatt_error" in lower:
            status = "FAILED"
            status_match = re.search(r"status\s+(\d+)", lower)
            if status_match:
                reason = status_match.group(1)
        elif "adv characteristic not found" in lower or "profile_missing" in lower:
            status = "FAILED"
            if not reason:
                reason = "profile_missing"
        elif "is connected" in lower:
            status = "CONNECTED"
        elif "is disconnected" in lower or "disconnected" in lower:
            status = "DISCONNECTED"
        elif (
            "gattc_conn_st" in lower
            or "bta_gattc_api_read_evt" in lower
            or "bta_gattc_api_write_evt" in lower
            or "gattc_read:" in lower
            or "gattc_write" in lower
        ):
            # Fallback: infer connected when active GATT data-path is observed.
            status = "CONNECTED"
            if not reason:
                reason = "inferred_from_gatt"

        if not status:
            return
        slot_updates: list[tuple[str, str]] = []
        for mac in macs:
            slot = self._slot_for_mac(mac)
            if slot:
                slot_updates.append((slot, mac))
            else:
                self.log(f"[SEQ] Android status {status} (unmapped MAC {mac})")

        if not slot_updates and side_hint:
            slot = self._slot_for_side_hint(side_hint)
            if slot:
                slot_updates.append((slot, ""))

        # Try conn_id-based mapping when MAC is redacted/missing in logcat.
        conn_id_candidates = conn_ids_primary if conn_ids_primary else conn_ids
        if not slot_updates and conn_id_candidates:
            for conn_id in conn_id_candidates:
                slot = self._slot_for_conn_id(
                    conn_id, create_if_missing=(status == "CONNECTED")
                )
                if slot:
                    slot_updates.append((slot, f"conn:0x{conn_id}"))
                if status in ("DISCONNECTED", "FAILED"):
                    self._android_connid_slot.pop(conn_id.lower(), None)

        if not slot_updates and (
            "bta_gattc_api_close_evt" in lower
            or "gatt_deregister" in lower
            or "ble_app_close" in lower
        ):
            connected_slots = [
                slot for slot in self._slots if self._android_conn_status.get(slot) == "CONNECTED"
            ]
            if connected_slots:
                slot_updates.extend((slot, "") for slot in connected_slots)

        if not slot_updates:
            return

        seen_slots: set[str] = set()
        for slot, mac in slot_updates:
            if slot in seen_slots:
                continue
            seen_slots.add(slot)
            self._android_conn_status[slot] = status
            self._apply_android_status(slot, status, mac, reason)

        # Keep conn_id->slot mapping fresh for later lines.
        if status == "CONNECTED" and conn_id_candidates:
            target_slot = next(iter(seen_slots), None)
            if target_slot:
                for conn_id in conn_id_candidates:
                    self._android_connid_slot[conn_id.lower()] = target_slot

    def _analyze_android_csv(self) -> None:
        path_text = self.android_csv_path_edit.text().strip().strip("\"")
        if not path_text:
            self._show_error("Set CSV path")
            return
        path = Path(path_text)
        if not path.exists():
            self._show_error(f"CSV not found: {path}")
            return
        self._reset_android_conn_status()
        events_for_timing: list[tuple[float, str]] = []
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                reader = csv.reader(handle)
                _ = next(reader, None)
                for row in reader:
                    if not row:
                        continue
                    event = ",".join(row[3:]) if len(row) > 3 else ",".join(row)
                    if len(row) > 3:
                        try:
                            time_sec = float(row[0])
                            events_for_timing.append((time_sec, event))
                        except ValueError:
                            pass
                    if "ANDROID:" in event:
                        line = event.split("ANDROID:", 1)[1].strip()
                        self._update_android_conn_from_line(line)
                    else:
                        self._update_android_conn_from_line(event)
            # Keep top and bottom analysis in sync when upper Analyze CSV is used.
            if events_for_timing:
                self._analyze_sequence_timing(events_for_timing)
            self.log(f"[SEQ] analyzed {path}")
        except Exception as exc:
            self._show_error(f"Analyze CSV failed: {exc}")

    def _handle_external_line(self, source: str, line: str, to_sequence: bool) -> None:
        if source == "ANDROID":
            self._update_android_conn_from_line(line)
            if self._is_ble_log(line):
                self.ble_log_view.appendPlainText(line)
                self.ble_log_view.ensureCursorVisible()
                if to_sequence:
                    self._record_sequence(f"ANDROID: {line}", "ANDROID")
            else:
                self.other_log_view.appendPlainText(line)
                self.other_log_view.ensureCursorVisible()
                if to_sequence and not self.android_ble_only_check.isChecked():
                    self._record_sequence(f"ANDROID: {line}", "ANDROID")
        elif source == "MCU":
            self.mcu_log_view.appendPlainText(line)
            self.mcu_log_view.ensureCursorVisible()
            handled = self._update_mcu_from_line(line, to_sequence)
            if to_sequence and not handled:
                self._record_sequence(f"MCU: {line}", "MCU")
        else:
            self.other_log_view.appendPlainText(f"[{source}] {line}")
            self.other_log_view.ensureCursorVisible()
            if to_sequence:
                self._record_sequence(f"{source}: {line}", source)
        self.log(f"[EXT-{source}] {line}")

    def _is_ble_log(self, line: str) -> bool:
        text = line.lower()
        keywords = [
            "bt_stack",
            "bluetooth",
            "gatt",
            "btif",
            "bta_gatt",
            "btm",
            "hci",
            "ble",
            "flutter_reactive_ble",
            "reactive_ble",
        ]
        return any(key in text for key in keywords)

    def _find_adb_path(self) -> str:
        candidates: list[Path] = []
        for env_key in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
            value = os.environ.get(env_key)
            if value:
                candidates.append(Path(value) / "platform-tools" / "adb.exe")
        candidates.append(
            Path.home() / "AppData" / "Local" / "Android" / "Sdk" / "platform-tools" / "adb.exe"
        )
        candidates.append(Path("C:/Android/sdk/platform-tools/adb.exe"))
        for path in candidates:
            if path.exists():
                return str(path)
        return ""

    def _resolve_adb_path(self, value: str) -> Optional[str]:
        text = value.strip()
        if not text:
            text = "adb"
        if Path(text).exists():
            return text
        resolved = shutil.which(text)
        if resolved:
            return resolved
        if text.lower() in ("adb", "adb.exe") and self._adb_path_guess:
            if Path(self._adb_path_guess).exists():
                return self._adb_path_guess
        return None

    def _start_logcat(self) -> None:
        if self._logcat_worker and self._logcat_worker.isRunning():
            return
        adb_path_input = self.adb_path_edit.text()
        adb_path = self._resolve_adb_path(adb_path_input)
        if not adb_path:
            self._show_error(
                "adb not found. Set full path (e.g. C:\\Users\\user\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe)"
            )
            return
        try:
            subprocess.run(
                [adb_path, "logcat", "-c"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=5,
            )
        except Exception as exc:
            self.log(f"[SEQ] adb logcat -c skipped: {exc}")
        self._start_active_sequence_csv("logcat")
        filter_text = self.logcat_filter_edit.text().strip()
        self._logcat_worker = LogcatWorker(adb_path, filter_text)
        self._logcat_worker.line_ready.connect(
            lambda line: self._handle_external_line(
                "ANDROID", line, self.android_add_sequence_check.isChecked()
            )
        )
        self._logcat_worker.error.connect(self._show_error)
        self._logcat_worker.finished.connect(self._on_logcat_finished)
        self._logcat_worker.start()
        self.logcat_status.setText("RUNNING")
        self.logcat_start_button.setEnabled(False)
        self.logcat_stop_button.setEnabled(True)

    def _stop_logcat(self) -> None:
        if self._logcat_worker:
            self._logcat_worker.stop()
        self._on_logcat_finished()

    def _on_logcat_finished(self) -> None:
        self.logcat_status.setText("IDLE")
        self.logcat_start_button.setEnabled(True)
        self.logcat_stop_button.setEnabled(False)

    def _start_serial(self) -> None:
        if self._serial_worker and self._serial_worker.isRunning():
            return
        port = self.serial_port_combo.currentText().strip()
        if self._is_unconnected_port(port):
            self._show_error("Select a serial port")
            return
        try:
            baud = int(self.serial_baud_edit.text().strip())
        except ValueError:
            self._show_error("Invalid baud rate")
            return
        self._start_active_sequence_csv("serial")
        self._serial_worker = SerialWorker(port, baud)
        self._serial_worker.line_ready.connect(
            lambda line: self._handle_external_line(
                "MCU", line, self.mcu_add_sequence_check.isChecked()
            )
        )
        self._serial_worker.error.connect(self._show_error)
        self._serial_worker.finished.connect(self._on_serial_finished)
        self._serial_worker.start()
        self.serial_status.setText("RUNNING")
        self.serial_start_button.setEnabled(False)
        self.serial_stop_button.setEnabled(True)

    def _stop_serial(self) -> None:
        if self._serial_worker:
            self._serial_worker.stop()
        self._on_serial_finished()

    def _on_serial_finished(self) -> None:
        self.serial_status.setText("IDLE")
        self.serial_start_button.setEnabled(True)
        self.serial_stop_button.setEnabled(False)

    def _refresh_monitor_ports(self) -> None:
        ports = self._list_ports()
        combo = self.serial_port_combo
        current = combo.currentText()
        self._fill_port_combo(combo, ports, current)

    # --------------------------- RSSI Monitor ---------------------------
    async def _start_rssi_monitor(self) -> None:
        if self._rssi_task and not self._rssi_task.done():
            return
        try:
            interval = float(self.rssi_interval_edit.text().strip())
        except ValueError:
            interval = 2.0
        try:
            timeout = float(self.rssi_timeout_edit.text().strip())
        except ValueError:
            timeout = 2.0
        if interval <= 0:
            interval = 1.0
        if timeout <= 0:
            timeout = 1.0
        self._rssi_interval = interval
        self._rssi_timeout = timeout
        self.rssi_status.setText("RUNNING")
        self.rssi_start_button.setEnabled(False)
        self.rssi_stop_button.setEnabled(True)
        self._rssi_start = time.perf_counter()
        self._rssi_task = asyncio.create_task(self._rssi_loop())

    def _stop_rssi_monitor(self) -> None:
        if self._rssi_task and not self._rssi_task.done():
            self._rssi_task.cancel()
        self.rssi_status.setText("IDLE")
        self.rssi_start_button.setEnabled(True)
        self.rssi_stop_button.setEnabled(False)

    async def _rssi_loop(self) -> None:
        self.log("[RSSI] monitor start")
        try:
            while True:
                await self._poll_rssi_once()
                await asyncio.sleep(self._rssi_interval)
        except asyncio.CancelledError:
            pass
        finally:
            self.log("[RSSI] monitor stop")

    async def _poll_rssi_once(self) -> None:
        async with self._scan_lock:
            rssi_map: dict[str, int] = {}

            def _callback(device, adv_data) -> None:
                rssi = getattr(adv_data, "rssi", None)
                if rssi is None:
                    return
                if device.name:
                    rssi_map[device.name] = rssi
                rssi_map[device.address] = rssi

            scanner = BleakScanner(detection_callback=_callback)
            try:
                await scanner.start()
                await asyncio.sleep(self._rssi_timeout)
            except Exception as exc:
                self.log(f"[RSSI] scan failed: {exc}")
                return
            finally:
                try:
                    await scanner.stop()
                except Exception:
                    pass
        now = time.perf_counter()
        if self._rssi_start is None:
            self._rssi_start = now
        elapsed = now - self._rssi_start
        updated = False
        for slot in self._slots:
            name = self._current_name(slot)
            if not name:
                self._update_rssi_status(slot, None, selected=False)
                continue
            rssi = None
            if name in rssi_map:
                rssi = rssi_map[name]
            else:
                addr = self._device_map.get(name)
                if addr and addr in rssi_map:
                    rssi = rssi_map[addr]
            self._rssi_events[slot].append((elapsed, rssi))
            if rssi is not None:
                self.rssi_series[slot].append(elapsed, rssi)
                updated = True
            self._update_rssi_status(slot, rssi, selected=True)
        if updated:
            self._update_rssi_axes(elapsed)

    def _update_rssi_axes(self, elapsed: float) -> None:
        max_x = max(10.0, elapsed)
        min_x = max(0.0, max_x - 60.0)
        self.rssi_axis_x.setRange(min_x, min_x + 60.0)

    def _clear_rssi_data(self) -> None:
        self._rssi_events = {slot: [] for slot in self._slots}
        self._rssi_start = time.perf_counter()
        for series in self.rssi_series.values():
            series.clear()
        self.rssi_axis_x.setRange(0, 60)
        for slot in self._slots:
            self._update_rssi_status(slot, None, selected=False)

    def _export_rssi_csv(self) -> None:
        path = self._log_dir / f"rssi_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["time_sec", "slot", "rssi"])
            for slot, samples in self._rssi_events.items():
                for elapsed, rssi in samples:
                    writer.writerow([f"{elapsed:.3f}", slot, "" if rssi is None else rssi])
        self._copy_path_to_clipboard(path, "RSSI CSV")
        self.log(f"[RSSI] saved {path}")

    def _update_rssi_status(
        self, slot: str, rssi: Optional[int], selected: bool
    ) -> None:
        label = self._rssi_status_labels.get(slot)
        if not label:
            return
        if not selected:
            label.setText(f"{slot}: No Device")
            self._set_label_style(label, "#424242", "#ffffff")
            return
        if rssi is None:
            label.setText(f"{slot}: No Signal")
            self._set_label_style(label, "#616161", "#ffffff")
            return
        if rssi > -50:
            status = "Excellent"
            color = "#2e7d32"
        elif rssi >= -80:
            status = "Good"
            color = "#1e88e5"
        else:
            status = "Weak"
            color = "#d32f2f"
        label.setText(f"{slot}: {rssi} dBm ({status})")
        self._set_label_style(label, color, "#ffffff")

    # --------------------------- BLE logic ---------------------------
    def _bleak_client_kwargs(self, **extra) -> dict:
        kwargs = dict(extra)
        winrt: dict[str, object] = {}
        address_type = getattr(config, "WINRT_ADDRESS_TYPE", None)
        if address_type:
            winrt["address_type"] = address_type
        use_cached_services = getattr(config, "WINRT_USE_CACHED_SERVICES", None)
        if use_cached_services is not None:
            winrt["use_cached_services"] = bool(use_cached_services)
        if winrt:
            kwargs["winrt"] = winrt
        return kwargs

    async def _scan_devices(self) -> None:
        async with self._scan_lock:
            self._record_sequence("SCAN_START")
            self.log("[SCAN] start")
            self.scan_button.setEnabled(False)
            try:
                devices = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
            except Exception as exc:
                self.log(f"[ERROR] Scan failed: {exc}")
                self.scan_button.setEnabled(True)
                self._record_sequence("SCAN_FAIL")
                return

            self._device_map.clear()
            for device in devices:
                if device.name and DEVICE_PATTERN.search(device.name):
                    self._device_map[device.name] = device.address

            for slot in self._slots:
                self._update_device_combo(slot)
                if self._current_name(slot) in self._device_map:
                    self._set_state(slot, "ADV")
                    # New scan with expected name visible: allow retry even if
                    # previous attempt latched PROFILE_MISSING.
                    self._slot_profile_blocked[slot] = False

            self._update_collision_status()
            self.log(f"[SCAN] found {len(self._device_map)} devices")
            self.scan_button.setEnabled(True)
            self._apply_pair2_no_connection_guard_ui()
            self._record_sequence(f"SCAN_DONE ({len(self._device_map)})")

    def _on_scan_clicked(self) -> None:
        self.log("[UI] Scan")
        self._run_async(self._scan_devices())

    def _on_connect_all_clicked(self) -> None:
        self.log("[UI] Connect All")
        self._run_async(self._connect_both())

    def _on_connect_pair1_clicked(self) -> None:
        self.log("[UI] Connect Pair 1")
        self._run_async(self._connect_pair_only(0))

    def _on_connect_pair2_clicked(self) -> None:
        self.log("[UI] Connect Pair 2")
        self._run_async(self._connect_pair_only(1))

    def _on_connect_a2_only_clicked(self) -> None:
        self.log("[UI] Connect A2 Only")
        self._run_async(self._connect_only_slots(["A2"]))

    def _on_connect_b2_only_clicked(self) -> None:
        self.log("[UI] Connect B2 Only")
        self._run_async(self._connect_only_slots(["B2"]))

    def _on_disconnect_all_clicked(self) -> None:
        self.log("[UI] Disconnect All")
        self._run_async(self._disconnect_both(reason="ui-disconnect-all"))

    def _on_reconnect_all_test_clicked(self) -> None:
        self.log("[UI] Reconnect All Test")
        self._run_async(self._reconnect_both_test())

    def _make_disconnected_callback(
        self, slot: str, address: str
    ) -> Callable[[BleakClient], None]:
        loop = asyncio.get_running_loop()

        def _callback(_client) -> None:
            loop.call_soon_threadsafe(
                self._handle_client_disconnected_callback,
                slot,
                address,
            )

        return _callback

    def _handle_client_disconnected_callback(self, slot: str, address: str) -> None:
        now = time.monotonic()
        expected = self._slot_disconnect_expected.get(slot, False)
        self._slot_disconnect_expected[slot] = False
        pair_idx = self._slot_pair_index(slot)
        if pair_idx is not None:
            self._startup_wave_done_pairs[pair_idx] = False
            self._pair_sync_inflight[pair_idx] = False
        connected_since = self._slot_connected_since.get(slot, 0.0)
        connected_for = max(0.0, now - connected_since) if connected_since > 0.0 else 0.0
        if expected:
            self.log(f"[LINK] {slot} disconnect callback (expected) {address}")
            return
        self.log(f"[LINK] {slot} disconnect callback (unexpected) {address}")
        if connected_for <= UNEXPECTED_LINK_DROP_EARLY_S:
            self._slot_unexpected_disconnect_until[slot] = max(
                self._slot_unexpected_disconnect_until.get(slot, 0.0),
                now + UNEXPECTED_LINK_DROP_BACKOFF_S,
            )
            self.log(
                f"[LINK] {slot} early disconnect after {connected_for:.1f}s; "
                f"reconnect cooldown {UNEXPECTED_LINK_DROP_BACKOFF_S:.1f}s; "
                "class=UNEXPECTED_LINK_DROP"
            )
        client = self._clients.get(slot)
        if client and client.is_connected:
            return
        self._clients[slot] = None
        self._set_state(slot, "DISCONNECT")
        self._set_status(slot, "link lost")
        self._slot_connected_since[slot] = 0.0
        self._slot_output_enabled[slot] = None
        self._slot_auth_state[slot] = "UNKNOWN"
        self._slot_auth_error_latched[slot] = False
        self._slot_pair_tried[slot] = False
        self._slot_auth_recover_tried[slot] = False
        self._slot_rebond_tried[slot] = False
        self._slot_session_fixed[slot] = False
        self._slot_write_pref[slot] = (
            False
            if PREFER_WRITE_COMMAND_WHEN_AVAILABLE
            else bool(config.WRITE_RESPONSE)
        )
        self._slot_write_cap_req[slot] = True
        self._slot_write_cap_cmd[slot] = True
        self._slot_adv_char_uuid[slot] = config.ADV_CHR_UUID
        self._slot_adv_char_missing_latched[slot] = False
        self.slot_widgets[slot]["connect_button"].setEnabled(True)
        self.slot_widgets[slot]["disconnect_button"].setEnabled(False)
        self._cancel_color_heartbeat(slot)
        self._cancel_pattern_task(slot)
        if pair_idx is not None:
            self._run_async(self._silence_pair_output(pair_idx))
        self._reset_pair_syncro_cheat_state(pair_idx)
        self._apply_pair2_no_connection_guard_ui()
        self._refresh_endurance_visual_slot(slot)

    async def _connect_slot(self, slot: str) -> bool:
        if not self._guard_slot_execution(slot, "connect"):
            return False
        now = time.monotonic()
        until = self._slot_unexpected_disconnect_until.get(slot, 0.0)
        if now < until:
            remaining = max(0.0, until - now)
            self.log(
                f"[SKIP] {slot} reconnect cooldown active "
                f"({remaining:.1f}s) after unexpected disconnect"
            )
            return False
        if self._slot_profile_blocked.get(slot, False):
            self.log(
                f"[SKIP] {slot} connect blocked (PROFILE_MISSING latched). "
                "Run Scan to clear and retry."
            )
            return False
        until = self._slot_profile_missing_until.get(slot, 0.0)
        if now < until:
            remaining = max(0.0, until - now)
            self.log(
                f"[SKIP] {slot} connect backoff active "
                f"({remaining:.1f}s) after PROFILE_MISSING"
            )
            return False
        if self._clients.get(slot) and self._clients[slot].is_connected:
            if self._slot_session_fixed.get(slot, False):
                self.log(f"[SESSION] {slot} fixed session reuse")
            return True
        name = self._current_name(slot)
        if not name:
            self.log(f"[SKIP] {slot}: no device selected")
            return False
        address = self._device_map.get(name)
        if not address:
            self.log(f"[SKIP] {slot}: '{name}' not found in current scan results")
            return False
        self._set_state(slot, "CONNECT")
        self._set_status(slot, "connecting")
        async with self._connect_lock:
            client = BleakClient(
                address,
                disconnected_callback=self._make_disconnected_callback(slot, address),
                timeout=config.CONNECT_TIMEOUT,
                pair=CONNECT_PAIR_ON_INITIAL,
                **self._bleak_client_kwargs(),
            )
            try:
                await client.connect()
            except BleakError as exc:
                self._set_status(slot, "connect failed")
                self._set_state(slot, "DISCONNECT")
                self.log(f"[ERROR] {slot} connect failed: {exc}")
                return False
            self._clients[slot] = client
            self._slot_connected_since[slot] = time.monotonic()
        if not CONNECT_PAIR_ON_INITIAL:
            self.log(f"[AUTH] {slot} initial connect pair=False (pair on demand)")
        self._slot_output_enabled[slot] = None
        self._slot_auth_state[slot] = "UNKNOWN"
        self._slot_auth_error_latched[slot] = False
        self._slot_pair_tried[slot] = False
        self._slot_auth_recover_tried[slot] = False
        self._slot_rebond_tried[slot] = False
        self._slot_write_pref[slot] = (
            False
            if PREFER_WRITE_COMMAND_WHEN_AVAILABLE
            else bool(config.WRITE_RESPONSE)
        )
        self._slot_write_cap_req[slot] = True
        self._slot_write_cap_cmd[slot] = True
        self._slot_adv_char_uuid[slot] = config.ADV_CHR_UUID
        self._slot_adv_char_missing_latched[slot] = False

        if not await self._ensure_slot_adv_profile(slot, client, context="connect"):
            return False

        self._slot_profile_missing_until[slot] = 0.0
        self._slot_profile_blocked[slot] = False
        self._slot_unexpected_disconnect_until[slot] = 0.0
        self._set_status(slot, "connected")
        self._set_state(slot, "CONNECT")
        self._record_sequence("CONNECTED", slot)
        self.slot_widgets[slot]["connect_button"].setEnabled(False)
        self.slot_widgets[slot]["disconnect_button"].setEnabled(True)
        self.log(f"[STATE] {slot} connected {address}")
        if slot in ("A2", "B2") and not self._slot_session_fixed.get(slot, False):
            self._slot_session_fixed[slot] = True
            self.log(f"[SESSION] {slot} fixed after first successful connect")

        await self._maybe_run_startup_wave_for_pair(slot)
        if self.auto_after_check.isChecked():
            await self._after_both_connected()
        return True

    async def _ensure_slot_adv_profile(
        self, slot: str, client: BleakClient, context: str
    ) -> bool:
        # Some reconnect paths briefly expose only GAP/GATT (1800/1801).
        # Give the peripheral a short grace window before classifying as missing.
        deadline = time.monotonic() + PROFILE_DISCOVERY_GRACE_S
        force_refresh = False
        while True:
            await self._detect_slot_write_caps(slot, client, force_refresh=force_refresh)
            if not self._slot_adv_char_missing_latched.get(slot):
                return True
            if not client.is_connected:
                break
            if time.monotonic() >= deadline:
                break
            force_refresh = True
            await asyncio.sleep(PROFILE_DISCOVERY_POLL_S)

        cooldown_until = self._slot_unexpected_disconnect_until.get(slot, 0.0)
        now = time.monotonic()
        if (not client.is_connected) and now < cooldown_until:
            remaining = max(0.0, cooldown_until - now)
            self.log(
                f"[GATT] {slot} profile discovery aborted by early link drop; "
                f"class=UNEXPECTED_LINK_DROP cooldown={remaining:.1f}s"
            )
            self._record_sequence("GATT_EARLY_LINK_DROP", slot)
            self._set_status(slot, "link drop cooldown")
            self._set_state(slot, "DISCONNECT")
            self._slot_profile_missing_until[slot] = 0.0
            self._slot_profile_blocked[slot] = False
            self._slot_connected_since[slot] = 0.0
            if self._clients.get(slot) is client:
                self._clients[slot] = None
            self.slot_widgets[slot]["connect_button"].setEnabled(True)
            self.slot_widgets[slot]["disconnect_button"].setEnabled(False)
            return False

        self.log(
            f"[GATT] {slot} required characteristic unavailable after {context}; "
            "class=PROFILE_MISSING"
        )
        self._record_sequence("GATT_PROFILE_MISSING", slot)
        self._slot_profile_missing_until[slot] = (
            time.monotonic() + PROFILE_MISSING_BACKOFF_S
        )
        self._slot_profile_blocked[slot] = True
        self._set_status(slot, "profile missing")
        self._set_state(slot, "DISCONNECT")
        self._slot_connected_since[slot] = 0.0
        try:
            if client.is_connected:
                self._slot_disconnect_expected[slot] = True
                await client.disconnect()
        except Exception:
            pass
        finally:
            self._slot_disconnect_expected[slot] = False
        if self._clients.get(slot) is client:
            self._clients[slot] = None
        self.slot_widgets[slot]["connect_button"].setEnabled(True)
        self.slot_widgets[slot]["disconnect_button"].setEnabled(False)
        return False

    async def _disconnect_slot(
        self,
        slot: str,
        *,
        explicit: bool = True,
        reason: str = "manual",
    ) -> bool:
        pair_idx = self._slot_pair_index(slot)
        if pair_idx is not None:
            self._startup_wave_done_pairs[pair_idx] = False
            self._pair_sync_inflight[pair_idx] = False
            await self._silence_pair_output(pair_idx)
        if (not explicit) and self._slot_session_fixed.get(slot, False):
            client = self._clients.get(slot)
            if client and client.is_connected:
                self.log(f"[SESSION] {slot} keep fixed session ({reason})")
                return True
        client = self._clients.get(slot)
        if client:
            try:
                if client.is_connected:
                    self._slot_disconnect_expected[slot] = True
                    await client.disconnect()
            except Exception as exc:
                self.log(f"[WARN] {slot} disconnect error: {exc}")
            finally:
                self._slot_disconnect_expected[slot] = False
                self._clients[slot] = None
        self._set_state(slot, "DISCONNECT")
        self._set_status(slot, "disconnected")
        self._slot_connected_since[slot] = 0.0
        self._slot_unexpected_disconnect_until[slot] = 0.0
        self._slot_output_enabled[slot] = None
        self._slot_auth_state[slot] = "UNKNOWN"
        self._slot_auth_error_latched[slot] = False
        self._slot_pair_tried[slot] = False
        self._slot_auth_recover_tried[slot] = False
        self._slot_rebond_tried[slot] = False
        self._slot_write_pref[slot] = (
            False
            if PREFER_WRITE_COMMAND_WHEN_AVAILABLE
            else bool(config.WRITE_RESPONSE)
        )
        self._slot_write_cap_req[slot] = True
        self._slot_write_cap_cmd[slot] = True
        self._slot_adv_char_uuid[slot] = config.ADV_CHR_UUID
        self._slot_adv_char_missing_latched[slot] = False
        self._slot_session_fixed[slot] = False
        self.slot_widgets[slot]["connect_button"].setEnabled(True)
        self.slot_widgets[slot]["disconnect_button"].setEnabled(False)
        self.log(f"[STATE] {slot} disconnected")
        self._cancel_color_heartbeat(slot)
        self._cancel_pattern_task(slot)
        if pair_idx is not None:
            self._startup_wave_done_pairs[pair_idx] = False
        self._reset_pair_syncro_cheat_state(pair_idx)
        self._apply_pair2_no_connection_guard_ui()
        self._refresh_endurance_visual_slot(slot)
        return True

    def _slot_pair_index(self, slot: str) -> Optional[int]:
        for idx, pair in enumerate(self._pairs):
            if slot in pair:
                return idx
        return None

    def _pair_connected(self, pair_index: int) -> bool:
        slot_a, slot_b = self._pairs[pair_index]
        return (
            self._clients.get(slot_a)
            and self._clients[slot_a].is_connected
            and self._clients.get(slot_b)
            and self._clients[slot_b].is_connected
        )

    async def _maybe_run_startup_wave_for_pair(self, slot: str) -> None:
        pair_idx = self._slot_pair_index(slot)
        if pair_idx is None:
            return
        await self._silence_pair_output(pair_idx)
        if self._endurance_active_cycle is not None:
            return
        if not self._pair_connected(pair_idx):
            return
        if self._pair_sync_inflight.get(pair_idx):
            return
        auto_startup_enabled = bool(
            hasattr(self, "color_auto_startup_check")
            and self.color_auto_startup_check.isChecked()
        )
        has_saved_output = self._pair_has_saved_output(pair_idx)
        if not auto_startup_enabled and not has_saved_output:
            return
        pair_slots = list(self._pairs[pair_idx])
        saved_states = (
            {
                pair_slot: {
                    "front": QColor(self._color_state[pair_slot]["front"]),
                    "rear": QColor(self._color_state[pair_slot]["rear"]),
                    "brightness": int(self._color_state[pair_slot]["brightness"]),
                    "output": bool(self._color_state[pair_slot]["output"]),
                    "mode": str(self._color_state[pair_slot]["mode"]),
                }
                for pair_slot in pair_slots
            }
            if has_saved_output
            else {}
        )
        self._pair_sync_inflight[pair_idx] = True
        try:
            ok = await self._run_startup_wave_slots(
                pair_slots,
                repeat_count=len(self._startup_wave_colors),
                cycle_seconds=max(0.2, self._startup_wave_cycle_ms / 1000.0),
                color_sequence=[QColor(color) for color in self._startup_wave_colors],
            )
            if ok:
                self._startup_wave_done_pairs[pair_idx] = True
                if has_saved_output:
                    for pair_slot, state in saved_states.items():
                        self._color_state[pair_slot] = state
                    await self._restore_color_state_after_connect(slot)
        finally:
            self._pair_sync_inflight[pair_idx] = False

    async def _connect_both(self) -> bool:
        active_pair_indices: list[int] = []
        for idx, (slot_a, slot_b) in enumerate(self._pairs):
            a_name = self._current_name(slot_a)
            b_name = self._current_name(slot_b)
            # Allow incomplete/unused pair rows (common in 2-device operation).
            if not a_name and not b_name:
                self.log(f"[SKIP] {self._pair_labels[idx]}: no devices selected")
                continue
            if not a_name or not b_name:
                self.log(
                    f"[SKIP] {self._pair_labels[idx]}: incomplete selection "
                    f"({slot_a}='{a_name or '-'}', {slot_b}='{b_name or '-'})"
                )
                continue
            ok, reason = self._pair_ok(idx)
            if not ok:
                self._show_error(f"{self._pair_labels[idx]} mismatch: {reason}")
                return False
            active_pair_indices.append(idx)
        if not active_pair_indices:
            self._show_error("No valid pair selected to connect")
            return False
        success = True
        for idx in active_pair_indices:
            for slot in self._pairs[idx]:
                slot_ok = await self._connect_slot(slot)
                success = success and slot_ok
        return success

    async def _connect_pair_only(self, pair_index: int) -> bool:
        if pair_index < 0 or pair_index >= len(self._pairs):
            return False
        slots = list(self._pairs[pair_index])
        self.log(f"[DIAG] isolate connect {self._pair_labels[pair_index]} -> {', '.join(slots)}")
        ok, reason = self._pair_ok(pair_index)
        if not ok:
            self._show_error(f"{self._pair_labels[pair_index]} mismatch: {reason}")
            return False
        if pair_index == 1:
            return await self._connect_pair2_staged(slots)
        return await self._connect_only_slots(slots, staged=True)

    async def _connect_pair2_staged(
        self,
        slots: list[str],
        *,
        settle_s: float = PAIR_CONNECT_SETTLE_S,
    ) -> bool:
        requested = [slot for slot in slots if slot in self._slots]
        if not requested:
            self._show_error("Pair 2 staged connect: no valid slot selected")
            return False
        requested_set = set(requested)
        for slot in self._slots:
            if slot in requested_set:
                continue
            client = self._clients.get(slot)
            if client and client.is_connected:
                await self._disconnect_slot(
                    slot,
                    explicit=False,
                    reason="pair2-staged",
                )
        for index, slot in enumerate(requested):
            stage_ok = await self._connect_slot(slot)
            if not stage_ok:
                self.log(f"[DIAG] Pair 2 staged connect aborted at {slot}")
                return False
            if index < len(requested) - 1:
                self.log(
                    f"[DIAG] Pair 2 stage {slot} OK; settle {settle_s:.1f}s before next"
                )
                await asyncio.sleep(settle_s)
        self.log("[DIAG] Pair 2 staged connect complete")
        return True

    async def _connect_only_slots(
        self,
        slots: list[str],
        *,
        staged: bool = False,
        settle_s: float = PAIR_CONNECT_SETTLE_S,
    ) -> bool:
        requested = [slot for slot in slots if slot in self._slots]
        if not requested:
            self._show_error("No valid slot selected")
            return False
        requested_set = set(requested)
        for slot in self._slots:
            if slot in requested_set:
                continue
            client = self._clients.get(slot)
            if client and client.is_connected:
                await self._disconnect_slot(
                    slot,
                    explicit=False,
                    reason=f"connect-only:{','.join(requested)}",
                )
        success = True
        for index, slot in enumerate(requested):
            slot_ok = await self._connect_slot(slot)
            success = success and slot_ok
            if staged and slot_ok and index < len(requested) - 1:
                self.log(
                    f"[DIAG] staged connect settle {slot} -> next in {settle_s:.1f}s"
                )
                await asyncio.sleep(settle_s)
        return success

    def _clear_profile_missing_latch(self) -> None:
        for slot in self._slots:
            self._slot_profile_blocked[slot] = False
            self._slot_profile_missing_until[slot] = 0.0
            self._slot_unexpected_disconnect_until[slot] = 0.0
        self.log("[DIAG] cleared PROFILE_MISSING and link-drop backoff for all slots")

    async def _disconnect_both(
        self,
        *,
        explicit: bool = True,
        reason: str = "manual",
    ) -> bool:
        success = True
        for slot in self._slots:
            slot_ok = await self._disconnect_slot(
                slot,
                explicit=explicit,
                reason=reason,
            )
            success = success and slot_ok
        return success and self._all_disconnected()

    async def _reconnect_both_test(self) -> None:
        self.log("[TEST] reconnect all")
        await self._disconnect_both()
        self.log("[TEST] power cycle devices then wait for advertising")
        await self._scan_until_found(timeout=60)
        await self._connect_both()

    async def _scan_until_found(self, timeout: int = 30) -> None:
        deadline = datetime.now().timestamp() + timeout
        while datetime.now().timestamp() < deadline:
            await self._scan_devices()
            if all(self._pair_ok(idx)[0] for idx in range(len(self._pairs))):
                return
            await asyncio.sleep(2)
        self.log("[WARN] scan timeout")

    async def _after_both_connected(self) -> bool:
        if not self._all_connected():
            return False
        all_battery_ok = True
        for slot in self._slots:
            battery_ok = await self._read_battery(slot)
            all_battery_ok = all_battery_ok and battery_ok
        self._update_collision_status()
        return all_battery_ok

    async def _gatt_test_all(self) -> None:
        for slot in self._slots:
            client = self._clients.get(slot)
            if not client or not client.is_connected:
                self.log(f"[GATT] {slot} skipped (not connected)")
                continue
            await self._led_test(slot)
            await self._read_battery(slot)

    async def _write_led_command_safe(
        self,
        slot: str,
        payload: list[int],
        *,
        allow_session_recovery: bool = True,
    ) -> bool:
        if not self._guard_slot_execution(slot, f"cmd=0x{payload[0]:02X}" if payload else "cmd"):
            return False
        if self._slot_adv_char_missing_latched.get(slot):
            client = self._clients.get(slot)
            if client and client.is_connected:
                await self._detect_slot_write_caps(slot, client, force_refresh=True)
            if self._slot_adv_char_missing_latched.get(slot):
                return False
        if self._slot_auth_state.get(slot) == "FAILED":
            if not self._slot_auth_error_latched.get(slot):
                self.log(f"[AUTH] {slot} write blocked (auth failed). reconnect/pair required")
                self._slot_auth_error_latched[slot] = True
            return False
        try:
            lock = self._slot_write_locks.get(slot)
            if lock is None:
                await self._write_led_command(
                    slot,
                    payload,
                    allow_session_recovery=allow_session_recovery,
                )
                return True
            async with lock:
                await self._write_led_command(
                    slot,
                    payload,
                    allow_session_recovery=allow_session_recovery,
                )
                return True
        except Exception:
            return False

    async def _write_led_command_live(self, slot: str, payload: list[int]) -> bool:
        return await self._write_led_command_safe(
            slot,
            payload,
            allow_session_recovery=False,
        )

    async def _run_startup_wave_all(
        self, repeat_count: int = 5, cycle_seconds: float = 1.0
    ) -> bool:
        slots = [
            slot
            for slot in self._slots
            if self._clients.get(slot) and self._clients[slot].is_connected
        ]
        return await self._run_startup_wave_slots(
            slots, repeat_count=repeat_count, cycle_seconds=cycle_seconds
        )

    async def _run_startup_wave_slots(
        self,
        slots: list[str],
        repeat_count: int = 5,
        cycle_seconds: float = 1.0,
        color: Optional[QColor] = None,
        brightness: Optional[int] = None,
        color_sequence: Optional[list[QColor]] = None,
    ) -> bool:
        if not slots:
            return False
        if color_sequence is not None:
            colors = [QColor(item) for item in color_sequence]
        elif color is not None:
            colors = [QColor(color)]
        else:
            colors = [QColor(item) for item in self._startup_wave_colors]
        colors = [item for item in colors if item.isValid()]
        if not colors:
            colors = [QColor(self._color_selected)]
        wave_count = max(1, min(int(repeat_count), len(colors)))
        active_colors = colors[:wave_count]
        self._record_sequence(
            f"STARTUP_WAVE_BEGIN count={len(active_colors)} cycle={cycle_seconds:.1f}s",
            "TOOL",
        )
        brightness_value = (
            int(brightness) if brightness is not None else int(self._color_value)
        )
        brightness = max(1, min(255, brightness_value))
        interval_ms = max(20, int((cycle_seconds * 1000.0) / 16.0))
        total_duration_s = max(0.2, (interval_ms * 16) / 1000.0)
        pattern_off_payload = [CMD_PATTERN_MODE, 0x00]

        for slot in slots:
            self._cancel_pattern_task(slot)
            self._cancel_color_heartbeat(slot)

        prep_results = await asyncio.gather(
            *[
                self._write_led_command_safe(slot, [CMD_SET_OUTPUT_ENABLE, 0x01])
                for slot in slots
            ],
            *[
                self._write_led_command_safe(slot, [CMD_SET_BRIGHTNESS, brightness])
                for slot in slots
            ],
            *[
                self._write_led_command_safe(slot, [CMD_STOP_RAINBOW])
                for slot in slots
            ],
            *[
                self._write_led_command_safe(slot, pattern_off_payload)
                for slot in slots
            ],
        )
        all_ok = all(prep_results) if prep_results else True

        for idx, wave_color in enumerate(active_colors):
            pattern_payload = [
                CMD_PATTERN_MODE,
                0x01,
                0x03,
                0x03,
                wave_color.red(),
                wave_color.green(),
                wave_color.blue(),
                interval_ms & 0xFF,
                (interval_ms >> 8) & 0xFF,
            ]
            self._record_sequence(
                (
                    "STARTUP_WAVE_PATTERN "
                    f"{idx + 1}/{len(active_colors)} color={wave_color.name()} "
                    f"interval_ms={interval_ms}"
                ),
                "TOOL",
            )
            pattern_results = await asyncio.gather(
                *[self._write_led_command_safe(slot, pattern_payload) for slot in slots]
            )
            all_ok = all_ok and all(pattern_results)
            await asyncio.sleep(total_duration_s)

            stop_results = await asyncio.gather(
                *[self._write_led_command_safe(slot, pattern_off_payload) for slot in slots]
            )
            all_ok = all_ok and all(stop_results)

        final_color = active_colors[-1]
        on_results = await asyncio.gather(
            *[
                self._write_led_command_safe(
                    slot,
                    [
                        CMD_SET_FRONT_COLOR,
                        final_color.red(),
                        final_color.green(),
                        final_color.blue(),
                    ],
                )
                for slot in slots
            ],
            *[
                self._write_led_command_safe(
                    slot,
                    [
                        CMD_SET_REAR_COLOR,
                        final_color.red(),
                        final_color.green(),
                        final_color.blue(),
                    ],
                )
                for slot in slots
            ],
        )
        all_ok = all_ok and all(on_results)
        self._refresh_color_tab(sync_picker=False)
        self._record_sequence(
            f"STARTUP_LED_ON color={final_color.name()} colors={len(active_colors)}",
            "TOOL",
        )
        return all_ok

    async def _led_test(self, slot: str) -> None:
        client = self._clients.get(slot)
        if not client or not client.is_connected:
            return
        self.log(f"[GATT] {slot} LED test start")
        try:
            await self._write_led_command(slot, [CMD_SET_OUTPUT_ENABLE, 0x01])
            await self._write_led_command(slot, [CMD_SET_BRIGHTNESS, 200])
            await self._write_led_command(
                slot, [CMD_SET_FRONT_COLOR, 255, 0, 0]
            )
            await self._write_led_command(
                slot, [CMD_SET_REAR_COLOR, 0, 0, 255]
            )
            await asyncio.sleep(0.2)
            await self._write_led_command(
                slot, [CMD_SET_FRONT_COLOR, 255, 255, 255]
            )
            await self._write_led_command(
                slot, [CMD_SET_REAR_COLOR, 255, 255, 255]
            )
            await asyncio.sleep(0.2)
        except Exception as exc:
            self.log(f"[WARN] {slot} LED test failed: {exc}")
            return
        self._record_sequence("LED_TEST", slot)
        self.log(f"[GATT] {slot} LED test done")

    def _is_auth_error(self, exc: Exception) -> bool:
        text = str(exc).lower()
        return (
            "insufficient authentication" in text
            or "protocol error 0x05" in text
            or "authentication" in text
        )

    def _is_char_missing_error(self, exc: Exception) -> bool:
        text = str(exc).lower()
        return "characteristic" in text and "not found" in text

    async def _try_pair_slot(
        self,
        slot: str,
        client: BleakClient,
        reason: str = "write_auth",
        force: bool = False,
    ) -> bool:
        if (not force) and self._slot_pair_tried.get(slot):
            return self._slot_auth_state.get(slot) == "OK"
        self._slot_pair_tried[slot] = True
        pair_fn = getattr(client, "pair", None)
        if not callable(pair_fn):
            self.log(
                f"[AUTH] {slot} pair() not supported on this platform/backend ({reason})"
            )
            self._record_sequence("PAIR_UNSUPPORTED", slot)
            return False
        # Try less strict first, then stricter levels. Some stacks reject strict
        # level requests but still allow encrypted bonding with default call.
        pair_attempts = [
            {},
            {"protection_level": 1},
            {"protection_level": 2},
            {"protection_level": "encryptionAndAuthentication"},
        ]
        attempted = False
        for kwargs in pair_attempts:
            try:
                result = await pair_fn(**kwargs)
                attempted = True
                self.log(
                    f"[AUTH] {slot} pair requested ({reason}) kwargs={kwargs} result={result}"
                )
                # pair() return type differs by backend. We never treat None as
                # confirmed success; write retry will verify real auth state.
                if result is True:
                    self._record_sequence("PAIR_REQ", slot)
                    return True
                if result is False:
                    continue
                await asyncio.sleep(0.2)
            except TypeError:
                continue
            except Exception as pair_exc:
                self.log(
                    f"[AUTH] {slot} pair failed ({reason}) kwargs={kwargs}: {pair_exc}"
                )
        if attempted:
            self._record_sequence("PAIR_REQ_PENDING", slot)
            return True
        self._record_sequence("PAIR_FAIL", slot)
        self._slot_auth_state[slot] = "FAILED"
        return False

    async def _recover_auth_by_reconnect(self, slot: str) -> bool:
        """One-shot auth recovery for Windows backend:
        reconnect with pair=True and retry pending write once.
        """
        name = self._current_name(slot)
        if not name:
            self.log(f"[AUTH] {slot} recover skipped: no selected name")
            return False
        address = self._device_map.get(name)
        if not address:
            self.log(f"[AUTH] {slot} recover skipped: '{name}' not in scan map")
            return False

        old_client = self._clients.get(slot)
        if old_client and old_client.is_connected:
            try:
                self._slot_disconnect_expected[slot] = True
                await old_client.disconnect()
            except Exception:
                pass
            finally:
                self._slot_disconnect_expected[slot] = False

        client = BleakClient(
            address,
            timeout=config.CONNECT_TIMEOUT,
            pair=True,
            **self._bleak_client_kwargs(),
        )
        try:
            await client.connect()
        except Exception as exc:
            self.log(f"[AUTH] {slot} recover reconnect failed: {exc}")
            self._clients[slot] = None
            self._set_status(slot, "connect failed")
            self._set_state(slot, "DISCONNECT")
            return False

        self._clients[slot] = client
        self._set_status(slot, "connected")
        self._set_state(slot, "CONNECT")
        self._slot_auth_state[slot] = "UNKNOWN"
        self._slot_pair_tried[slot] = False
        self._slot_auth_error_latched[slot] = False
        self._slot_rebond_tried[slot] = False
        self._slot_write_pref[slot] = (
            False
            if PREFER_WRITE_COMMAND_WHEN_AVAILABLE
            else bool(config.WRITE_RESPONSE)
        )
        self._slot_write_cap_req[slot] = True
        self._slot_write_cap_cmd[slot] = True
        self._slot_adv_char_uuid[slot] = config.ADV_CHR_UUID
        self._slot_adv_char_missing_latched[slot] = False
        if not await self._ensure_slot_adv_profile(slot, client, context="auth_recover"):
            return False
        self._slot_profile_missing_until[slot] = 0.0
        self._slot_profile_blocked[slot] = False
        self.log(f"[AUTH] {slot} recover reconnect OK")
        return True

    async def _recover_auth_by_rebond(self, slot: str) -> bool:
        """Stronger auth recovery:
        unpair (if backend supports it), reconnect, and pair again.
        """
        if self._slot_rebond_tried.get(slot):
            return False
        self._slot_rebond_tried[slot] = True

        name = self._current_name(slot)
        if not name:
            self.log(f"[AUTH] {slot} rebond skipped: no selected name")
            return False
        address = self._device_map.get(name)
        if not address:
            self.log(f"[AUTH] {slot} rebond skipped: '{name}' not in scan map")
            return False

        old_client = self._clients.get(slot)
        if old_client:
            unpair_fn = getattr(old_client, "unpair", None)
            if callable(unpair_fn):
                try:
                    await unpair_fn()
                    self.log(f"[AUTH] {slot} unpair requested")
                    await asyncio.sleep(AUTH_PAIR_RETRY_DELAY_S)
                except Exception as exc:
                    self.log(f"[AUTH] {slot} unpair failed: {exc}")
            if old_client.is_connected:
                try:
                    self._slot_disconnect_expected[slot] = True
                    await old_client.disconnect()
                except Exception:
                    pass
                finally:
                    self._slot_disconnect_expected[slot] = False

        client = BleakClient(
            address,
            timeout=config.CONNECT_TIMEOUT,
            pair=True,
            **self._bleak_client_kwargs(),
        )
        try:
            await client.connect()
        except Exception as exc:
            self.log(f"[AUTH] {slot} rebond reconnect failed: {exc}")
            self._clients[slot] = None
            self._set_status(slot, "connect failed")
            self._set_state(slot, "DISCONNECT")
            return False

        self._clients[slot] = client
        self._set_status(slot, "connected")
        self._set_state(slot, "CONNECT")
        self._slot_auth_state[slot] = "UNKNOWN"
        self._slot_pair_tried[slot] = False
        self._slot_auth_error_latched[slot] = False
        self._slot_write_pref[slot] = bool(config.WRITE_RESPONSE)
        self._slot_write_cap_req[slot] = True
        self._slot_write_cap_cmd[slot] = True
        self._slot_adv_char_uuid[slot] = config.ADV_CHR_UUID
        self._slot_adv_char_missing_latched[slot] = False
        if not await self._ensure_slot_adv_profile(slot, client, context="rebond"):
            return False
        self._slot_profile_missing_until[slot] = 0.0
        self._slot_profile_blocked[slot] = False
        await self._try_pair_slot(slot, client, reason="rebond", force=True)
        await asyncio.sleep(AUTH_PAIR_RETRY_DELAY_S)
        self.log(f"[AUTH] {slot} rebond reconnect OK")
        return True

    async def _get_client_services(
        self, client: BleakClient, force_refresh: bool = False
    ) -> tuple[Optional[object], Optional[Exception]]:
        """Compatibility wrapper for bleak service discovery across versions."""
        cached = getattr(client, "services", None)
        if cached and not force_refresh:
            return cached, None

        get_services = getattr(client, "get_services", None)
        if callable(get_services):
            try:
                return await get_services(), None
            except Exception as exc:
                return None, exc

        backend = getattr(client, "_backend", None)
        backend_get = getattr(backend, "get_services", None) if backend else None
        if callable(backend_get):
            try:
                return await backend_get(), None
            except Exception as exc:
                return None, exc

        if cached:
            return cached, None

        backend_cached = getattr(backend, "services", None) if backend else None
        if backend_cached:
            return backend_cached, None

        return None, AttributeError(
            "service discovery API not available in this bleak backend"
        )

    async def _detect_slot_write_caps(
        self, slot: str, client: BleakClient, force_refresh: bool = False
    ) -> None:
        services = None
        last_exc: Optional[Exception] = None
        for attempt in range(6):
            refresh = force_refresh or attempt > 0
            services, exc = await self._get_client_services(client, force_refresh=refresh)
            if exc is not None:
                last_exc = exc
            if services:
                break
            await asyncio.sleep(0.20)

        if not services:
            if last_exc is not None:
                self.log(f"[GATT] {slot} service discovery failed: {type(last_exc).__name__}: {last_exc}")
            self._slot_adv_char_missing_latched[slot] = True
            return

        target = config.ADV_CHR_UUID.lower()
        target_svc = config.ADV_SVC_UUID.lower()
        char_obj = None

        get_char = getattr(services, "get_characteristic", None)
        if callable(get_char):
            try:
                char_obj = get_char(config.ADV_CHR_UUID)
            except Exception:
                char_obj = None

        if char_obj is None:
            try:
                for svc in services:
                    for ch in getattr(svc, "characteristics", []):
                        if str(getattr(ch, "uuid", "")).lower() == target:
                            char_obj = ch
                            break
                    if char_obj is not None:
                        break
            except Exception:
                char_obj = None

        if char_obj is None:
            # Fallback: pick first writable characteristic from target service.
            try:
                for svc in services:
                    svc_uuid = str(getattr(svc, "uuid", "")).lower()
                    if svc_uuid != target_svc:
                        continue
                    writable = []
                    for ch in getattr(svc, "characteristics", []):
                        props = {str(p).lower() for p in getattr(ch, "properties", [])}
                        if "write" in props or "write-without-response" in props:
                            writable.append(ch)
                    if writable:
                        char_obj = writable[0]
                        break
            except Exception:
                char_obj = None

        if char_obj is None:
            if not self._slot_adv_char_missing_latched.get(slot):
                try:
                    svc_uuids = [str(getattr(svc, "uuid", "")) for svc in services]
                    svc_preview = ", ".join(svc_uuids[:8])
                    base_only = all(
                        u.lower()
                        in (
                            "00001800-0000-1000-8000-00805f9b34fb",
                            "00001801-0000-1000-8000-00805f9b34fb",
                        )
                        for u in svc_uuids
                        if u
                    )
                except Exception:
                    svc_preview = "?"
                    base_only = False
                self.log(
                    f"[GATT] {slot} adv characteristic not found: {config.ADV_CHR_UUID} "
                    f"(services: {svc_preview})"
                )
                if base_only:
                    self.log(
                        f"[GATT] {slot} base services only (1800/1801). "
                        "Possible causes: wrong firmware, early reconnect race, or auth-gated profile."
                    )
            self._slot_adv_char_missing_latched[slot] = True
            return

        resolved_uuid = str(getattr(char_obj, "uuid", config.ADV_CHR_UUID))
        self._slot_adv_char_uuid[slot] = resolved_uuid
        self._slot_adv_char_missing_latched[slot] = False

        props = {str(p).lower() for p in getattr(char_obj, "properties", [])}
        can_req = "write" in props
        can_cmd = "write-without-response" in props
        if not can_req and not can_cmd:
            self.log(f"[GATT] {slot} write properties unknown: {sorted(props)}")
            return

        self._slot_write_cap_req[slot] = can_req
        self._slot_write_cap_cmd[slot] = can_cmd
        if can_req and not can_cmd:
            self._slot_write_pref[slot] = True
        elif can_cmd and not can_req:
            self._slot_write_pref[slot] = False
        else:
            self._slot_write_pref[slot] = (
                False
                if PREFER_WRITE_COMMAND_WHEN_AVAILABLE
                else bool(config.WRITE_RESPONSE)
            )
        mode = "request" if self._slot_write_pref[slot] else "command"
        self.log(
            f"[GATT] {slot} write caps req={can_req} cmd={can_cmd} pref={mode} "
            f"uuid={resolved_uuid}"
        )

    async def _write_gatt_adv(
        self, client: BleakClient, slot: str, payload: list[int]
    ) -> None:
        response_mode = bool(self._slot_write_pref.get(slot, bool(config.WRITE_RESPONSE)))
        slot_uuid = self._slot_adv_char_uuid.get(slot, config.ADV_CHR_UUID)
        try:
            await client.write_gatt_char(
                slot_uuid,
                bytearray(payload),
                response=response_mode,
            )
            return
        except Exception as exc:
            text = str(exc).lower()
            if "characteristic" in text and "not found" in text:
                self._slot_adv_char_missing_latched[slot] = True
                self.log(f"[GATT] {slot} missing char on write ({slot_uuid}), refreshing")
                await self._detect_slot_write_caps(slot, client, force_refresh=True)
                if not self._slot_adv_char_missing_latched.get(slot):
                    retry_uuid = self._slot_adv_char_uuid.get(slot, slot_uuid)
                    await client.write_gatt_char(
                        retry_uuid,
                        bytearray(payload),
                        response=response_mode,
                    )
                    return
            raise

    async def _write_led_command(
        self,
        slot: str,
        payload: list[int],
        *,
        allow_session_recovery: bool = True,
    ) -> None:
        client = self._clients.get(slot)
        if not client or not client.is_connected:
            raise BleakError(f"{slot} not connected")
        if self._slot_auth_state.get(slot) == "FAILED":
            raise BleakError(f"{slot} auth not established (pair required)")
        if payload and payload[0] == CMD_SET_OUTPUT_ENABLE and len(payload) >= 2:
            self._slot_output_enabled[slot] = payload[1] != 0
            self._refresh_endurance_visual_slot(slot)
            if slot in self._color_state:
                self._color_state[slot]["output"] = payload[1] != 0
                self._refresh_color_tab(sync_picker=False)
        if payload and payload[0] == CMD_SET_BRIGHTNESS and len(payload) >= 2:
            if slot in self._color_state:
                self._color_state[slot]["brightness"] = int(payload[1])
                self._refresh_color_tab(sync_picker=False)

        auth_error: Optional[Exception] = None
        for auth_stage in range(4):
            try:
                await self._write_gatt_adv(client, slot, payload)
                if self._slot_auth_state.get(slot) != "OK":
                    self._slot_auth_state[slot] = "OK"
                    self._slot_auth_error_latched[slot] = False
                return
            except Exception as exc:
                if not self._is_auth_error(exc):
                    if self._is_char_missing_error(exc):
                        if not self._slot_adv_char_missing_latched.get(slot):
                            self.log(
                                f"[GATT] {slot} write blocked: command characteristic missing"
                            )
                        self._slot_adv_char_missing_latched[slot] = True
                    else:
                        self.log(f"[WARN] {slot} write {payload} failed: {exc}")
                    raise
                auth_error = exc

                if (
                    ALLOW_WRITE_COMMAND_FALLBACK_ON_AUTH_ERROR
                    and self._slot_write_cap_cmd.get(slot, False)
                ):
                    try:
                        self.log(f"[AUTH] {slot} fallback to write-without-response")
                        self._slot_write_pref[slot] = False
                        await self._write_gatt_adv(client, slot, payload)
                        self.log(f"[AUTH] {slot} fallback write OK {payload}")
                        # Do not mark auth OK here; command write can be accepted
                        # by stack while peripheral still rejects secured command.
                        self._slot_auth_state[slot] = "UNKNOWN"
                        self._slot_auth_error_latched[slot] = False
                        self.log(
                            f"[AUTH] {slot} running in command-fallback mode"
                        )
                        return
                    except Exception as fallback_exc:
                        self.log(f"[AUTH] {slot} fallback write failed: {fallback_exc}")
                    finally:
                        self._slot_write_pref[slot] = bool(config.WRITE_RESPONSE)

                if auth_stage == 0:
                    if not allow_session_recovery:
                        self.log(f"[AUTH] {slot} live write blocked (no recovery)")
                        break
                    self.log(f"[AUTH] {slot} auth required, trying pair + retry")
                    paired = await self._try_pair_slot(
                        slot, client, reason="write_auth", force=False
                    )
                    if paired:
                        await asyncio.sleep(AUTH_PAIR_RETRY_DELAY_S)
                        if self._slot_write_cap_req.get(slot, True):
                            self._slot_write_pref[slot] = True
                        continue
                    self.log(f"[AUTH] {slot} pair unavailable/failed, write blocked")
                    break

                if (
                    allow_session_recovery
                    and
                    AUTH_ENABLE_RECOVER_RECONNECT
                    and auth_stage == 1
                    and not self._slot_auth_recover_tried.get(slot)
                ):
                    self._slot_auth_recover_tried[slot] = True
                    self.log(f"[AUTH] {slot} trying recover reconnect")
                    recovered = await self._recover_auth_by_reconnect(slot)
                    if recovered:
                        client = self._clients.get(slot)
                        if client and client.is_connected:
                            await asyncio.sleep(AUTH_PAIR_RETRY_DELAY_S)
                            if self._slot_write_cap_req.get(slot, True):
                                self._slot_write_pref[slot] = True
                            continue

                if allow_session_recovery and AUTH_ENABLE_REBOND and auth_stage == 2:
                    self.log(f"[AUTH] {slot} trying full rebond")
                    rebonded = await self._recover_auth_by_rebond(slot)
                    if rebonded:
                        client = self._clients.get(slot)
                        if client and client.is_connected:
                            if self._slot_write_cap_req.get(slot, True):
                                self._slot_write_pref[slot] = True
                            continue
                break

        self._slot_auth_state[slot] = "FAILED"
        if not self._slot_auth_error_latched.get(slot):
            self.log(
                f"[AUTH] {slot} still unauthorized, reconnect and pair from OS settings"
            )
            self.log(
                f"[AUTH] {slot} hint: Windows Settings -> Bluetooth -> remove device -> pair again"
            )
            self._slot_auth_error_latched[slot] = True
        if auth_error is not None:
            raise auth_error

    async def _read_battery(self, slot: str) -> bool:
        client = self._clients.get(slot)
        if not client or not client.is_connected:
            return False
        try:
            raw = await client.read_gatt_char(config.VOLTAGE_CHR_UUID)
        except Exception as exc:
            self.log(f"[WARN] {slot} battery read failed: {exc}")
            return False
        voltage = self._parse_voltage(raw)
        if voltage is None:
            self.log(f"[WARN] {slot} battery parse failed: {raw.hex()}")
            return False
        self._set_state(slot, "GATT")
        self._set_battery(slot, voltage)
        self._record_sequence("BATTERY_READ", slot)
        self.log(f"[GATT] {slot} battery {voltage:.2f} V")
        return True

    # --------------------------- Helpers ---------------------------
    def _update_device_combo(self, slot: str) -> None:
        combo = self.slot_widgets[slot]["combo"]
        current = combo.currentText()
        combo.blockSignals(True)
        combo.clear()
        items: list[str] = []
        for name in sorted(self._device_map.keys(), key=self._device_sort_key):
            if not self._name_matches_slot(slot, name):
                continue
            items.append(name)
        desired = self._desired_slot_names.get(slot, "")
        if desired and desired not in items and self._name_matches_slot(slot, desired):
            items.insert(0, desired)
        if items:
            combo.addItems(items)
        if desired:
            idx = combo.findText(desired)
            if idx >= 0:
                combo.setCurrentIndex(idx)
        elif current:
            idx = combo.findText(current)
            if idx >= 0:
                combo.setCurrentIndex(idx)
        desired = self._desired_slot_names.get(slot, "")
        if desired:
            idx = combo.findText(desired)
            if idx >= 0:
                combo.setCurrentIndex(idx)
        combo.blockSignals(False)
        self._refresh_endurance_visual_slot(slot)

    def _apply_desired_names_to_combos(self) -> None:
        if not hasattr(self, "slot_widgets"):
            return
        for slot in self._slots:
            combo = self.slot_widgets[slot]["combo"]
            desired = self._desired_slot_names.get(slot, "")
            if not desired:
                continue
            idx = combo.findText(desired)
            if idx < 0 and self._name_matches_slot(slot, desired):
                combo.insertItem(0, desired)
                idx = combo.findText(desired)
            if idx >= 0:
                combo.setCurrentIndex(idx)
        self._update_collision_status()
        self._refresh_endurance_visual_all()

    def _name_matches_slot(self, slot: str, name: str) -> bool:
        number = self._extract_number(name)
        if number is None:
            return False
        is_a = slot.startswith("A")
        if is_a and number % 2 == 0:
            return False
        if not is_a and number % 2 != 0:
            return False
        return True

    def _update_flash_names(self) -> None:
        base_name = self._read_device_name() or "XIAO-ESP32C3-LED-STOCK2"
        for idx, pair in enumerate(self.pairs):
            n_value = self._parse_n(pair["n_edit"].text())
            slot_a, slot_b = self._pairs[idx]
            if n_value is None:
                pair["a_label"].setText("A: --")
                pair["b_label"].setText("B: --")
                self._desired_slot_names[slot_a] = ""
                self._desired_slot_names[slot_b] = ""
                continue
            a_num = 2 * n_value - 1
            b_num = 2 * n_value
            a_name = self._make_device_name(base_name, a_num)
            b_name = self._make_device_name(base_name, b_num)
            pair["a_label"].setText(f"A: {a_name}")
            pair["b_label"].setText(f"B: {b_name}")
            self._desired_slot_names[slot_a] = a_name
            self._desired_slot_names[slot_b] = b_name
        self._apply_desired_names_to_combos()

    def _parse_n(self, text: str) -> Optional[int]:
        try:
            value = int(text.strip())
        except ValueError:
            return None
        if value <= 0:
            return None
        return value

    def _auto_detect_ports(self) -> None:
        ports = self._list_ports()
        if not ports:
            self._refresh_all_com_ports()
            self.log("[COM] Auto Detect: no COM ports found")
            return
        port_iter = iter(ports)
        for pair in self.pairs:
            for key in ("a_port", "b_port"):
                combo: QComboBox = pair[key]
                current = combo.currentText()
                self._fill_port_combo(combo, ports, current)
                try:
                    combo.setCurrentText(next(port_iter))
                except StopIteration:
                    combo.setCurrentText(ports[0])
        self._sync_control_ports(ports)
        self._refresh_monitor_ports()
        self._apply_pair2_no_connection_guard_ui()
        self.log(f"[COM] Auto Detect assigned: {', '.join(ports)}")

    async def _detect_ble_devices(self) -> None:
        self.log(
            f"[SCAN] timeout={config.SCAN_TIMEOUT}s, looking for name contains: "
            f"{config.TARGET_NAME!r}"
        )
        try:
            devices = await BleakScanner.discover(timeout=config.SCAN_TIMEOUT)
        except Exception as exc:
            self.log(f"[ERROR] Scan failed: {exc}")
            return
        found_names = set()
        for device in devices:
            name = device.name or ""
            self.log(f"- {device.address}  {name}")
            if name:
                found_names.add(name)

        base_name = self._read_device_name() or "XIAO-ESP32C3-LED-STOCK2"
        for pair in self.pairs:
            n_value = self._parse_n(pair["n_edit"].text())
            if n_value is None:
                self._set_label_style(pair["a_status"], "#444444", "#ffffff")
                self._set_label_style(pair["b_status"], "#444444", "#ffffff")
                pair["a_status"].setText("NG")
                pair["b_status"].setText("NG")
                continue
            a_name = self._make_device_name(base_name, 2 * n_value - 1)
            b_name = self._make_device_name(base_name, 2 * n_value)
            if a_name in found_names:
                pair["a_status"].setText("OK")
                self._set_label_style(pair["a_status"], "#2e7d32", "#ffffff")
            else:
                pair["a_status"].setText("NG")
                self._set_label_style(pair["a_status"], "#d32f2f", "#ffffff")
            if b_name in found_names:
                pair["b_status"].setText("OK")
                self._set_label_style(pair["b_status"], "#2e7d32", "#ffffff")
            else:
                pair["b_status"].setText("NG")
                self._set_label_style(pair["b_status"], "#d32f2f", "#ffffff")

    def _sync_control_ports(self, ports: list[str]) -> None:
        if not hasattr(self, "slot_widgets"):
            return
        for idx, pair in enumerate(self.pairs):
            slot_a, slot_b = self._pairs[idx]
            a_port = pair["a_port"].currentText()
            b_port = pair["b_port"].currentText()
            self._fill_port_combo(self.slot_widgets[slot_a]["port_combo"], ports, a_port)
            self._fill_port_combo(self.slot_widgets[slot_b]["port_combo"], ports, b_port)

    def _refresh_all_com_ports(self) -> None:
        ports = self._list_ports()
        for pair in self.pairs:
            a_current = pair["a_port"].currentText()
            b_current = pair["b_port"].currentText()
            self._fill_port_combo(pair["a_port"], ports, a_current)
            self._fill_port_combo(pair["b_port"], ports, b_current)
        self._sync_control_ports(ports)
        if hasattr(self, "serial_port_combo"):
            serial_current = self.serial_port_combo.currentText()
            self._fill_port_combo(self.serial_port_combo, ports, serial_current)
        if hasattr(self, "serial_color_port_combo"):
            serial_color_current = self.serial_color_port_combo.currentText()
            self._fill_port_combo(
                self.serial_color_port_combo, ports, serial_color_current
            )
        self._apply_pair2_no_connection_guard_ui()
        if ports:
            self.log(f"[COM] refreshed all tabs: {', '.join(ports)}")
        else:
            self.log("[COM] refreshed all tabs: - (no ports)")

    def _is_unconnected_port(self, port: str) -> bool:
        value = (port or "").strip()
        if not value:
            return True
        if value == COM_PORT_NONE:
            return True
        return value.upper() == "N/A"

    def _fill_port_combo(self, combo: QComboBox, ports: list[str], current: str) -> None:
        combo.blockSignals(True)
        combo.clear()
        combo.addItem(COM_PORT_NONE)
        seen = {COM_PORT_NONE}
        for port in ports:
            port_text = (port or "").strip()
            if self._is_unconnected_port(port_text) or port_text in seen:
                continue
            combo.addItem(port_text)
            seen.add(port_text)
        current_text = (current or "").strip()
        if current_text.upper() == "N/A":
            current_text = COM_PORT_NONE
        if current_text in seen:
            combo.setCurrentText(current_text)
        else:
            combo.setCurrentText(COM_PORT_NONE)
        combo.blockSignals(False)

    def _set_flash_status(self, text: str, bg: str, fg: str = "#ffffff") -> None:
        self.flash_status.setText(text)
        self._set_label_style(self.flash_status, bg, fg)

    def _set_flash_slot_status(self, slot: str, text: str, bg: str) -> None:
        label = self.flash_slot_labels.get(slot)
        if not label:
            return
        label.setText(f"{slot}: {text}")
        self._set_label_style(label, bg, "#ffffff")

    def _reset_flash_slot_statuses(self) -> None:
        for slot in self._slots:
            self._set_flash_slot_status(slot, "IDLE", "#444444")

    async def _auto_build(self) -> None:
        if not self._ensure_flash_settings():
            return
        self._set_flash_buttons(False)
        self._set_flash_status("BUILDING", "#f9a825")
        self._reset_flash_slot_statuses()
        sketch_path = self._resolve_sketch_file()
        if sketch_path is None:
            self._set_flash_status("BUILD NG", "#d32f2f")
            self._set_flash_buttons(True)
            return
        original = sketch_path.read_text(encoding="utf-8")
        success = True
        try:
            for pair in self.pairs:
                n_value = self._parse_n(pair["n_edit"].text())
                if n_value is None:
                    continue
                success &= await self._build_for_number(
                    sketch_path, 2 * n_value - 1
                )
                success &= await self._build_for_number(sketch_path, 2 * n_value)
        finally:
            sketch_path.write_text(original, encoding="utf-8")
            self._set_flash_buttons(True)
            if success:
                self._set_flash_status("BUILD OK", "#2e7d32")
            else:
                self._set_flash_status("BUILD NG", "#d32f2f")

    async def _auto_flash(self) -> None:
        if not self._ensure_flash_settings():
            return
        self._set_flash_buttons(False)
        self._set_flash_status("FLASHING", "#f9a825")
        self._reset_flash_slot_statuses()
        sketch_path = self._resolve_sketch_file()
        if sketch_path is None:
            self._set_flash_status("FLASH NG", "#d32f2f")
            self._set_flash_buttons(True)
            return
        original = sketch_path.read_text(encoding="utf-8")
        success = True
        try:
            for idx, pair in enumerate(self.pairs):
                n_value = self._parse_n(pair["n_edit"].text())
                if n_value is None:
                    continue
                slot_a, slot_b = self._pairs[idx]
                a_port = pair["a_port"].currentText()
                b_port = pair["b_port"].currentText()
                if not self._is_unconnected_port(a_port):
                    success &= await self._flash_for_number(
                        sketch_path, 2 * n_value - 1, a_port, slot_a
                    )
                else:
                    self.log(f"[FLASH] skip A (N={n_value}) no COM")
                    self._set_flash_slot_status(slot_a, "NG", "#d32f2f")
                    success = False
                if not self._is_unconnected_port(b_port):
                    success &= await self._flash_for_number(
                        sketch_path, 2 * n_value, b_port, slot_b
                    )
                else:
                    self.log(f"[FLASH] skip B (N={n_value}) no COM")
                    self._set_flash_slot_status(slot_b, "NG", "#d32f2f")
                    success = False
        finally:
            sketch_path.write_text(original, encoding="utf-8")
            self._set_flash_buttons(True)
            if success:
                self._set_flash_status("FLASH OK", "#2e7d32")
            else:
                self._set_flash_status("FLASH NG", "#d32f2f")

    def _set_flash_buttons(self, enabled: bool) -> None:
        self.detect_ports_button.setEnabled(enabled)
        if hasattr(self, "refresh_all_com_button"):
            self.refresh_all_com_button.setEnabled(enabled)
        self.detect_ble_button.setEnabled(enabled)
        self.auto_build_button.setEnabled(enabled)
        self.auto_flash_button.setEnabled(enabled)

    def _ensure_flash_settings(self) -> bool:
        cli_path = Path(self.cli_path_edit.text().strip())
        sketch_dir = Path(self.sketch_edit.text().strip())
        fqbn = self.fqbn_edit.text().strip()
        if not cli_path.exists():
            self._show_error("arduino-cli not found")
            return False
        if not sketch_dir.exists():
            self._show_error("Sketch folder not found")
            return False
        if not fqbn:
            self._show_error("FQBN is empty")
            return False
        return True

    def _resolve_sketch_file(self) -> Optional[Path]:
        sketch_dir = Path(self.sketch_edit.text().strip())
        if not sketch_dir.exists():
            self._show_error("Sketch folder not found")
            return None
        candidate = sketch_dir / f"{sketch_dir.name}.ino"
        if candidate.exists():
            return candidate
        ino_files = list(sketch_dir.glob("*.ino"))
        if not ino_files:
            self._show_error("No .ino file found")
            return None
        return ino_files[0]

    def _read_device_name(self) -> Optional[str]:
        sketch_path = self._resolve_sketch_file()
        if sketch_path is None:
            return None
        content = sketch_path.read_text(encoding="utf-8")
        match = re.search(r'#define\s+DEVICE_NAME\s+"([^"]+)"', content)
        if not match:
            return None
        return match.group(1)

    def _make_device_name(self, base_name: str, number: int) -> str:
        match = re.search(r"(.*?)(\d+)$", base_name)
        if match:
            return f"{match.group(1)}{number}"
        return f"{base_name}{number}"

    def _write_device_name(self, sketch_path: Path, new_name: str) -> None:
        content = sketch_path.read_text(encoding="utf-8")
        new_content, count = re.subn(
            r'(#define\s+DEVICE_NAME\s+")([^"]+)(")',
            rf'\1{new_name}\3',
            content,
            count=1,
        )
        if count == 0:
            self._show_error("DEVICE_NAME not found in sketch")
            return
        sketch_path.write_text(new_content, encoding="utf-8")
        self.log(f"[NAME] {new_name}")

    async def _build_for_number(self, sketch_path: Path, number: int) -> bool:
        base_name = self._read_device_name() or "XIAO-ESP32C3-LED-STOCK2"
        new_name = self._make_device_name(base_name, number)
        self._write_device_name(sketch_path, new_name)
        return await self._run_cli_command(
            [
                "compile",
                "--fqbn",
                self.fqbn_edit.text().strip(),
                str(sketch_path.parent),
            ]
        )

    async def _flash_for_number(
        self, sketch_path: Path, number: int, port: str, slot: str
    ) -> bool:
        base_name = self._read_device_name() or "XIAO-ESP32C3-LED-STOCK2"
        new_name = self._make_device_name(base_name, number)
        self._write_device_name(sketch_path, new_name)
        self._set_flash_slot_status(slot, "FLASHING", "#f9a825")
        ok = await self._run_cli_command(
            [
                "compile",
                "--fqbn",
                self.fqbn_edit.text().strip(),
                str(sketch_path.parent),
            ]
        )
        if not ok:
            self._set_flash_slot_status(slot, "NG", "#d32f2f")
            return False
        ok = await self._run_cli_command(
            [
                "upload",
                "-p",
                port,
                "--fqbn",
                self.fqbn_edit.text().strip(),
                str(sketch_path.parent),
            ]
        )
        if ok:
            self._set_flash_slot_status(slot, "OK", "#2e7d32")
        else:
            self._set_flash_slot_status(slot, "NG", "#d32f2f")
        return ok

    async def _run_cli_command(self, args: list[str]) -> bool:
        cli_path = self.cli_path_edit.text().strip()
        command = [cli_path] + args
        self.log(f"[CMD] {' '.join(command)}")

        def _run() -> subprocess.CompletedProcess:
            return subprocess.run(
                command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )

        try:
            result = await asyncio.to_thread(_run)
        except FileNotFoundError:
            self.log("[ERROR] arduino-cli not found")
            return False
        except Exception as exc:
            self.log(f"[ERROR] command failed: {exc}")
            return False
        if result.stdout:
            for line in result.stdout.splitlines():
                self.log(f"[OUT] {line}")
        if result.stderr:
            for line in result.stderr.splitlines():
                self.log(f"[ERR] {line}")
        if result.returncode != 0:
            self.log(f"[ERROR] command failed ({result.returncode})")
            return False
        return True

    def _device_sort_key(self, name: str) -> tuple:
        number = self._extract_number(name)
        return (number is None, number or 0, name)

    def _extract_number(self, name: str) -> Optional[int]:
        match = DEVICE_PATTERN.search(name or "")
        if not match:
            return None
        return int(match.group(1))

    def _current_name(self, slot: str) -> str:
        combo = self.slot_widgets[slot]["combo"]
        return combo.currentText().strip()

    def _pair_ok(self, pair_index: int) -> tuple[bool, str]:
        slot_a, slot_b = self._pairs[pair_index]
        return self._pair_ok_for_names(
            self._current_name(slot_a), self._current_name(slot_b)
        )

    def _pair_ok_for_names(self, a_name: str, b_name: str) -> tuple[bool, str]:
        a_num = self._extract_number(a_name)
        b_num = self._extract_number(b_name)
        if a_num is None or b_num is None:
            return False, "missing device numbers"
        if a_num % 2 == 0:
            return False, "A must be odd"
        if b_num % 2 != 0:
            return False, "B must be even"
        if b_num != a_num + 1:
            return False, "N mismatch"
        return True, "OK"

    def _pair_n_value(self, pair_index: int) -> Optional[int]:
        slot_a, _ = self._pairs[pair_index]
        a_num = self._extract_number(self._current_name(slot_a))
        if a_num is None:
            return None
        return (a_num + 1) // 2

    def _update_collision_status(self, *args) -> None:
        for idx, label in enumerate(self.pair_collision_labels):
            ok, reason = self._pair_ok(idx)
            n_value = self._pair_n_value(idx)
            if ok:
                text = f"{self._pair_labels[idx]} Collision: OK (N={n_value})"
                self._set_label_style(label, "#1e88e5", "#ffffff")
            else:
                text = f"{self._pair_labels[idx]} Collision: NG ({reason})"
                self._set_label_style(label, "#d32f2f", "#ffffff")
            label.setText(text)

    def _set_status(self, slot: str, text: str) -> None:
        self.slot_widgets[slot]["status_label"].setText(f"Status: {text}")
        self._refresh_color_tab()

    def _slot_com_detected(self, slot: str) -> bool:
        if not hasattr(self, "slot_widgets"):
            return False
        widgets = self.slot_widgets.get(slot)
        if not widgets:
            return False
        combo = widgets.get("port_combo")
        if combo is None:
            return False
        port = combo.currentText().strip()
        return not self._is_unconnected_port(port)

    def _is_pair2_no_connection(self, slot: str) -> bool:
        if slot not in ("A2", "B2"):
            return False
        client = self._clients.get(slot)
        if client and client.is_connected:
            return False
        return not self._slot_com_detected(slot)

    def _set_slot_no_connection_ui(self, slot: str) -> None:
        if not hasattr(self, "slot_widgets") or slot not in self.slot_widgets:
            return
        self.slot_widgets[slot]["status_label"].setText("Status: NO CONNECTION")
        self.slot_widgets[slot]["connect_button"].setEnabled(False)
        self.slot_widgets[slot]["disconnect_button"].setEnabled(False)
        self._set_state(slot, "DISCONNECT")

    def _clear_slot_no_connection_ui(self, slot: str) -> None:
        if not hasattr(self, "slot_widgets") or slot not in self.slot_widgets:
            return
        client = self._clients.get(slot)
        connected = bool(client and client.is_connected)
        if connected:
            self.slot_widgets[slot]["status_label"].setText("Status: connected")
            self.slot_widgets[slot]["connect_button"].setEnabled(False)
            self.slot_widgets[slot]["disconnect_button"].setEnabled(True)
            self._set_state(slot, "CONNECT")
        else:
            self.slot_widgets[slot]["status_label"].setText("Status: disconnected")
            self.slot_widgets[slot]["connect_button"].setEnabled(True)
            self.slot_widgets[slot]["disconnect_button"].setEnabled(False)
            self._set_state(slot, "DISCONNECT")

    def _guard_slot_execution(self, slot: str, context: str) -> bool:
        if not self._is_pair2_no_connection(slot):
            if self._no_connection_latched.get(slot):
                self._no_connection_latched[slot] = False
                self._clear_slot_no_connection_ui(slot)
            return True
        self._set_slot_no_connection_ui(slot)
        if not self._no_connection_latched.get(slot):
            self._no_connection_latched[slot] = True
            self.log(f"[NO CONNECTION] {slot} Pair2 COM not detected, skip {context}")
        return False

    def _apply_pair2_no_connection_guard_ui(self) -> None:
        for slot in ("A2", "B2"):
            if self._is_pair2_no_connection(slot):
                self._set_slot_no_connection_ui(slot)
            else:
                self._clear_slot_no_connection_ui(slot)

    def _set_battery(self, slot: str, voltage: float) -> None:
        self._slot_last_voltage[slot] = voltage
        self.slot_widgets[slot]["battery_label"].setText(f"Battery: {voltage:.2f} V")
        self._refresh_endurance_visual_slot(slot)
        self._refresh_color_tab()

    def _set_state(self, slot: str, state: str) -> None:
        previous = self._states.get(slot)
        self._states[slot] = state
        if previous != state:
            self._record_sequence(state, slot)
        labels = self.slot_widgets[slot]["state_labels"]
        for key, label in labels.items():
            if key == state:
                color = "#26a69a" if state == "GATT" else "#43a047"
                if state == "ADV":
                    color = "#f9a825"
                if state == "DISCONNECT":
                    color = "#616161"
                self._set_label_style(label, color, "#ffffff")
            else:
                self._set_label_style(label, "#333333", "#aaaaaa")
        self._refresh_endurance_visual_slot(slot)

    def _apply_dpm_profile(self) -> None:
        try:
            a_v = float(self.dpm_a_voltage_edit.text().strip())
            a_pwm = float(self.dpm_a_pwm_edit.text().strip())
            b_v = float(self.dpm_b_voltage_edit.text().strip())
            b_pwm = float(self.dpm_b_pwm_edit.text().strip())
        except ValueError:
            self._show_error("DPM values must be numeric")
            return
        self._dpm_profile["A"] = {"target_v": a_v, "pwm": a_pwm}
        self._dpm_profile["B"] = {"target_v": b_v, "pwm": b_pwm}
        marker = f"DPM_PROFILE A={a_v:.2f}V/{a_pwm:.1f}% B={b_v:.2f}V/{b_pwm:.1f}%"
        self.dpm_status_label.setText(f"DPM marker: {marker}")
        self._record_sequence(marker, "TOOL")
        self.log(f"[DPM] {marker}")
        self._refresh_endurance_visual_all()

    def _refresh_endurance_visual_all(self) -> None:
        if not hasattr(self, "endurance_visual_slots"):
            return
        for slot in self._slots:
            self._refresh_endurance_visual_slot(slot)
        self._refresh_endurance_diagram()
        self._refresh_endurance_visual_summary()
        self._refresh_endurance_failure_table()

    def _refresh_endurance_visual_slot(self, slot: str) -> None:
        if not hasattr(self, "endurance_visual_slots"):
            return
        widgets = self.endurance_visual_slots.get(slot)
        if not widgets:
            return
        name = self._current_name(slot) if hasattr(self, "slot_widgets") else ""
        if not name:
            name = self._desired_slot_names.get(slot, "")
        widgets["name"].setText(f"Name: {name or '--'}")

        state = self._states.get(slot, "DISCONNECT")
        conn_color = "#616161"
        if state == "ADV":
            conn_color = "#f9a825"
        elif state == "CONNECT":
            conn_color = "#1e88e5"
        elif state == "GATT":
            conn_color = "#2e7d32"
        widgets["conn"].setText(f"BLE: {state}")
        self._set_label_style(widgets["conn"], conn_color, "#FFFFFF")

        android = self._android_conn_status.get(slot, "UNKNOWN")
        android_color = "#616161"
        if android == "CONNECTED":
            android_color = "#2e7d32"
        elif android == "FAILED":
            android_color = "#d32f2f"
        elif android == "DISCONNECTED":
            android_color = "#455a64"
        widgets["android"].setText(f"Android: {android}")
        self._set_label_style(widgets["android"], android_color, "#FFFFFF")

        output = self._slot_output_enabled.get(slot)
        if output is True:
            widgets["output"].setText("LED: ON")
            self._set_label_style(widgets["output"], "#c62828", "#FFFFFF")
        elif output is False:
            widgets["output"].setText("LED: OFF")
            self._set_label_style(widgets["output"], "#1565c0", "#FFFFFF")
        else:
            widgets["output"].setText("LED: UNKNOWN")
            self._set_label_style(widgets["output"], "#616161", "#FFFFFF")

        voltage = self._slot_last_voltage.get(slot)
        if voltage is None:
            widgets["battery"].setText("Battery: --.- V")
            self._set_label_style(widgets["battery"], "#616161", "#FFFFFF")
        else:
            batt_color = self._battery_color(voltage)
            widgets["battery"].setText(f"Battery: {voltage:.2f} V")
            self._set_label_style(widgets["battery"], batt_color, "#FFFFFF")

        side = "A" if slot.startswith("A") else "B"
        profile = self._dpm_profile.get(side, {})
        target_v = profile.get("target_v")
        pwm = profile.get("pwm")
        if target_v is None or pwm is None:
            widgets["dpm"].setText("DPM: -- V / -- PWM")
            self._set_label_style(widgets["dpm"], "#616161", "#FFFFFF")
        else:
            widgets["dpm"].setText(f"DPM: {target_v:.2f} V / {pwm:.1f}%")
            self._set_label_style(widgets["dpm"], "#6a1b9a", "#FFFFFF")
        self._refresh_endurance_diagram()

    def _refresh_endurance_diagram(self) -> None:
        if not hasattr(self, "endurance_diagram_labels"):
            return
        for side in ("A", "B"):
            primary = f"{side}1"
            secondary = f"{side}2"
            p_state = self._states.get(primary, "DISCONNECT")
            s_state = self._states.get(secondary, "DISCONNECT")
            active_state = p_state if p_state != "DISCONNECT" else s_state
            labels = self.endurance_diagram_labels.get(side, {})
            mcu_text = f"MCU: {primary}={p_state} / {secondary}={s_state}"
            mcu_color = "#616161"
            if active_state == "ADV":
                mcu_color = "#f9a825"
            elif active_state == "CONNECT":
                mcu_color = "#1e88e5"
            elif active_state == "GATT":
                mcu_color = "#2e7d32"
            if labels.get("mcu"):
                labels["mcu"].setText(mcu_text)
                self._set_label_style(labels["mcu"], mcu_color, "#FFFFFF")

            output = self._slot_output_enabled.get(primary)
            if output is None:
                output = self._slot_output_enabled.get(secondary)
            stock_text = f"Stock {side}: LED UNKNOWN"
            if output is True:
                stock_text = f"Stock {side}: LED ON"
            elif output is False:
                stock_text = f"Stock {side}: LED OFF"
            if labels.get("stock"):
                labels["stock"].setText(stock_text)
                stock_bg = "#424242"
                if output is True:
                    stock_bg = "#c62828"
                elif output is False:
                    stock_bg = "#1565c0"
                self._set_label_style(labels["stock"], stock_bg, "#FFFFFF")

            on_label = self.endurance_stock_on_labels.get(side)
            off_label = self.endurance_stock_off_labels.get(side)
            if on_label:
                on_bg = "#c62828" if output is True else "#7f1d1d"
                self._set_label_style(on_label, on_bg, "#FFFFFF")
            if off_label:
                off_bg = "#1565c0" if output is False else "#1e3a8a"
                self._set_label_style(off_label, off_bg, "#FFFFFF")

            voltage = self._slot_last_voltage.get(primary)
            if voltage is None:
                voltage = self._slot_last_voltage.get(secondary)
            status_labels = self.endurance_side_status_labels.get(side, {})
            onoff_label = status_labels.get("onoff")
            volt_label = status_labels.get("volt")
            if onoff_label:
                if output is True:
                    onoff_label.setText("ON/OFF: ON")
                    self._set_label_style(onoff_label, "#c62828", "#FFFFFF")
                elif output is False:
                    onoff_label.setText("ON/OFF: OFF")
                    self._set_label_style(onoff_label, "#1565c0", "#FFFFFF")
                else:
                    onoff_label.setText("ON/OFF: UNKNOWN")
                    self._set_label_style(onoff_label, "#616161", "#FFFFFF")
            if volt_label:
                if voltage is None:
                    volt_label.setText("Battery: --.- V")
                    self._set_label_style(volt_label, "#616161", "#FFFFFF")
                else:
                    batt_bg = self._battery_color(voltage)
                    volt_label.setText(f"Battery: {voltage:.2f} V")
                    self._set_label_style(volt_label, batt_bg, "#FFFFFF")

            profile = self._dpm_profile.get(side, {})
            dpm_label = labels.get("dpm")
            if dpm_label:
                target_v = profile.get("target_v")
                pwm = profile.get("pwm")
                if target_v is None or pwm is None:
                    dpm_label.setText("DPM + Regulator")
                    self._set_label_style(dpm_label, "#6a1b9a", "#FFFFFF")
                else:
                    dpm_label.setText(f"DPM: {target_v:.2f} V / {pwm:.1f}%")
                    self._set_label_style(dpm_label, "#6a1b9a", "#FFFFFF")
            center_label = (
                self.endurance_stock_center_a
                if side == "A"
                else self.endurance_stock_center_b
            )
            center_text = f"Stock {side}: "
            if output is True:
                center_text += "ON"
            elif output is False:
                center_text += "OFF"
            else:
                center_text += "UNKNOWN"
            if voltage is not None:
                center_text += f" / {voltage:.2f}V"
            center_label.setText(center_text)
            center_bg = "#455a64"
            if output is True:
                center_bg = "#c62828"
            elif output is False:
                center_bg = "#1565c0"
            self._set_label_style(center_label, center_bg, "#FFFFFF")

    def _refresh_endurance_visual_summary(self) -> None:
        if not hasattr(self, "endurance_visual_cycle_label"):
            return
        total = self._endurance_total_cycles
        done = self._endurance_done_cycles
        self.endurance_visual_cycle_label.setText(f"Cycles: {done}/{total}")
        self.endurance_visual_pass_label.setText(f"PASS: {self._endurance_pass_count}")
        self.endurance_visual_fail_label.setText(f"FAIL: {self._endurance_fail_count}")
        if total > 0:
            self.endurance_visual_progress.setValue(int((done / total) * 100))
        else:
            self.endurance_visual_progress.setValue(0)
        if hasattr(self, "endurance_pc_status_label"):
            run_state = "RUNNING" if self._endurance_task and not self._endurance_task.done() else "IDLE"
            self.endurance_pc_status_label.setText(
                f"PC: {run_state} ({done}/{total})"
            )
            pc_bg = "#1e88e5" if run_state == "RUNNING" else "#546e7a"
            self._set_label_style(self.endurance_pc_status_label, pc_bg, "#FFFFFF")
        if hasattr(self, "endurance_android_summary_label"):
            connected = sum(1 for s in self._slots if self._android_conn_status.get(s) == "CONNECTED")
            failed = sum(1 for s in self._slots if self._android_conn_status.get(s) == "FAILED")
            self.endurance_android_summary_label.setText(
                f"Android: CONNECTED={connected} FAILED={failed}"
            )
            android_bg = "#2e7d32" if failed == 0 else "#d32f2f"
            self._set_label_style(self.endurance_android_summary_label, android_bg, "#FFFFFF")
        if hasattr(self, "endurance_link_status_label"):
            pass_rate = (
                (self._endurance_pass_count / max(1, self._endurance_done_cycles)) * 100.0
                if self._endurance_done_cycles > 0
                else 0.0
            )
            self.endurance_link_status_label.setText(
                f"Status: PASS={self._endurance_pass_count} FAIL={self._endurance_fail_count} ({pass_rate:.1f}%)"
            )
            link_bg = "#2e7d32" if self._endurance_fail_count == 0 else "#d32f2f"
            self._set_label_style(self.endurance_link_status_label, link_bg, "#FFFFFF")
        if hasattr(self, "endurance_display_view"):
            recent = self._sequence_events[-5:]
            lines = []
            for entry in recent:
                lines.append(
                    f"{entry.get('elapsed', 0):7.3f}s [{entry.get('slot', '')}] {entry.get('event', '')}"
                )
            summary = (
                f"Cycles: {done}/{total}  PASS={self._endurance_pass_count}  FAIL={self._endurance_fail_count}\n"
                f"Report: {self._endurance_report_path or '--'}\n"
                + "\n".join(lines)
            )
            self.endurance_display_view.setPlainText(summary)

    def _refresh_endurance_failure_table(self) -> None:
        if not hasattr(self, "endurance_failure_table"):
            return
        items = sorted(self._endurance_failure_counter.items())
        self.endurance_failure_table.setRowCount(len(items))
        for row, (failure, count) in enumerate(items):
            failure_item = QTableWidgetItem(failure)
            failure_item.setFlags(failure_item.flags() & ~Qt.ItemIsEditable)
            count_item = QTableWidgetItem(str(count))
            count_item.setFlags(count_item.flags() & ~Qt.ItemIsEditable)
            self.endurance_failure_table.setItem(row, 0, failure_item)
            self.endurance_failure_table.setItem(row, 1, count_item)
        self.endurance_failure_table.resizeColumnsToContents()

    def _all_connected(self) -> bool:
        return all(
            self._clients.get(slot) and self._clients[slot].is_connected
            for slot in self._slots
        )

    def _all_disconnected(self) -> bool:
        return all(
            (self._clients.get(slot) is None)
            or (not self._clients[slot].is_connected)
            for slot in self._slots
        )

    def _battery_percent(self, voltage: Optional[float]) -> int:
        if voltage is None:
            return 0
        span = BATTERY_FULL_V - BATTERY_EMPTY_V
        if span <= 0:
            return 0
        percent = round((voltage - BATTERY_EMPTY_V) / span * 100)
        return max(0, min(100, percent))

    def _battery_color(self, voltage: Optional[float]) -> str:
        if voltage is None:
            return "#616161"
        percent = self._battery_percent(voltage)
        if percent >= 60:
            return "#2e7d32"
        if percent >= 25:
            return "#f9a825"
        return "#d32f2f"

    def _parse_voltage(self, raw: bytes) -> Optional[float]:
        if not raw:
            return None
        if len(raw) >= 4:
            mv = int.from_bytes(raw[2:4], "little", signed=False)
            if mv <= 0:
                return None
            return (mv / 1000.0) * BATTERY_DIVIDER_RATIO
        value = int.from_bytes(raw, "little", signed=False)
        if len(raw) == 1:
            return float(value)
        if len(raw) == 2:
            if value > 1000:
                return value / 1000.0
            return value / 100.0
        return float(value)

    def _set_label_style(self, label: QLabel, bg: str, fg: str) -> None:
        label.setStyleSheet(
            f"background-color: {bg}; color: {fg}; padding: 4px; border-radius: 4px;"
        )

    def _on_auto_test_changed(self, *args) -> None:
        if self.auto_test_check.isChecked() and self._endurance_task and not self._endurance_task.done():
            self.auto_test_check.setChecked(False)
            self.log("[AUTO] ignored while endurance test is running")
            return
        if self.auto_test_check.isChecked():
            self._auto_test_task = asyncio.create_task(self._auto_test_loop())
        else:
            if self._auto_test_task:
                self._auto_test_task.cancel()
                self._auto_test_task = None

    async def _auto_test_loop(self) -> None:
        self.log("[AUTO] test start")
        try:
            while self.auto_test_check.isChecked():
                await self._connect_both()
                await self._after_both_connected()
                await asyncio.sleep(1.0)
                await self._disconnect_both()
                await asyncio.sleep(1.0)
        except asyncio.CancelledError:
            pass
        finally:
            self.log("[AUTO] test stop")

    def _start_endurance(self, fixed_cycles: Optional[int] = None) -> None:
        if self._endurance_task and not self._endurance_task.done():
            return
        if fixed_cycles is None:
            try:
                fixed_cycles = int(self.endurance_cycles_edit.text().strip())
            except ValueError:
                self._show_error("Cycles must be integer")
                return
        if fixed_cycles <= 0:
            self._show_error("Cycles must be > 0")
            return
        try:
            connect_wait = float(self.endurance_connect_wait_edit.text().strip())
            disconnect_wait = float(self.endurance_disconnect_wait_edit.text().strip())
        except ValueError:
            self._show_error("Wait time must be numeric")
            return
        if connect_wait < 0 or disconnect_wait < 0:
            self._show_error("Wait time must be >= 0")
            return
        self._endurance_stop_requested = False
        self._endurance_task = asyncio.create_task(
            self._run_endurance_loop(fixed_cycles, connect_wait, disconnect_wait)
        )
        self._endurance_task.add_done_callback(self._on_endurance_finished)
        self._set_endurance_running(True)

    def _stop_endurance(self) -> None:
        self._endurance_stop_requested = True
        if self._endurance_task and not self._endurance_task.done():
            self._endurance_task.cancel()

    def _on_endurance_finished(self, task: asyncio.Task) -> None:
        self._set_endurance_running(False)
        self._endurance_task = None
        self._endurance_active_cycle = None
        if task.cancelled():
            self.endurance_status_label.setText("STOPPED")
            self._refresh_endurance_visual_summary()
            return
        exc = task.exception()
        if exc:
            self.endurance_status_label.setText("ERROR")
            self.log(f"[ENDURANCE] task failed: {exc}")
            self._refresh_endurance_visual_summary()
            return
        if self._endurance_stop_requested:
            self.endurance_status_label.setText("STOPPED")
        else:
            self.endurance_status_label.setText("DONE")
        self._refresh_endurance_visual_summary()

    def _set_endurance_running(self, running: bool) -> None:
        self.endurance_start_100_button.setEnabled(not running)
        self.endurance_start_custom_button.setEnabled(not running)
        self.endurance_stop_button.setEnabled(running)
        if running:
            self.endurance_status_label.setText("RUNNING")
        self._refresh_endurance_visual_summary()

    def _copy_endurance_report_path(self) -> None:
        if not self._endurance_report_path:
            return
        self._copy_path_to_clipboard(self._endurance_report_path, "Endurance Report")

    async def _run_endurance_loop(
        self, cycles: int, connect_wait_s: float, disconnect_wait_s: float
    ) -> None:
        self.log(f"[ENDURANCE] start cycles={cycles}")
        self.endurance_progress_label.setText(f"Cycle: 0/{cycles}")
        self._endurance_total_cycles = cycles
        self._endurance_done_cycles = 0
        self._endurance_pass_count = 0
        self._endurance_fail_count = 0
        self._endurance_failure_counter.clear()
        self._endurance_cycle_records.clear()
        self._endurance_report_path = None
        self.endurance_report_label.setText("Report: --")
        self.endurance_copy_report_button.setEnabled(False)
        if hasattr(self, "endurance_visual_last_label"):
            self.endurance_visual_last_label.setText("Last: --")
        self._refresh_endurance_visual_summary()
        self._refresh_endurance_failure_table()

        # Keep this run isolated from older CSV data.
        self._clear_sequence_events()
        self._start_active_sequence_csv("endurance")
        self._reset_android_conn_status()

        if self.endurance_ble_only_check.isChecked():
            self.android_ble_only_check.setChecked(True)
            self.android_add_sequence_check.setChecked(True)

        if self.auto_test_check.isChecked():
            self.auto_test_check.setChecked(False)

        if self.endurance_require_register_check.isChecked():
            ok, reason = self._validate_register_baseline()
            if not ok:
                self._record_sequence(f"REGISTER_INVALID {reason}", "TOOL")
                self.log(f"[ENDURANCE] register baseline NG: {reason}")
                self.endurance_status_label.setText("FAILED")
                return
            self._record_register_baseline()
        cancelled = False
        try:
            for cycle in range(1, cycles + 1):
                if self._endurance_stop_requested:
                    break
                record = await self._run_endurance_cycle(
                    cycle, cycles, connect_wait_s, disconnect_wait_s
                )
                self._endurance_cycle_records.append(record)
                self._endurance_done_cycles = cycle
                if record["result"] == "PASS":
                    self._endurance_pass_count += 1
                else:
                    self._endurance_fail_count += 1
                self._endurance_failure_counter[record["failure_class"]] += 1
                self.endurance_progress_label.setText(f"Cycle: {cycle}/{cycles}")
                if hasattr(self, "endurance_visual_last_label"):
                    self.endurance_visual_last_label.setText(
                        f"Last: cycle {cycle} {record['result']} ({record['failure_class']})"
                    )
                self._refresh_endurance_visual_summary()
                self._refresh_endurance_failure_table()
                if record["result"] == "FAIL" and self.endurance_stop_on_fail_check.isChecked():
                    self.log(f"[ENDURANCE] stop on fail at cycle={cycle}")
                    break
        except asyncio.CancelledError:
            cancelled = True
            self.log("[ENDURANCE] cancelled")
        finally:
            self._endurance_active_cycle = None
            await self._disconnect_both()

        self._endurance_report_path = self._export_endurance_report_csv()
        if self._endurance_report_path:
            self.endurance_report_label.setText(f"Report: {self._endurance_report_path}")
            self.endurance_copy_report_button.setEnabled(True)
            self.log(f"[ENDURANCE] report {self._endurance_report_path}")
        if cancelled:
            raise asyncio.CancelledError

    def _validate_register_baseline(self) -> tuple[bool, str]:
        if not self._register_entries:
            return False, "register table empty"
        for idx, (slot_a, slot_b) in enumerate(self._pairs):
            ok, reason = self._pair_ok(idx)
            if not ok:
                return False, f"{self._pair_labels[idx]} {reason}"
            a_name = self._current_name(slot_a)
            b_name = self._current_name(slot_b)
            matched = False
            for entry in self._register_entries:
                if entry.a_name == a_name and entry.b_name == b_name:
                    matched = True
                    break
            if not matched:
                return False, f"{self._pair_labels[idx]} not registered ({a_name}/{b_name})"
        return True, "OK"

    def _record_register_baseline(self) -> None:
        self._record_sequence("REGISTER_BASELINE_OK", "TOOL")
        for idx, (slot_a, slot_b) in enumerate(self._pairs):
            a_name = self._current_name(slot_a)
            b_name = self._current_name(slot_b)
            a_mac = self._device_map.get(a_name, self._mac_from_register(slot_a, a_name))
            b_mac = self._device_map.get(b_name, self._mac_from_register(slot_b, b_name))
            n_value = self._pair_n_value(idx)
            self._record_sequence(
                f"REGISTER_PAIR pair={idx + 1} n={n_value} a={a_name}({a_mac}) b={b_name}({b_mac})",
                "TOOL",
            )

    def _all_selected_names_discovered(self) -> bool:
        for slot in self._slots:
            name = self._current_name(slot)
            if not name or name not in self._device_map:
                return False
        return True

    async def _run_endurance_cycle(
        self,
        cycle: int,
        total_cycles: int,
        connect_wait_s: float,
        disconnect_wait_s: float,
    ) -> dict:
        start_idx = len(self._sequence_events)
        start_iso = datetime.now().isoformat(timespec="milliseconds")
        t0 = time.perf_counter()
        self._endurance_active_cycle = cycle
        self._record_sequence(f"CYCLE_START {cycle}/{total_cycles}", "TOOL")
        dpm_a = self._dpm_profile.get("A", {})
        dpm_b = self._dpm_profile.get("B", {})
        if (
            dpm_a.get("target_v") is not None
            and dpm_a.get("pwm") is not None
            and dpm_b.get("target_v") is not None
            and dpm_b.get("pwm") is not None
        ):
            self._record_sequence(
                "DPM_MARKER "
                f"A={dpm_a.get('target_v'):.2f}V/{dpm_a.get('pwm'):.1f}% "
                f"B={dpm_b.get('target_v'):.2f}V/{dpm_b.get('pwm'):.1f}%",
                "TOOL",
            )

        await self._scan_devices()
        t_scan = time.perf_counter()
        scan_ok = self._all_selected_names_discovered()
        if not scan_ok:
            self._record_sequence("SCAN_EXPECTED_MISSING", "TOOL")

        connect_ok = await self._connect_both()
        t_connect = time.perf_counter()
        if connect_wait_s > 0:
            await asyncio.sleep(connect_wait_s)

        gatt_ok = False
        if connect_ok:
            startup_ok = await self._run_startup_wave_all(
                repeat_count=len(self._startup_wave_colors), cycle_seconds=1.0
            )
            gatt_ok = startup_ok and await self._after_both_connected()
            if self.endurance_run_gatt_check.isChecked():
                await self._gatt_test_all()
        t_gatt = time.perf_counter()

        disconnect_ok = await self._disconnect_both()
        if disconnect_wait_s > 0:
            await asyncio.sleep(disconnect_wait_s)
        disconnect_ok = disconnect_ok and self._all_disconnected()
        t_end = time.perf_counter()
        end_iso = datetime.now().isoformat(timespec="milliseconds")

        self._record_sequence(
            f"CYCLE_END {cycle}/{total_cycles} scan={scan_ok} connect={connect_ok} gatt={gatt_ok} disconnect={disconnect_ok}",
            "TOOL",
        )
        cycle_entries = self._sequence_events[start_idx:]
        result = (
            "PASS"
            if (scan_ok and connect_ok and gatt_ok and disconnect_ok)
            else "FAIL"
        )
        failure_class, failure_detail = self._classify_cycle_failure(
            cycle_entries, scan_ok, connect_ok, gatt_ok, disconnect_ok
        )
        if result == "PASS":
            failure_class = "PASS"
            failure_detail = ""

        last_ble = self._tail_lines(cycle_entries, slot="ANDROID", ble_only=True, limit=5)
        last_mcu = self._tail_lines(cycle_entries, slot="MCU", ble_only=False, limit=5)

        rec = {
            "cycle": cycle,
            "start_iso": start_iso,
            "end_iso": end_iso,
            "result": result,
            "failure_class": failure_class,
            "failure_detail": failure_detail,
            "scan_ms": (t_scan - t0) * 1000.0,
            "connect_ms": (t_connect - t_scan) * 1000.0,
            "gatt_ms": (t_gatt - t_connect) * 1000.0,
            "disconnect_ms": (t_end - t_gatt) * 1000.0,
            "total_ms": (t_end - t0) * 1000.0,
            "scan_ok": scan_ok,
            "connect_ok": connect_ok,
            "gatt_ok": gatt_ok,
            "disconnect_ok": disconnect_ok,
            "last_ble": last_ble,
            "last_mcu": last_mcu,
            "active_csv": str(self._active_sequence_csv_path or ""),
        }
        self.log(
            f"[ENDURANCE] cycle={cycle:03d} {result} "
            f"scan={rec['scan_ms']:.0f}ms connect={rec['connect_ms']:.0f}ms "
            f"gatt={rec['gatt_ms']:.0f}ms disconnect={rec['disconnect_ms']:.0f}ms "
            f"class={failure_class}"
        )
        if result != "PASS":
            self._record_connection_failure(
                failure_class,
                detail=failure_detail,
                example=(
                    f"[ENDURANCE] cycle={cycle:03d} result={result} "
                    f"class={failure_class} detail={failure_detail}"
                ),
            )
        self._endurance_active_cycle = None
        return rec

    def _tail_lines(
        self, entries: list[dict], slot: str, ble_only: bool, limit: int
    ) -> str:
        lines: list[str] = []
        for entry in entries:
            if str(entry.get("slot", "")) != slot:
                continue
            text = str(entry.get("event", ""))
            if ble_only:
                if "ANDROID:" in text:
                    line = text.split("ANDROID:", 1)[1].strip()
                else:
                    line = text
                if not self._is_ble_log(line):
                    continue
            lines.append(text)
        return " || ".join(lines[-limit:])

    def _classify_cycle_failure(
        self,
        entries: list[dict],
        scan_ok: bool,
        connect_ok: bool,
        gatt_ok: bool,
        disconnect_ok: bool,
    ) -> tuple[str, str]:
        all_text = " ".join(str(entry.get("event", "")) for entry in entries).lower()
        flat_cycle_ids: set[str] = set()
        for entry in entries:
            text = str(entry.get("event", "")).lower()
            for cid in re.findall(r"\[cycle\s+(\d+)\]", text):
                flat_cycle_ids.add(cid)
        if len(flat_cycle_ids) > 1:
            return "LOG_MIXED_OLD_DATA", "multiple cycle ids detected in one cycle window"
        if "status 133" in all_text or "gatt_error" in all_text:
            return "STATUS_133_GATT_ERROR", "status 133 / gatt_error"
        if "0x0016" in all_text or "reason 0x0016" in all_text:
            return "REASON_0X0016", "reason 0x0016"
        if "api_close_evt" in all_text or "bta_gattc_api_close_evt" in all_text:
            return "API_CLOSE_EVT", "api_close event"
        if "gatt_deregister" in all_text or "ble_app_close" in all_text:
            return "APP_RESET_OR_DEREGISTER", "app close/deregister"
        if (
            "gatt_profile_missing" in all_text
            or "class=profile_missing" in all_text
            or "adv characteristic not found" in all_text
            or "base services only (1800/1801)" in all_text
        ):
            return "PROFILE_MISSING", "required service/characteristic not exposed"
        if "service discovery failed" in all_text or "discover failed" in all_text:
            return "SERVICE_DISCOVERY_FAIL", "service discovery failed"
        if "cccd" in all_text and ("fail" in all_text or "error" in all_text):
            return "CCCD_SUBSCRIBE_FAIL", "cccd subscribe failed"
        if not self.android_ble_only_check.isChecked():
            for entry in entries:
                if str(entry.get("slot", "")) != "ANDROID":
                    continue
                event_text = str(entry.get("event", ""))
                line = event_text.split("ANDROID:", 1)[1].strip() if "ANDROID:" in event_text else event_text
                if not self._is_ble_log(line):
                    return "NON_BLE_LOG_MIXED", "non-BLE Android log mixed"
        if not scan_ok:
            return "ADV_NOT_FOUND", "advertising not detected for selected names"
        if not connect_ok:
            return "CONNECT_FAILED", "connect timeout or connect rejected"
        if not gatt_ok:
            return "GATT_TIMEOUT_OR_READ_FAIL", "gatt battery/read stage failed"
        if not disconnect_ok:
            return "DISCONNECT_INCOMPLETE", "disconnect incomplete"
        return "OTHER", "unclassified"

    def _export_endurance_report_csv(self) -> Optional[Path]:
        if not self._endurance_cycle_records:
            return None
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        detail_path = self._log_dir / f"endurance_report_{timestamp}.csv"
        summary_path = self._log_dir / f"endurance_report_summary_{timestamp}.csv"
        with detail_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
                    "cycle",
                    "start_iso",
                    "end_iso",
                    "result",
                    "failure_class",
                    "failure_detail",
                    "scan_ms",
                    "connect_ms",
                    "gatt_ms",
                    "disconnect_ms",
                    "total_ms",
                    "scan_ok",
                    "connect_ok",
                    "gatt_ok",
                    "disconnect_ok",
                    "active_csv",
                    "last_ble",
                    "last_mcu",
                ]
            )
            for rec in self._endurance_cycle_records:
                writer.writerow(
                    [
                        rec["cycle"],
                        rec["start_iso"],
                        rec["end_iso"],
                        rec["result"],
                        rec["failure_class"],
                        rec["failure_detail"],
                        f"{rec['scan_ms']:.1f}",
                        f"{rec['connect_ms']:.1f}",
                        f"{rec['gatt_ms']:.1f}",
                        f"{rec['disconnect_ms']:.1f}",
                        f"{rec['total_ms']:.1f}",
                        rec["scan_ok"],
                        rec["connect_ok"],
                        rec["gatt_ok"],
                        rec["disconnect_ok"],
                        rec["active_csv"],
                        rec["last_ble"],
                        rec["last_mcu"],
                    ]
                )
        counts = Counter(rec["failure_class"] for rec in self._endurance_cycle_records)
        with summary_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["failure_class", "count"])
            for key, count in sorted(counts.items()):
                writer.writerow([key, count])
            writer.writerow(["TOTAL", len(self._endurance_cycle_records)])
            writer.writerow(
                [
                    "PASS_RATE(%)",
                    f"{(counts.get('PASS', 0) / max(1, len(self._endurance_cycle_records))) * 100.0:.2f}",
                ]
            )
        self.log(f"[ENDURANCE] summary {summary_path}")
        return detail_path

    # --------------------------- Register ---------------------------
    def _add_current_pair(self) -> None:
        added = False
        errors = []
        for idx in range(len(self._pairs)):
            ok, reason = self._pair_ok(idx)
            if not ok:
                errors.append(f"{self._pair_labels[idx]}: {reason}")
                continue
            n_value = self._pair_n_value(idx)
            if n_value is None:
                errors.append(f"{self._pair_labels[idx]}: N parse failed")
                continue
            slot_a, slot_b = self._pairs[idx]
            a_name = self._current_name(slot_a)
            b_name = self._current_name(slot_b)
            a_mac = self._device_map.get(a_name, "")
            b_mac = self._device_map.get(b_name, "")
            a_port = self.slot_widgets[slot_a]["port_combo"].currentText()
            b_port = self.slot_widgets[slot_b]["port_combo"].currentText()
            entry = RegisterEntry(
                n_value=n_value,
                a_name=a_name,
                a_port=a_port,
                a_mac=a_mac,
                b_name=b_name,
                b_port=b_port,
                b_mac=b_mac,
            )
            self._register_entries.append(entry)
            added = True
        if not added:
            self._show_error("Cannot add: " + ", ".join(errors))
            return
        self._save_register()
        self._refresh_table()

    def _delete_selected(self) -> None:
        selected = self.table.selectionModel().selectedRows()
        if not selected:
            return
        indices = sorted((index.row() for index in selected), reverse=True)
        start = self._page_index * PAGE_SIZE
        for row in indices:
            idx = start + row
            if 0 <= idx < len(self._register_entries):
                self._register_entries.pop(idx)
        self._save_register()
        self._refresh_table()

    def _clear_register(self) -> None:
        self._register_entries.clear()
        self._page_index = 0
        self._save_register()
        self._refresh_table()

    def _refresh_table(self) -> None:
        self.table.setRowCount(0)
        start = self._page_index * PAGE_SIZE
        page_entries = self._register_entries[start : start + PAGE_SIZE]
        for row, entry in enumerate(page_entries):
            self.table.insertRow(row)
            for col, value in enumerate(entry.to_row()):
                item = QTableWidgetItem(value)
                item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.table.setItem(row, col, item)
        total_pages = max(1, (len(self._register_entries) + PAGE_SIZE - 1) // PAGE_SIZE)
        self.page_label.setText(f"{self._page_index + 1} / {total_pages}")

    def _change_page(self, delta: int) -> None:
        total_pages = max(1, (len(self._register_entries) + PAGE_SIZE - 1) // PAGE_SIZE)
        new_index = self._page_index + delta
        if 0 <= new_index < total_pages:
            self._page_index = new_index
            self._refresh_table()

    def _save_register(self) -> None:
        data = [entry.to_dict() for entry in self._register_entries]
        self._register_path.write_text(json.dumps(data, ensure_ascii=True, indent=2))

    def _save_color_settings(self) -> None:
        try:
            color_state = {}
            for slot, state in self._color_state.items():
                color_state[slot] = {
                    "front": QColor(state.get("front", QColor(255, 255, 255))).name(),
                    "rear": QColor(state.get("rear", QColor(255, 255, 255))).name(),
                    "brightness": int(state.get("brightness", 200)),
                    "output": bool(state.get("output", False)),
                    "mode": str(state.get("mode", "off")),
                }
            data = {
                "color_selected": self._color_selected.name(),
                "color_hue": int(self._color_hue),
                "color_saturation": int(self._color_saturation),
                "color_value": int(self._color_value),
                "syncro_enabled": bool(self._color_cheat),
                "heartbeat_color": self._color_heartbeat_color.name(),
                "pattern_selected": self._pattern_selected.name(),
                "startup_wave_cycle_ms": int(self._startup_wave_cycle_ms),
                "startup_wave_colors": [
                    QColor(color).name() for color in self._startup_wave_colors
                ],
                "color_state": color_state,
            }
            self._color_settings_path.write_text(
                json.dumps(data, ensure_ascii=True, indent=2),
                encoding="utf-8",
            )
        except Exception:
            return

    def _load_color_settings(self) -> None:
        if not self._color_settings_path.exists():
            return
        try:
            data = json.loads(self._color_settings_path.read_text(encoding="utf-8"))
        except Exception:
            return

        color_selected = QColor(str(data.get("color_selected", self._color_selected.name())))
        if color_selected.isValid():
            self._color_selected = color_selected

        try:
            self._color_hue = int(data.get("color_hue", self._color_hue))
            self._color_saturation = int(
                data.get("color_saturation", self._color_saturation)
            )
            self._color_value = int(data.get("color_value", self._color_value))
        except Exception:
            pass

        self._color_cheat = bool(data.get("syncro_enabled", self._color_cheat))

        heartbeat_color = QColor(
            str(data.get("heartbeat_color", self._color_heartbeat_color.name()))
        )
        if heartbeat_color.isValid():
            self._color_heartbeat_color = heartbeat_color

        pattern_selected = QColor(
            str(data.get("pattern_selected", self._pattern_selected.name()))
        )
        if pattern_selected.isValid():
            self._pattern_selected = pattern_selected

        try:
            self._startup_wave_cycle_ms = max(
                200, min(10000, int(data.get("startup_wave_cycle_ms", self._startup_wave_cycle_ms)))
            )
        except Exception:
            pass

        raw_colors = data.get("startup_wave_colors")
        if isinstance(raw_colors, list):
            loaded_colors: list[QColor] = []
            for item in raw_colors[:5]:
                color = QColor(str(item))
                if color.isValid():
                    loaded_colors.append(color)
            if loaded_colors:
                while len(loaded_colors) < 5:
                    loaded_colors.append(QColor(loaded_colors[-1]))
                self._startup_wave_colors = loaded_colors[:5]

        raw_state = data.get("color_state")
        if isinstance(raw_state, dict):
            for slot in self._slots:
                slot_state = raw_state.get(slot)
                if not isinstance(slot_state, dict):
                    continue
                front = QColor(str(slot_state.get("front", self._color_selected.name())))
                rear = QColor(str(slot_state.get("rear", self._color_selected.name())))
                if front.isValid():
                    self._color_state[slot]["front"] = front
                if rear.isValid():
                    self._color_state[slot]["rear"] = rear
                try:
                    self._color_state[slot]["brightness"] = int(
                        slot_state.get("brightness", self._color_value)
                    )
                except Exception:
                    pass
                self._color_state[slot]["output"] = bool(
                    slot_state.get("output", self._color_state[slot]["output"])
                )
                self._color_state[slot]["mode"] = str(
                    slot_state.get("mode", self._color_state[slot]["mode"])
                )
        else:
            for slot in self._slots:
                self._color_state[slot]["front"] = QColor(self._color_selected)
                self._color_state[slot]["rear"] = QColor(self._color_selected)
                self._color_state[slot]["brightness"] = int(self._color_value)

    def _load_register(self) -> None:
        if not self._register_path.exists():
            return
        try:
            data = json.loads(self._register_path.read_text(encoding="utf-8"))
        except Exception:
            return
        self._register_entries = [RegisterEntry.from_dict(item) for item in data]
        self._refresh_table()

    def _export_register_csv(self) -> None:
        path = self._log_dir / f"register_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                ["N", "A Device Name", "A Port", "A MAC", "B Device Name", "B Port", "B MAC"]
            )
            for entry in self._register_entries:
                writer.writerow(entry.to_row())
        self._copy_path_to_clipboard(path, "Register CSV")
        self.log(f"[CSV] saved {path}")

    def _start_active_sequence_csv(self, source: str) -> None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = self._log_dir / f"sequence_events_{timestamp}.csv"
        self._active_sequence_csv_path = path
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["time_sec", "delta_ms", "slot", "event"])
        self._sync_sequence_csv_edits(path)
        self.log(f"[SEQ] active csv ({source}) {path}")

    def _append_active_sequence_csv(self, entry: dict) -> None:
        path = self._active_sequence_csv_path
        if not path:
            return
        with path.open("a", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
                    f"{entry['elapsed']:.3f}",
                    f"{entry['delta_ms']:.1f}",
                    entry["slot"],
                    entry["event"],
                ]
            )

    def _sync_sequence_csv_edits(self, path: Path) -> None:
        text = str(path)
        if hasattr(self, "android_csv_path_edit"):
            self.android_csv_path_edit.setText(text)
        if hasattr(self, "sequence_timing_csv_edit"):
            self.sequence_timing_csv_edit.setText(text)

    def _copy_path_to_clipboard(self, path: Path, label: str) -> None:
        app = QApplication.instance()
        if app and app.clipboard():
            app.clipboard().setText(str(path))
            self.log(f"[COPY] {label} path copied: {path}")

    def _copy_text_to_clipboard(self, text: str, label: str) -> None:
        if not text:
            return
        app = QApplication.instance()
        if app and app.clipboard():
            app.clipboard().setText(text)
            self.log(f"[COPY] {label} path copied: {text}")

    # --------------------------- Ports ---------------------------
    def _refresh_ports(self) -> None:
        ports = self._list_ports()
        for slot in self._slots:
            combo = self.slot_widgets[slot]["port_combo"]
            current = combo.currentText()
            self._fill_port_combo(combo, ports, current)
        self._apply_pair2_no_connection_guard_ui()

    def _list_ports(self) -> list[str]:
        try:
            from serial.tools import list_ports
        except Exception:
            return []
        return [port.device for port in list_ports.comports()]

    def _detect_connection_failure(self, message: str) -> Optional[tuple[str, str]]:
        text = message.lower().strip()
        if not text:
            return None
        if "result=pass" in text:
            return None
        if "connect backoff active" in text:
            return "PROFILE_MISSING_LATCHED", "automatic reconnect is blocked after a profile-missing failure"
        if "class=unexpected_link_drop" in text:
            return "UNEXPECTED_LINK_DROP", CONNECTION_FAILURE_NOTES["UNEXPECTED_LINK_DROP"]
        if "connect blocked (profile_missing latched)" in text:
            return "PROFILE_MISSING_LATCHED", "manual reconnect attempt was blocked by profile-missing latch"
        class_match = re.search(r"class=([a-z0-9_]+)", text)
        if class_match:
            failure_class = class_match.group(1).upper()
            if failure_class not in {"PASS", "N_A"}:
                return failure_class, CONNECTION_FAILURE_NOTES.get(
                    failure_class,
                    "classified from runtime log",
                )
        if "protocol error 0x05" in text or "insufficient authentication" in text:
            return "INSUFFICIENT_AUTHENTICATION", CONNECTION_FAILURE_NOTES["INSUFFICIENT_AUTHENTICATION"]
        if "status 133" in text or "gatt_error" in text:
            return "STATUS_133_GATT_ERROR", CONNECTION_FAILURE_NOTES["STATUS_133_GATT_ERROR"]
        if "reason 0x0016" in text or "0x0016" in text:
            return "REASON_0X0016", CONNECTION_FAILURE_NOTES["REASON_0X0016"]
        if "api_close_evt" in text or "bta_gattc_api_close_evt" in text:
            return "API_CLOSE_EVT", CONNECTION_FAILURE_NOTES["API_CLOSE_EVT"]
        if "gatt_deregister" in text or "ble_app_close" in text:
            return "APP_RESET_OR_DEREGISTER", CONNECTION_FAILURE_NOTES["APP_RESET_OR_DEREGISTER"]
        if (
            "adv characteristic not found" in text
            or "base services only (1800/1801)" in text
            or "required characteristic unavailable after connect" in text
            or "profile_missing" in text
        ):
            return "PROFILE_MISSING", CONNECTION_FAILURE_NOTES["PROFILE_MISSING"]
        if "characteristic" in text and "was not found" in text:
            return "CHAR_NOT_FOUND", CONNECTION_FAILURE_NOTES["CHAR_NOT_FOUND"]
        if "service discovery failed" in text or "discover failed" in text:
            return "SERVICE_DISCOVERY_FAIL", CONNECTION_FAILURE_NOTES["SERVICE_DISCOVERY_FAIL"]
        if "cccd" in text and ("fail" in text or "error" in text):
            return "CCCD_SUBSCRIBE_FAIL", CONNECTION_FAILURE_NOTES["CCCD_SUBSCRIBE_FAIL"]
        if "not found in current scan results" in text:
            return "ADV_NOT_FOUND_OR_NAME_MISMATCH", CONNECTION_FAILURE_NOTES["ADV_NOT_FOUND_OR_NAME_MISMATCH"]
        if "connect failed:" in text:
            return "CONNECT_FAILED", CONNECTION_FAILURE_NOTES["CONNECT_FAILED"]
        if "gatt timeout" in text or "read fail" in text:
            return "GATT_TIMEOUT_OR_READ_FAIL", CONNECTION_FAILURE_NOTES["GATT_TIMEOUT_OR_READ_FAIL"]
        if "disconnect incomplete" in text:
            return "DISCONNECT_INCOMPLETE", CONNECTION_FAILURE_NOTES["DISCONNECT_INCOMPLETE"]
        if "[error] select a serial port" in text:
            return "SERIAL_TRIGGERED_RESET_OR_LINK_DROP", "serial monitor start failed because no serial port was selected"
        return None

    def _record_connection_failure(
        self,
        failure_class: str,
        detail: str = "",
        example: str = "",
    ) -> None:
        failure_class = (failure_class or "").strip().upper()
        if not failure_class or failure_class == "PASS":
            return
        now = time.monotonic()
        last = self._connection_failure_last_recorded_at.get(failure_class, 0.0)
        if now - last < FAILURE_LOG_DEBOUNCE_S:
            return
        self._connection_failure_last_recorded_at[failure_class] = now
        iso = datetime.now().isoformat(timespec="seconds")
        self._connection_failure_counter[failure_class] += 1
        self._connection_failure_first_seen.setdefault(failure_class, iso)
        self._connection_failure_last_seen[failure_class] = iso
        if detail:
            self._connection_failure_last_detail[failure_class] = detail
        if example:
            self._connection_failure_last_message[failure_class] = example
        self._write_connection_failure_summary()

    def _default_investigation_summary(self) -> dict[str, object]:
        address_type = str(getattr(config, "WINRT_ADDRESS_TYPE", "") or "").lower()
        if address_type != "public":
            return {}
        return {
            "root_cause": (
                "Windows Bleak/WinRT auto-detected the ESP32-C3 devices with an unstable "
                "address type. Default connect and pair=True both disconnected after about "
                "0.37-0.47s, while iPhone nRF Connect held both devices for more than 5 seconds."
            ),
            "evidence": [
                "iPhone nRF Connect held XIAO-ESP32C3-LED-STOCK3 and STOCK4 for >5s.",
                "07_hold_connection_diag.py default connect disconnected after about 0.375-0.469s on STOCK3/STOCK4.",
                "07_hold_connection_diag.py with --address-type public stayed connected for 15.0s on both devices.",
            ],
            "resolution": [
                "Set config.WINRT_ADDRESS_TYPE = 'public'.",
                "Pass that WinRT address_type to BleakClient in gui_c3_state_check_dual.py and 07_hold_connection_diag.py.",
                "Keep Pair 2 staged connect and unexpected-disconnect cooldown logic as diagnostic guards.",
            ],
        }

    def _write_connection_failure_summary(self) -> None:
        updated_iso = datetime.now().isoformat(timespec="seconds")
        lines = [
            "ESP32-C3 BLE Connection Failure Summary",
            f"updated: {updated_iso}",
            f"log: {self._log_path}",
            f"csv: {self._csv_log_path}",
            "",
            "[Tracked Causes]",
        ]
        for failure_class in sorted(CONNECTION_FAILURE_NOTES):
            lines.append(f"- {failure_class}: {CONNECTION_FAILURE_NOTES[failure_class]}")
        lines.extend(["", "[Observed Failures]"])
        if not self._connection_failure_counter:
            lines.append("- none observed in this GUI session")
        else:
            for failure_class, count in self._connection_failure_counter.most_common():
                lines.append(f"- {failure_class}: count={count}")
                first_seen = self._connection_failure_first_seen.get(failure_class, "---")
                last_seen = self._connection_failure_last_seen.get(failure_class, "---")
                lines.append(f"  first_seen: {first_seen}")
                lines.append(f"  last_seen:  {last_seen}")
                detail = self._connection_failure_last_detail.get(
                    failure_class,
                    CONNECTION_FAILURE_NOTES.get(failure_class, ""),
                )
                if detail:
                    lines.append(f"  detail: {detail}")
                example = self._connection_failure_last_message.get(failure_class, "")
                if example:
                    lines.append(f"  latest_example: {example}")
        investigation = dict(self._investigation_summary)
        if investigation:
            lines.extend(["", "[Investigation Summary]"])
            root_cause = str(investigation.get("root_cause", "") or "").strip()
            if root_cause:
                lines.append(f"- Root cause: {root_cause}")
            for evidence in investigation.get("evidence", []):
                text = str(evidence).strip()
                if text:
                    lines.append(f"- Evidence: {text}")
            for resolution in investigation.get("resolution", []):
                text = str(resolution).strip()
                if text:
                    lines.append(f"- Resolution: {text}")
            result = str(investigation.get("result", "") or "").strip()
            if result:
                lines.append(f"- Result: {result}")
            investigation["updated"] = updated_iso
        state = {
            "updated": updated_iso,
            "counter": dict(self._connection_failure_counter),
            "first_seen": dict(self._connection_failure_first_seen),
            "last_seen": dict(self._connection_failure_last_seen),
            "last_detail": dict(self._connection_failure_last_detail),
            "last_message": dict(self._connection_failure_last_message),
            "investigation_summary": investigation,
        }
        self._failure_summary_state_path.write_text(
            json.dumps(state, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        self._failure_summary_path.write_text(
            "\n".join(lines) + "\n",
            encoding="utf-8",
        )

    def _load_connection_failure_summary_state(self) -> None:
        if not self._failure_summary_state_path.exists():
            return
        try:
            raw = json.loads(
                self._failure_summary_state_path.read_text(encoding="utf-8")
            )
        except Exception:
            return
        counter = raw.get("counter", {})
        if isinstance(counter, dict):
            for key, value in counter.items():
                try:
                    self._connection_failure_counter[str(key).upper()] = int(value)
                except Exception:
                    continue
        for attr_name, target in (
            ("first_seen", self._connection_failure_first_seen),
            ("last_seen", self._connection_failure_last_seen),
            ("last_detail", self._connection_failure_last_detail),
            ("last_message", self._connection_failure_last_message),
        ):
            data = raw.get(attr_name, {})
            if isinstance(data, dict):
                for key, value in data.items():
                    target[str(key).upper()] = str(value)
        investigation = raw.get("investigation_summary", {})
        if isinstance(investigation, dict) and investigation:
            merged = self._default_investigation_summary()
            merged.update(investigation)
            self._investigation_summary = merged

    # --------------------------- Logging ---------------------------
    def log(self, message: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] {message}"
        if hasattr(self, "log_view") and self.log_view is not None:
            self.log_view.appendPlainText(line)
            self.log_view.ensureCursorVisible()
        with self._log_path.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
        self._write_csv_log(message)
        detected = self._detect_connection_failure(message)
        if detected:
            failure_class, detail = detected
            self._record_connection_failure(
                failure_class,
                detail=detail,
                example=message,
            )

    def _write_csv_log(self, message: str) -> None:
        exists = self._csv_log_path.exists()
        with self._csv_log_path.open("a", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            if not exists:
                writer.writerow(["time", "message"])
            writer.writerow([datetime.now().isoformat(), message])

    def _run_async(self, coro: asyncio.Future) -> None:
        task = asyncio.create_task(coro)
        self._tasks.add(task)
        task.add_done_callback(lambda t: self._tasks.discard(t))

    def _show_error(self, message: str) -> None:
        self.log(f"[ERROR] {message}")
        QMessageBox.critical(self, "Error", message)

    def closeEvent(self, event) -> None:
        self._save_color_settings()
        for task in list(self._tasks):
            task.cancel()
        if self._auto_test_task:
            self._auto_test_task.cancel()
        if self._endurance_task:
            self._endurance_task.cancel()
        for task in list(self._color_heartbeat_tasks.values()):
            task.cancel()
        for task in list(self._pattern_tasks.values()):
            task.cancel()
        if self._logcat_worker:
            self._logcat_worker.stop()
        if self._serial_worker:
            self._serial_worker.stop()
        if self._serial_color_is_connected():
            self._serial_color_disconnect()
        if self._rssi_task and not self._rssi_task.done():
            self._rssi_task.cancel()
        self._tasks.clear()
        self._run_async(self._disconnect_both())
        super().closeEvent(event)


def main() -> None:
    app = QApplication.instance() or QApplication([])
    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    window = DualStateCheck()
    window.resize(1920, 1080)
    window.show()

    app.aboutToQuit.connect(loop.stop)
    with loop:
        loop.run_forever()


if __name__ == "__main__":
    main()
