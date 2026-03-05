#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Adafruit_NeoPixel.h>

#define DEVICE_NAME "XIAO-ESP32C3-LED-STOCK2"
#define BATTERY_LIFEPO4 1
#define FORCE_CLEAR_BONDS_AT_BOOT 0
// 0: test/debug friendly (no encrypted-write requirement), 1: strict security.
#define STRICT_BLE_SECURITY 0

static constexpr uint8_t FRONT_PIN = 5;
static constexpr uint8_t REAR_PIN = 6;
static constexpr uint8_t BATTERY_PIN = 3;
static constexpr uint8_t FRONT_COUNT = 12;
static constexpr uint8_t REAR_COUNT = 16;

static constexpr float BATTERY_DIVIDER_RATIO = 2.18f;
#if BATTERY_LIFEPO4
static constexpr uint16_t BATTERY_MIN_MV = 2500;
static constexpr uint16_t BATTERY_MAX_MV = 3800;
#else
static constexpr uint16_t BATTERY_MIN_MV = 3200;
static constexpr uint16_t BATTERY_MAX_MV = 4200;
#endif

static constexpr char kServiceUuid[] = "de8a5aac-a99b-c315-0c80-60d4cbb51001";
static constexpr char kCommandUuid[] = "de8a5aac-a99b-c315-0c80-60d4cbb51002";
static constexpr char kVoltageUuid[] = "de8a5aac-a99b-c315-0c80-60d4cbb51003";
static constexpr uint32_t kPairPasskey = 123456;

static constexpr uint8_t CMD_SET_BRIGHTNESS = 0x01;
static constexpr uint8_t CMD_START_RAINBOW = 0x03;
static constexpr uint8_t CMD_STOP_RAINBOW = 0x04;
static constexpr uint8_t CMD_ACCEL_MODE = 0x06;
static constexpr uint8_t CMD_SET_FRONT_COLOR = 0x07;
static constexpr uint8_t CMD_SET_REAR_COLOR = 0x08;
static constexpr uint8_t CMD_SET_OUTPUT_ENABLE = 0x09;
static constexpr uint8_t CMD_HEARTBEAT_MODE = 0x0A;
static constexpr uint8_t CMD_GPIO_TEST = 0x0B;
static constexpr uint8_t CMD_PATTERN_MODE = 0x0C;

struct Rgb {
  uint8_t r;
  uint8_t g;
  uint8_t b;
};

Adafruit_NeoPixel g_front_strip(FRONT_COUNT, FRONT_PIN, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel g_rear_strip(REAR_COUNT, REAR_PIN, NEO_GRB + NEO_KHZ800);
static NimBLEServer *g_server = nullptr;
static NimBLEAdvertising *g_adv = nullptr;
static bool g_has_trusted_peer = false;
static NimBLEAddress g_trusted_peer;

static String addr_to_upper(const NimBLEAddress &addr) {
  String mac = addr.toString().c_str();
  mac.toUpperCase();
  return mac;
}

static void refresh_whitelist_filter() {
#if !STRICT_BLE_SECURITY
  Serial.println("[STATE] WL_OPEN_INSECURE");
  return;
#endif
  if (g_has_trusted_peer) {
    Serial.print("[STATE] WL_LOCK ");
    Serial.println(addr_to_upper(g_trusted_peer));
  } else {
    Serial.println("[STATE] WL_OPEN");
  }
}

static void load_trusted_peer_from_bonds() {
#if !STRICT_BLE_SECURITY
  g_has_trusted_peer = false;
  Serial.println("[STATE] BOND_SKIP_INSECURE");
  return;
#endif
  const int bonds = NimBLEDevice::getNumBonds();
  if (bonds > 0) {
    g_trusted_peer = NimBLEDevice::getBondedAddress(0);
    g_has_trusted_peer = true;
    Serial.print("[STATE] BOND_LOAD ");
    Serial.println(addr_to_upper(g_trusted_peer));
  } else {
    g_has_trusted_peer = false;
    Serial.println("[STATE] BOND_EMPTY");
  }
}

static bool is_authorized_peer(const NimBLEConnInfo &connInfo) {
#if !STRICT_BLE_SECURITY
  (void)connInfo;
  return true;
#endif
  if (!g_has_trusted_peer) {
    return true;
  }
  if (!connInfo.isBonded() && !NimBLEDevice::isBonded(connInfo.getAddress())) {
    return false;
  }
  const int bonds = NimBLEDevice::getNumBonds();
  if (bonds <= 1) {
    return true;
  }
  return connInfo.getAddress() == g_trusted_peer;
}

static Rgb g_front_color = {255, 0, 0};
static Rgb g_rear_color = {0, 0, 255};
static Rgb g_fixed_color = {0, 180, 255};

static uint8_t g_brightness = 255;
static bool g_output_enabled = false;
static bool g_rainbow_mode = false;
static bool g_accel_mode = false;
static bool g_heartbeat_mode = false;

static uint16_t g_rainbow_interval_ms = 40;
static uint32_t g_last_rainbow_ms = 0;
static float g_rainbow_hue = 0.0f;

static uint32_t g_last_fixed_ms = 0;
static float g_breathe_phase = 0.0f;

static uint16_t g_heartbeat_bpm = 60;
static uint8_t g_heartbeat_color_index = 0;
static uint32_t g_last_heartbeat_ms = 0;
static bool g_heartbeat_on = false;

static bool g_pattern_mode = false;
static uint8_t g_pattern_id = 0;
static uint8_t g_pattern_zone_mask = 0x03;  // bit0=front, bit1=rear
static Rgb g_pattern_color = {255, 0, 0};
static uint16_t g_pattern_interval_ms = 120;
static uint32_t g_last_pattern_ms = 0;
static int16_t g_front_pos = 0;
static int16_t g_rear_pos = 0;
static int8_t g_front_dir = 1;
static int8_t g_rear_dir = 1;
static uint8_t g_pattern_step = 0;
static bool g_pattern_toggle = false;

static void apply_brightness() {
  g_front_strip.setBrightness(g_brightness);
  g_rear_strip.setBrightness(g_brightness);
}

static void set_all_no_show(Adafruit_NeoPixel &strip, uint32_t color) {
  const uint16_t count = strip.numPixels();
  for (uint16_t i = 0; i < count; ++i) {
    strip.setPixelColor(i, color);
  }
}

static void show_both() {
  g_front_strip.show();
  g_rear_strip.show();
}

static void clear_strips() {
  g_front_strip.clear();
  g_rear_strip.clear();
  show_both();
}

static Rgb hsv_to_rgb(float h, float s, float v) {
  while (h < 0.f) h += 360.f;
  while (h >= 360.f) h -= 360.f;
  const float c = v * s;
  const float x = c * (1.f - fabsf(fmodf(h / 60.f, 2.f) - 1.f));
  const float m = v - c;
  float r1 = 0.f;
  float g1 = 0.f;
  float b1 = 0.f;
  if (h < 60.f) {
    r1 = c; g1 = x; b1 = 0.f;
  } else if (h < 120.f) {
    r1 = x; g1 = c; b1 = 0.f;
  } else if (h < 180.f) {
    r1 = 0.f; g1 = c; b1 = x;
  } else if (h < 240.f) {
    r1 = 0.f; g1 = x; b1 = c;
  } else if (h < 300.f) {
    r1 = x; g1 = 0.f; b1 = c;
  } else {
    r1 = c; g1 = 0.f; b1 = x;
  }
  Rgb out;
  out.r = static_cast<uint8_t>((r1 + m) * 255.f);
  out.g = static_cast<uint8_t>((g1 + m) * 255.f);
  out.b = static_cast<uint8_t>((b1 + m) * 255.f);
  return out;
}

static Rgb scale_color(const Rgb &color, float scale) {
  const float s = scale < 0.f ? 0.f : (scale > 1.f ? 1.f : scale);
  Rgb out;
  out.r = static_cast<uint8_t>(color.r * s);
  out.g = static_cast<uint8_t>(color.g * s);
  out.b = static_cast<uint8_t>(color.b * s);
  return out;
}

static void show_solid() {
  apply_brightness();
  const uint32_t front = g_front_strip.Color(g_front_color.r, g_front_color.g, g_front_color.b);
  const uint32_t rear = g_rear_strip.Color(g_rear_color.r, g_rear_color.g, g_rear_color.b);
  set_all_no_show(g_front_strip, front);
  set_all_no_show(g_rear_strip, rear);
  show_both();
}

static void update_rainbow(uint32_t now_ms) {
  if (now_ms - g_last_rainbow_ms < g_rainbow_interval_ms) {
    return;
  }
  g_last_rainbow_ms = now_ms;
  g_rainbow_hue += 3.f;

  apply_brightness();
  for (uint16_t i = 0; i < FRONT_COUNT; ++i) {
    const float h = g_rainbow_hue + (360.f / FRONT_COUNT) * i;
    const Rgb c = hsv_to_rgb(h, 1.f, 1.f);
    g_front_strip.setPixelColor(i, g_front_strip.Color(c.r, c.g, c.b));
  }
  for (uint16_t i = 0; i < REAR_COUNT; ++i) {
    const float h = g_rainbow_hue + (360.f / REAR_COUNT) * i;
    const Rgb c = hsv_to_rgb(h, 1.f, 1.f);
    g_rear_strip.setPixelColor(i, g_rear_strip.Color(c.r, c.g, c.b));
  }
  show_both();
}

static void update_fixed_effect(uint32_t now_ms) {
  if (now_ms - g_last_fixed_ms < 20) {
    return;
  }
  g_last_fixed_ms = now_ms;
  g_breathe_phase += 0.08f;
  if (g_breathe_phase > 6.283185f) {
    g_breathe_phase -= 6.283185f;
  }
  const float wave = (sinf(g_breathe_phase) + 1.f) * 0.5f;
  const float scale = 0.15f + wave * 0.85f;
  const Rgb color = scale_color(g_fixed_color, scale);

  apply_brightness();
  const uint32_t packed = g_front_strip.Color(color.r, color.g, color.b);
  set_all_no_show(g_front_strip, packed);
  set_all_no_show(g_rear_strip, packed);
  show_both();
}

static Rgb heartbeat_color(uint8_t index) {
  switch (index) {
    case 1: return {25, 118, 210};
    case 2: return {123, 31, 162};
    case 3: return {255, 193, 7};
    case 4: return {76, 175, 80};
    default: return {255, 0, 0};
  }
}

static void update_heartbeat(uint32_t now_ms) {
  const uint16_t bpm = g_heartbeat_bpm < 30 ? 30 : g_heartbeat_bpm;
  const uint32_t interval = 60000UL / bpm / 2;
  if (now_ms - g_last_heartbeat_ms < interval) {
    return;
  }
  g_last_heartbeat_ms = now_ms;
  g_heartbeat_on = !g_heartbeat_on;

  apply_brightness();
  if (g_heartbeat_on) {
    const Rgb color = heartbeat_color(g_heartbeat_color_index);
    const uint32_t packed = g_front_strip.Color(color.r, color.g, color.b);
    set_all_no_show(g_front_strip, packed);
    set_all_no_show(g_rear_strip, packed);
  } else {
    set_all_no_show(g_front_strip, 0);
    set_all_no_show(g_rear_strip, 0);
  }
  show_both();
}

static void stop_modes() {
  g_rainbow_mode = false;
  g_accel_mode = false;
  g_heartbeat_mode = false;
  g_pattern_mode = false;
}

static void handle_output_enable(bool enabled) {
  g_output_enabled = enabled;
  if (!enabled) {
    stop_modes();
    clear_strips();
    return;
  }
  if (!g_rainbow_mode && !g_accel_mode && !g_heartbeat_mode && !g_pattern_mode) {
    show_solid();
  }
}

static void handle_front_color(uint8_t r, uint8_t g, uint8_t b) {
  g_front_color = {r, g, b};
  if (g_output_enabled && !g_rainbow_mode && !g_accel_mode && !g_heartbeat_mode && !g_pattern_mode) {
    show_solid();
  }
}

static void handle_rear_color(uint8_t r, uint8_t g, uint8_t b) {
  g_rear_color = {r, g, b};
  if (g_output_enabled && !g_rainbow_mode && !g_accel_mode && !g_heartbeat_mode && !g_pattern_mode) {
    show_solid();
  }
}

static void clear_strip_no_show(Adafruit_NeoPixel &strip) {
  const uint16_t count = strip.numPixels();
  for (uint16_t i = 0; i < count; ++i) {
    strip.setPixelColor(i, 0);
  }
}

static void render_scan_frame(Adafruit_NeoPixel &strip, int16_t pos, const Rgb &c) {
  const int n = static_cast<int>(strip.numPixels());
  if (n <= 0) return;
  clear_strip_no_show(strip);
  if (pos < 0) pos = 0;
  if (pos >= n) pos = n - 1;
  strip.setPixelColor(pos, strip.Color(c.r, c.g, c.b));
  if (pos - 1 >= 0) {
    const Rgb t = scale_color(c, 0.35f);
    strip.setPixelColor(pos - 1, strip.Color(t.r, t.g, t.b));
  }
  if (pos + 1 < n) {
    const Rgb t = scale_color(c, 0.35f);
    strip.setPixelColor(pos + 1, strip.Color(t.r, t.g, t.b));
  }
}

static void step_scan(int16_t &pos, int8_t &dir, int count, bool bounce) {
  if (count <= 0) return;
  pos += dir;
  if (bounce) {
    if (pos >= count - 1) {
      pos = count - 1;
      dir = -1;
    } else if (pos <= 0) {
      pos = 0;
      dir = 1;
    }
  } else {
    if (pos >= count) pos = 0;
    if (pos < 0) pos = count - 1;
  }
}

static void update_pattern_mode(uint32_t now_ms) {
  if (!g_pattern_mode) return;
  const uint16_t interval = g_pattern_interval_ms < 20 ? 20 : g_pattern_interval_ms;
  if (now_ms - g_last_pattern_ms < interval) return;
  g_last_pattern_ms = now_ms;
  apply_brightness();

  const bool front_on = (g_pattern_zone_mask & 0x01) != 0;
  const bool rear_on = (g_pattern_zone_mask & 0x02) != 0;
  const uint32_t front_c = g_front_strip.Color(g_pattern_color.r, g_pattern_color.g, g_pattern_color.b);
  const uint32_t rear_c = g_rear_strip.Color(g_pattern_color.r, g_pattern_color.g, g_pattern_color.b);

  switch (g_pattern_id) {
    case 1: { // Knight Rider
      if (front_on) render_scan_frame(g_front_strip, g_front_pos, g_pattern_color);
      else clear_strip_no_show(g_front_strip);
      if (rear_on) render_scan_frame(g_rear_strip, g_rear_pos, g_pattern_color);
      else clear_strip_no_show(g_rear_strip);
      step_scan(g_front_pos, g_front_dir, FRONT_COUNT, true);
      step_scan(g_rear_pos, g_rear_dir, REAR_COUNT, true);
      break;
    }
    case 2: { // Chase
      if (front_on) render_scan_frame(g_front_strip, g_front_pos, g_pattern_color);
      else clear_strip_no_show(g_front_strip);
      if (rear_on) render_scan_frame(g_rear_strip, g_rear_pos, g_pattern_color);
      else clear_strip_no_show(g_rear_strip);
      step_scan(g_front_pos, g_front_dir, FRONT_COUNT, false);
      step_scan(g_rear_pos, g_rear_dir, REAR_COUNT, false);
      break;
    }
    case 3: { // Wave
      clear_strip_no_show(g_front_strip);
      clear_strip_no_show(g_rear_strip);
      if (front_on) {
        for (uint16_t i = 0; i < FRONT_COUNT; ++i) {
          float phase = (float)(i + g_pattern_step) / (float)max<uint8_t>(1, FRONT_COUNT);
          float w = (sinf(phase * 6.283185f) + 1.0f) * 0.5f;
          Rgb c = scale_color(g_pattern_color, 0.2f + w * 0.8f);
          g_front_strip.setPixelColor(i, g_front_strip.Color(c.r, c.g, c.b));
        }
      }
      if (rear_on) {
        for (uint16_t i = 0; i < REAR_COUNT; ++i) {
          float phase = (float)(i + g_pattern_step) / (float)max<uint8_t>(1, REAR_COUNT);
          float w = (sinf(phase * 6.283185f) + 1.0f) * 0.5f;
          Rgb c = scale_color(g_pattern_color, 0.2f + w * 0.8f);
          g_rear_strip.setPixelColor(i, g_rear_strip.Color(c.r, c.g, c.b));
        }
      }
      g_pattern_step = (uint8_t)(g_pattern_step + 1);
      break;
    }
    case 4: { // Pulse
      float p = (sinf((float)g_pattern_step * 0.5f) + 1.0f) * 0.5f;
      Rgb c = scale_color(g_pattern_color, 0.15f + p * 0.85f);
      if (front_on) set_all_no_show(g_front_strip, g_front_strip.Color(c.r, c.g, c.b));
      else clear_strip_no_show(g_front_strip);
      if (rear_on) set_all_no_show(g_rear_strip, g_rear_strip.Color(c.r, c.g, c.b));
      else clear_strip_no_show(g_rear_strip);
      g_pattern_step = (uint8_t)(g_pattern_step + 1);
      break;
    }
    case 5: { // Breath
      float p = (sinf((float)g_pattern_step * 0.18f) + 1.0f) * 0.5f;
      Rgb c = scale_color(g_pattern_color, 0.05f + p * 0.95f);
      if (front_on) set_all_no_show(g_front_strip, g_front_strip.Color(c.r, c.g, c.b));
      else clear_strip_no_show(g_front_strip);
      if (rear_on) set_all_no_show(g_rear_strip, g_rear_strip.Color(c.r, c.g, c.b));
      else clear_strip_no_show(g_rear_strip);
      g_pattern_step = (uint8_t)(g_pattern_step + 1);
      break;
    }
    case 6: { // Strobe
      g_pattern_toggle = !g_pattern_toggle;
      if (front_on) set_all_no_show(g_front_strip, g_pattern_toggle ? front_c : 0);
      else clear_strip_no_show(g_front_strip);
      if (rear_on) set_all_no_show(g_rear_strip, g_pattern_toggle ? rear_c : 0);
      else clear_strip_no_show(g_rear_strip);
      break;
    }
    case 7: { // Blink
      g_pattern_toggle = !g_pattern_toggle;
      if (front_on) set_all_no_show(g_front_strip, g_pattern_toggle ? front_c : 0);
      else clear_strip_no_show(g_front_strip);
      if (rear_on) set_all_no_show(g_rear_strip, g_pattern_toggle ? rear_c : 0);
      else clear_strip_no_show(g_rear_strip);
      break;
    }
    default:
      g_pattern_mode = false;
      show_solid();
      return;
  }
  show_both();
}

static void handle_command(const uint8_t *data, size_t len) {
  if (!data || len == 0) return;
  switch (data[0]) {
    case CMD_SET_OUTPUT_ENABLE:
      if (len >= 2) {
        handle_output_enable(data[1] != 0);
      }
      break;
    case CMD_SET_BRIGHTNESS:
      if (len >= 2) {
        g_brightness = data[1];
        if (g_output_enabled && !g_rainbow_mode && !g_accel_mode && !g_heartbeat_mode && !g_pattern_mode) {
          show_solid();
        }
      }
      break;
    case CMD_SET_FRONT_COLOR:
      if (len >= 4) {
        handle_front_color(data[1], data[2], data[3]);
      }
      break;
    case CMD_SET_REAR_COLOR:
      if (len >= 4) {
        handle_rear_color(data[1], data[2], data[3]);
      }
      break;
    case CMD_START_RAINBOW:
      if (len >= 3) {
        g_rainbow_interval_ms = static_cast<uint16_t>(data[1] | (data[2] << 8));
        if (g_rainbow_interval_ms == 0) g_rainbow_interval_ms = 1;
      }
      g_rainbow_mode = true;
      g_accel_mode = false;
      g_heartbeat_mode = false;
      g_pattern_mode = false;
      break;
    case CMD_STOP_RAINBOW:
      g_rainbow_mode = false;
      if (g_output_enabled) {
        show_solid();
      }
      break;
    case CMD_ACCEL_MODE:
      if (len >= 2) {
        g_accel_mode = data[1] != 0;
        if (g_accel_mode) {
          g_rainbow_mode = false;
          g_heartbeat_mode = false;
          g_pattern_mode = false;
        } else if (g_output_enabled) {
          show_solid();
        }
      }
      break;
    case CMD_HEARTBEAT_MODE:
      if (len >= 4) {
        g_heartbeat_mode = data[1] != 0;
        g_heartbeat_bpm = data[2];
        g_heartbeat_color_index = data[3];
        g_heartbeat_on = false;
        g_last_heartbeat_ms = millis();
        if (g_heartbeat_mode) {
          g_rainbow_mode = false;
          g_accel_mode = false;
          g_pattern_mode = false;
        } else if (g_output_enabled) {
          show_solid();
        }
      }
      break;
    case CMD_PATTERN_MODE:
      if (len >= 2) {
        const bool enable = data[1] != 0;
        if (!enable) {
          g_pattern_mode = false;
          if (g_output_enabled) {
            show_solid();
          }
          break;
        }
        if (len < 9) {
          break;
        }
        g_pattern_id = data[2];
        g_pattern_zone_mask = data[3] & 0x03;
        if (g_pattern_zone_mask == 0) g_pattern_zone_mask = 0x03;
        g_pattern_color = {data[4], data[5], data[6]};
        g_pattern_interval_ms = static_cast<uint16_t>(data[7] | (data[8] << 8));
        if (g_pattern_interval_ms < 20) g_pattern_interval_ms = 20;
        g_pattern_mode = true;
        g_rainbow_mode = false;
        g_accel_mode = false;
        g_heartbeat_mode = false;
        g_pattern_step = 0;
        g_pattern_toggle = false;
        g_front_pos = 0;
        g_front_dir = 1;
        g_rear_pos = 0;
        g_rear_dir = 1;
        g_last_pattern_ms = 0;
      }
      break;
    case CMD_GPIO_TEST:
      if (len >= 3) {
        const uint8_t pin = data[1];
        const uint8_t value = data[2] ? HIGH : LOW;
        if (pin == 4 || pin == 5) {
          digitalWrite(pin, value);
        }
      }
      break;
    default:
      break;
  }
}

static void build_voltage_payload(uint8_t *payload) {
  const uint16_t raw = analogRead(BATTERY_PIN);
  const uint16_t mv = analogReadMilliVolts(BATTERY_PIN);
  payload[0] = static_cast<uint8_t>(raw & 0xFF);
  payload[1] = static_cast<uint8_t>((raw >> 8) & 0xFF);
  payload[2] = static_cast<uint8_t>(mv & 0xFF);
  payload[3] = static_cast<uint8_t>((mv >> 8) & 0xFF);
}

class CommandCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *ch, NimBLEConnInfo &connInfo) override {
#if STRICT_BLE_SECURITY
    if (!connInfo.isEncrypted()) {
      Serial.println("[STATE] REJECT_UNENCRYPTED_WRITE");
      return;
    }
#endif
    const std::string value = ch->getValue();
    handle_command(reinterpret_cast<const uint8_t *>(value.data()), value.size());
  }
};

class VoltageCallbacks : public NimBLECharacteristicCallbacks {
  void onRead(NimBLECharacteristic *ch, NimBLEConnInfo &connInfo) override {
#if STRICT_BLE_SECURITY
    if (!connInfo.isEncrypted()) {
      Serial.println("[STATE] REJECT_UNENCRYPTED_READ");
      return;
    }
#endif
    uint8_t payload[4] = {0};
    build_voltage_payload(payload);
    ch->setValue(payload, sizeof(payload));
  }
};

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *server, NimBLEConnInfo &connInfo) override {
    if (!is_authorized_peer(connInfo)) {
      Serial.print("[STATE] REJECT_CONN ");
      Serial.println(addr_to_upper(connInfo.getAddress()));
      server->disconnect(connInfo.getConnHandle());
      return;
    }
    Serial.print("[STATE] CONNECTED ");
    Serial.println(addr_to_upper(connInfo.getAddress()));
  }

  void onDisconnect(NimBLEServer *server, NimBLEConnInfo &connInfo, int reason) override {
    (void)server;
    Serial.print("[STATE] DISCONNECTED ");
    Serial.print(addr_to_upper(connInfo.getAddress()));
    Serial.print(" reason=0x");
    Serial.println(reason, HEX);
    handle_output_enable(false);
    NimBLEDevice::startAdvertising();
  }

  uint32_t onPassKeyDisplay() override {
    Serial.print("[STATE] PASSKEY ");
    Serial.println(kPairPasskey);
    return kPairPasskey;
  }

  void onAuthenticationComplete(NimBLEConnInfo &connInfo) override {
#if STRICT_BLE_SECURITY
    if (!connInfo.isEncrypted()) {
      Serial.println("[STATE] AUTH_FAIL_NO_ENC");
      if (g_server) {
        g_server->disconnect(connInfo.getConnHandle());
      }
      return;
    }
#endif
    if (!g_has_trusted_peer && connInfo.isBonded()) {
      g_trusted_peer = connInfo.getAddress();
      g_has_trusted_peer = true;
      Serial.print("[STATE] TRUST_SET ");
      Serial.println(addr_to_upper(g_trusted_peer));
      refresh_whitelist_filter();
      return;
    }
    if (!is_authorized_peer(connInfo)) {
      Serial.println("[STATE] AUTH_REJECT_NOT_TRUSTED");
      if (g_server) {
        g_server->disconnect(connInfo.getConnHandle());
      }
      return;
    }
    Serial.println("[STATE] AUTH_OK");
  }
};

void setup() {
  Serial.begin(115200);

  pinMode(4, OUTPUT);
  pinMode(5, OUTPUT);
  digitalWrite(4, LOW);
  digitalWrite(5, LOW);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(BATTERY_PIN, INPUT);
  analogRead(BATTERY_PIN);

  g_front_strip.begin();
  g_rear_strip.begin();
  g_front_strip.clear();
  g_rear_strip.clear();
  show_both();

  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
#if STRICT_BLE_SECURITY
  NimBLEDevice::setSecurityAuth(true, false, true);
  NimBLEDevice::setSecurityIOCap(3);  // BLE_HS_IO_NO_INPUT_OUTPUT
  NimBLEDevice::setSecurityPasskey(kPairPasskey);
#if FORCE_CLEAR_BONDS_AT_BOOT
  NimBLEDevice::deleteAllBonds();
  Serial.println("[STATE] BOND_CLEAR_BOOT");
#endif
#else
  NimBLEDevice::setSecurityAuth(false, false, false);
  NimBLEDevice::deleteAllBonds();
  Serial.println("[STATE] BOND_CLEAR_INSECURE_BOOT");
#endif

  g_server = NimBLEDevice::createServer();
  g_server->setCallbacks(new ServerCallbacks());

  NimBLEService *service = g_server->createService(kServiceUuid);
#if STRICT_BLE_SECURITY
  NimBLECharacteristic *cmd = service->createCharacteristic(
      kCommandUuid,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR |
      NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::WRITE_AUTHEN);
  NimBLECharacteristic *voltage = service->createCharacteristic(
      kVoltageUuid,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC |
      NIMBLE_PROPERTY::READ_AUTHEN | NIMBLE_PROPERTY::NOTIFY);
#else
  NimBLECharacteristic *cmd = service->createCharacteristic(
      kCommandUuid,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  NimBLECharacteristic *voltage = service->createCharacteristic(
      kVoltageUuid,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
#endif

  cmd->setCallbacks(new CommandCallbacks());
  voltage->setCallbacks(new VoltageCallbacks());
  service->start();

  g_adv = NimBLEDevice::getAdvertising();
  g_adv->setName(DEVICE_NAME);
  g_adv->addServiceUUID(service->getUUID());
  g_adv->enableScanResponse(true);
  load_trusted_peer_from_bonds();
  refresh_whitelist_filter();
  g_adv->start();
}

void loop() {
  const uint32_t now = millis();
  if (!g_output_enabled) {
    delay(10);
    return;
  }
  if (g_pattern_mode) {
    update_pattern_mode(now);
  } else if (g_heartbeat_mode) {
    update_heartbeat(now);
  } else if (g_rainbow_mode) {
    update_rainbow(now);
  } else if (g_accel_mode) {
    update_fixed_effect(now);
  }
  delay(10);
}
