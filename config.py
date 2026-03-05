# ==== BLE LED 共通設定 ====
TARGET_NAME     = "XIAO-MG24-LED"   # 端末名でスキャンする場合
TARGET_ADDR     = None              # 固定接続したい場合: "AA:BB:CC:DD:EE:FF"

# Immediate Alert (0x1802 / 0x2A06)
SVC_UUID        = "00001802-0000-1000-8000-00805f9b34fb"
CHR_UUID        = "00002a06-0000-1000-8000-00805f9b34fb"

# 拡張制御 (輝度・色・エフェクト)
ADV_SVC_UUID    = "de8a5aac-a99b-c315-0c80-60d4cbb51001"
ADV_CHR_UUID    = "de8a5aac-a99b-c315-0c80-60d4cbb51002"
VOLTAGE_CHR_UUID = "de8a5aac-a99b-c315-0c80-60d4cbb51003"

WRITE_RESPONSE  = True              # True: Write Request, False: Write Command
SCAN_TIMEOUT    = 8.0               # [s]
CONNECT_TIMEOUT = 15.0              # [s]
WINRT_ADDRESS_TYPE = "public"      # Windows C3 devices are stable with public address type
WINRT_USE_CACHED_SERVICES = None    # None=library default, True/False to force

# 必要なら任意の書き込みキャラクタリスティックを上書き
# WRITE_CHAR_UUID = CHR_UUID
