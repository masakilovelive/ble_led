#include <Arduino.h>
#include <Wire.h>
#include <LSM6DS3.h>
#include "firmware_versions.h"
extern "C" {
  #include "em_gpio.h"
  #include "em_cmu.h"
  #include "sl_bt_api.h"
  #include "app_assert.h"
}
#include <core_cm33.h>

#if !defined(ARDUINO_SILABS_STACK_BLE_SILABS)
#error "Tools → Protocol Stack で『BLE (SiLabs BGAPI)』を選択してください。"
#endif

// -------------------- BLE command codes --------------------
static constexpr uint8_t CMD_SET_BRIGHTNESS = 0x01;
static constexpr uint8_t CMD_SET_COLOR      = 0x02;
static constexpr uint8_t CMD_START_RAINBOW  = 0x03;
static constexpr uint8_t CMD_STOP_RAINBOW   = 0x04;
static constexpr uint8_t CMD_ACCEL_MODE     = 0x06;  // payload: 0x00=off, 0x01=on
static constexpr uint8_t CMD_SET_FRONT_COLOR = 0x07;
static constexpr uint8_t CMD_SET_REAR_COLOR  = 0x08;
static constexpr uint8_t CMD_SET_OUTPUT_ENABLE = 0x09;

static const char *FIRMWARE_NAME = "xiao_mg24_ble_alert_led";
static const char *DEVICE_NAME = "XIAO-MG24-LED";
static const uint8_t GENERIC_ACCESS_UUID_16[2] = { 0x00, 0x18 };
static const uint8_t IMMEDIATE_ALERT_UUID_16[2] = { 0x02, 0x18 };
static const sl_bt_uuid_16_t ALERT_LEVEL_UUID = { .data = { 0x06, 0x2A } };
static const uint8_t SERVICE_UUID_128[16] = {
  0x01, 0x10, 0xb5, 0xcb, 0xd4, 0x60, 0x80, 0x0c,
  0x15, 0xc3, 0x9b, 0xa9, 0xac, 0x5a, 0x8a, 0xde
};
static const uuid_128 kLedAdvServiceUuid = {
  .data = { 0x01, 0x10, 0xb5, 0xcb, 0xd4, 0x60, 0x80, 0x0c,
            0x15, 0xc3, 0x9b, 0xa9, 0xac, 0x5a, 0x8a, 0xde }
};
static const uuid_128 kLedAdvCharUuid = {
  .data = { 0x02, 0x10, 0xb5, 0xcb, 0xd4, 0x60, 0x80, 0x0c,
            0x15, 0xc3, 0x9b, 0xa9, 0xac, 0x5a, 0x8a, 0xde }
};

// -------------------- LED strip configuration --------------------
static constexpr uint8_t LED_COUNT = 8;      // adjust if必要
static constexpr uint8_t FRONT_REAR_COUNT = 8;
static constexpr uint8_t WS_PIN = 3;        // PA3 == D8
static constexpr uint8_t WS_PORT_PIN = WS_PIN;
static constexpr GPIO_Port_TypeDef WS_PORT = gpioPortA;
static constexpr uint8_t FRONT_PIN = 9;     // D9
static constexpr uint8_t REAR_PIN = 10;     // D10
static constexpr GPIO_Port_TypeDef FRONT_PORT = gpioPortA; // D9 -> PA4
static constexpr uint8_t FRONT_PORT_PIN = 4;
static constexpr GPIO_Port_TypeDef REAR_PORT = gpioPortA;  // D10 -> PA5
static constexpr uint8_t REAR_PORT_PIN = 5;

struct RGB { uint8_t r, g, b; };
static RGB leds[LED_COUNT];
static uint8_t g_brightness = 160;
static bool g_led_enabled = false;
static bool g_rainbow_mode = false;
static bool g_accel_mode = false;
static bool g_idle_frame = false;
static RGB g_solid_color {255, 120, 40};
static RGB g_front_color {0, 0, 0};
static RGB g_rear_color {0, 0, 0};
static bool g_front_dirty = true;
static bool g_rear_dirty = true;
static bool g_output_enabled = false;

// Rainbow state
static float g_rainbow_hue = 0.f;
static uint32_t g_last_rainbow_ms = 0;

// BLE handles
static uint8_t adv_handle = 0xFF;
static uint8_t g_connection = SL_BT_INVALID_CONNECTION_HANDLE;
static uint16_t gattdb_session_id = 0;
static uint16_t generic_access_service_handle = 0;
static uint16_t name_characteristic_handle = 0;
static uint16_t immediate_alert_service_handle = 0;
static uint16_t alert_level_characteristic_handle = 0;
static uint16_t led_adv_service_handle = 0;
static uint16_t led_adv_char_handle = 0;

static inline bool has_active_connection() {
  return g_connection != SL_BT_INVALID_CONNECTION_HANDLE;
}

// -------------------- IMU --------------------
static constexpr uint8_t IMU_EN_PIN = 5; // PD5
static constexpr uint8_t IMU_ADDR = 0x6A;
LSM6DS3 imu(I2C_MODE, IMU_ADDR);
static bool g_imu_ready = false;
static float g_tilt_lp = 0.2f;
static float g_acc_lp = 0.0f;
static int g_knight_pos = 0;
static int g_knight_dir = 1;
static uint32_t g_knight_last_ms = 0;

// -------------------- WS2812 timing --------------------
static inline void dwt_init() {
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  DWT->CYCCNT = 0;
  DWT->CTRL  |= DWT_CTRL_CYCCNTENA_Msk;
}
static inline void wait_cyc(uint32_t target_cycles) {
  uint32_t start = DWT->CYCCNT;
  while ((uint32_t)(DWT->CYCCNT - start) < target_cycles) {}
}
static inline uint32_t ns_to_cycles(uint32_t ns) {
  return (uint32_t)(((uint64_t)F_CPU * ns) / 1000000000ULL);
}

static uint32_t C1H, C1L, C0H, C0L;
static uint32_t g_TTOTAL_ns = 1250;
static uint32_t g_T1H_ns = 800;
static uint32_t g_T0H_ns = 200;
static uint32_t g_TRESET_us = 300;

static void refresh_cycles() {
  C1H = ns_to_cycles(g_T1H_ns);
  C1L = ns_to_cycles(g_TTOTAL_ns - g_T1H_ns);
  C0H = ns_to_cycles(g_T0H_ns);
  C0L = ns_to_cycles(g_TTOTAL_ns - g_T0H_ns);
}

static inline void ws_bit_port(GPIO_Port_TypeDef port, uint8_t pin, bool one) {
  uint32_t start = DWT->CYCCNT;
  GPIO_PinOutSet(port, pin);
  wait_cyc(one ? C1H : C0H);
  GPIO_PinOutClear(port, pin);
  start = DWT->CYCCNT;
  wait_cyc(one ? C1L : C0L);
}
static inline void ws_bit(bool one) {
  ws_bit_port(WS_PORT, WS_PORT_PIN, one);
}
static inline void ws_byte_port(GPIO_Port_TypeDef port, uint8_t pin, uint8_t v) {
  for (int i = 7; i >= 0; --i) ws_bit_port(port, pin, (v >> i) & 1);
}
static inline void ws_byte(uint8_t v) {
  for (int i = 7; i >= 0; --i) ws_bit((v >> i) & 1);
}
static inline void ws_grb_port(GPIO_Port_TypeDef port, uint8_t pin, uint8_t g, uint8_t r, uint8_t b) {
  ws_byte_port(port, pin, g);
  ws_byte_port(port, pin, r);
  ws_byte_port(port, pin, b);
}
static inline void ws_grb(uint8_t g, uint8_t r, uint8_t b) {
  ws_byte(g); ws_byte(r); ws_byte(b);
}

static void ws_show() {
  noInterrupts();
  for (uint8_t i = 0; i < LED_COUNT; ++i) {
    uint16_t r = (uint16_t)leds[i].r * g_brightness / 255;
    uint16_t g = (uint16_t)leds[i].g * g_brightness / 255;
    uint16_t b = (uint16_t)leds[i].b * g_brightness / 255;
    ws_grb((uint8_t)g, (uint8_t)r, (uint8_t)b);
  }
  interrupts();
  delayMicroseconds(g_TRESET_us);
}
static void ws_clear(uint8_t repeats = 2) {
  for (auto &p : leds) p = {0, 0, 0};
  for (uint8_t i = 0; i < repeats; ++i) ws_show();
}

// -------------------- Color helpers --------------------
static RGB hsv_to_rgb(float h, float s, float v) {
  while (h < 0.f) h += 360.f;
  while (h >= 360.f) h -= 360.f;
  float c = v * s;
  float x = c * (1.f - fabsf(fmodf(h / 60.f, 2.f) - 1.f));
  float m = v - c;
  float r1, g1, b1;
  if (h < 60.f)      { r1 = c; g1 = x; b1 = 0; }
  else if (h < 120.f){ r1 = x; g1 = c; b1 = 0; }
  else if (h < 180.f){ r1 = 0; g1 = c; b1 = x; }
  else if (h < 240.f){ r1 = 0; g1 = x; b1 = c; }
  else if (h < 300.f){ r1 = x; g1 = 0; b1 = c; }
  else               { r1 = c; g1 = 0; b1 = x; }
  RGB out;
  out.r = (uint8_t)roundf((r1 + m) * 255.f);
  out.g = (uint8_t)roundf((g1 + m) * 255.f);
  out.b = (uint8_t)roundf((b1 + m) * 255.f);
  return out;
}

static void fill_all(const RGB &color) {
  for (auto &p : leds) p = color;
}

static inline void mark_led_active() {
  g_idle_frame = false;
}

static void force_led_off(bool allow_output) {
  if (!g_led_enabled && !g_rainbow_mode && !g_accel_mode && g_idle_frame) {
    return;
  }
  g_led_enabled = false;
  g_rainbow_mode = false;
  g_accel_mode = false;
  g_knight_pos = 0;
  g_knight_dir = 1;
  fill_all({0, 0, 0});
  GPIO_PinOutClear(WS_PORT, WS_PORT_PIN);
  GPIO_PinOutClear(FRONT_PORT, FRONT_PORT_PIN);
  GPIO_PinOutClear(REAR_PORT, REAR_PORT_PIN);
  set_front_color(0, 0, 0);
  set_rear_color(0, 0, 0);
  if (allow_output) {
    ws_show();
    update_front_rear();
  }
  g_idle_frame = true;
}

static inline bool output_allowed() {
  return g_output_enabled;
}

// -------------------- IMU helpers --------------------
static bool imu_begin() {
  pinMode(IMU_EN_PIN, OUTPUT);
  digitalWrite(IMU_EN_PIN, HIGH);
  delay(10);
  Wire.begin();
  Wire.setClock(400000);
  if (imu.begin() != 0) {
    return false;
  }
  imu.settings.accelEnabled = 1;
  imu.settings.accelRange = 2;   // ±2g
  imu.settings.accelSampleRate = 104;
  imu.settings.accelBandWidth = 100;
  imu.begin();
  return true;
}

static bool imu_read(float &ax, float &ay, float &az) {
  if (!g_imu_ready) return false;
  ax = imu.readFloatAccelX();
  ay = imu.readFloatAccelY();
  az = imu.readFloatAccelZ();
  if (!isfinite(ax) || !isfinite(ay) || !isfinite(az)) return false;
  return true;
}

static void update_accel_effect(uint32_t now_ms) {
  float ax, ay, az;
  if (!imu_read(ax, ay, az)) {
    fill_all({0, 0, 0});
    return;
  }
  float tilt_mag = sqrtf(ax * ax + ay * ay);
  g_tilt_lp = 0.9f * g_tilt_lp + 0.1f * tilt_mag;
  float brightness = constrain(0.15f + g_tilt_lp * 0.8f, 0.1f, 1.0f);

  float heading = atan2f(ay, ax) * 180.0f / PI; // -180..180
  heading += 180.f;
  RGB base = hsv_to_rgb(heading, 0.9f, brightness * 0.6f + 0.2f);

  float accel_total = sqrtf(ax * ax + ay * ay + az * az);
  g_acc_lp = 0.85f * g_acc_lp + 0.15f * fabsf(accel_total - 1.0f);
  uint32_t interval = (uint32_t)constrain(140.f - g_acc_lp * 120.f, 35.f, 220.f);
  if (now_ms - g_knight_last_ms >= interval) {
    g_knight_last_ms = now_ms;
    g_knight_pos += g_knight_dir;
    if (g_knight_pos >= LED_COUNT - 1) { g_knight_pos = LED_COUNT - 1; g_knight_dir = -1; }
    else if (g_knight_pos <= 0)      { g_knight_pos = 0;              g_knight_dir = 1;  }
  }

  fill_all(base);
  for (int offset = -3; offset <= 3; ++offset) {
    int idx = g_knight_pos + offset;
    if (idx < 0 || idx >= LED_COUNT) continue;
    float weight = 1.0f - (fabsf((float)offset) / 3.0f);
    weight = constrain(weight, 0.f, 1.f);
    uint8_t boost = (uint8_t)roundf(255.f * brightness * weight);
    leds[idx].r = constrain((int)leds[idx].r + boost, 0, 255);
    leds[idx].g = constrain((int)leds[idx].g + boost / 4, 0, 255);
    leds[idx].b = constrain((int)leds[idx].b + boost / 6, 0, 255);
  }
}

static void update_rainbow(uint32_t now_ms) {
  if (!g_led_enabled) return;
  if (now_ms - g_last_rainbow_ms >= 30) {
    g_last_rainbow_ms = now_ms;
    g_rainbow_hue += 3.f;
  }
  for (uint8_t i = 0; i < LED_COUNT; ++i) {
    float h = g_rainbow_hue + (360.f / LED_COUNT) * i;
    leds[i] = hsv_to_rgb(h, 1.0f, 1.0f);
  }
}

static void update_solid() {
  fill_all(g_solid_color);
}

static void set_front_color(uint8_t r, uint8_t g, uint8_t b) {
  g_front_color = { r, g, b };
  g_front_dirty = true;
}

static void set_rear_color(uint8_t r, uint8_t g, uint8_t b) {
  g_rear_color = { r, g, b };
  g_rear_dirty = true;
}

static void update_front_rear() {
  if (!g_front_dirty && !g_rear_dirty) {
    return;
  }
  noInterrupts();
  if (g_front_dirty) {
    for (uint8_t i = 0; i < FRONT_REAR_COUNT; ++i) {
      ws_grb_port(FRONT_PORT, FRONT_PORT_PIN, g_front_color.g, g_front_color.r, g_front_color.b);
    }
    g_front_dirty = false;
  }
  if (g_rear_dirty) {
    for (uint8_t i = 0; i < FRONT_REAR_COUNT; ++i) {
      ws_grb_port(REAR_PORT, REAR_PORT_PIN, g_rear_color.g, g_rear_color.r, g_rear_color.b);
    }
    g_rear_dirty = false;
  }
  interrupts();
  delayMicroseconds(g_TRESET_us);
}

// -------------------- BLE helpers --------------------
static void set_led_enabled(bool on) {
  if (on) {
    g_led_enabled = true;
    mark_led_active();
    return;
  }
  force_led_off(g_output_enabled);
}

static void set_accel_mode(bool enable) {
  if (enable) {
    if (!g_imu_ready || !has_active_connection()) {
      g_accel_mode = false;
      return;
    }
    if (g_accel_mode) {
      return;
    }
    g_accel_mode = true;
    g_led_enabled = true;
    mark_led_active();
    g_knight_pos = 0;
    g_knight_dir = 1;
    g_knight_last_ms = millis();
    g_tilt_lp = 0.2f;
    g_acc_lp = 0.f;
    return;
  }

  if (!g_accel_mode) {
    return;
  }
  g_accel_mode = false;
  g_knight_pos = 0;
  g_knight_dir = 1;
  g_knight_last_ms = millis();
}

static void apply_alert_level(uint8_t level) {
  if (level >= 1) {
    set_led_enabled(true);
  } else {
    set_led_enabled(false);
    set_accel_mode(false);
  }
}

static void handle_led_command(const uint8_t *data, uint16_t len) {
  if (!data || len == 0) return;
  if (data[0] == CMD_SET_OUTPUT_ENABLE) {
    if (len >= 2) {
      bool enable = data[1] != 0;
      bool was_enabled = g_output_enabled;
      if (!enable) {
        g_output_enabled = false;
        if (was_enabled) {
          force_led_off(true);
        }
      } else {
        g_output_enabled = true;
      }
    }
    return;
  }
  switch (data[0]) {
    case CMD_SET_BRIGHTNESS:
      if (len >= 2) {
        g_brightness = constrain(data[1], (uint8_t)0, (uint8_t)255);
        set_led_enabled(true);
      }
      break;
    case CMD_SET_COLOR:
      if (len >= 4) {
        g_solid_color = { data[1], data[2], data[3] };
        set_led_enabled(true);
        g_rainbow_mode = false;
        set_accel_mode(false);
      }
      break;
    case CMD_START_RAINBOW:
      set_led_enabled(true);
      g_rainbow_mode = true;
      set_accel_mode(false);
      g_last_rainbow_ms = millis();
      break;
    case CMD_STOP_RAINBOW:
      g_rainbow_mode = false;
      break;
    case CMD_ACCEL_MODE:
      if (len >= 2) {
        bool enable = data[1] != 0;
        set_accel_mode(enable);
      }
      break;
    case CMD_SET_FRONT_COLOR:
      if (len >= 4) {
        set_front_color(data[1], data[2], data[3]);
      }
      break;
    case CMD_SET_REAR_COLOR:
      if (len >= 4) {
        set_rear_color(data[1], data[2], data[3]);
      }
      break;
    default:
      break;
  }
}

// -------------------- Serial (debug) --------------------
static void print_help() {
  Serial.println(F("Commands: HELP, VER, ON, OFF, BR xx, COLOR r g b, FRONT r g b, REAR r g b, ACCEL 0|1"));
}

static void print_version() {
  Serial.print(F("Firmware: "));
  Serial.print(FIRMWARE_NAME);
  Serial.print(F(" v"));
  Serial.println(FW_VERSION_ALERT_LED);
}

static void handle_serial() {
  if (!Serial.available()) return;
  String line = Serial.readStringUntil('\n');
  line.trim();
  line.toUpperCase();
  if (line == "HELP") {
    print_help();
  } else if (line == "VER" || line == "VERSION") {
    print_version();
  } else if (line == "ON") {
    set_led_enabled(true);
  } else if (line == "OFF") {
    set_led_enabled(false);
  } else if (line.startsWith("BR")) {
    int value = line.substring(2).toInt();
    g_brightness = constrain(value, 0, 255);
    set_led_enabled(true);
  } else if (line.startsWith("COLOR")) {
    int r, g, b;
    if (sscanf(line.c_str(), "COLOR %d %d %d", &r, &g, &b) == 3) {
      g_solid_color = { (uint8_t)constrain(r,0,255), (uint8_t)constrain(g,0,255), (uint8_t)constrain(b,0,255) };
      set_led_enabled(true);
      g_rainbow_mode = false;
      set_accel_mode(false);
    }
  } else if (line.startsWith("FRONT")) {
    int r, g, b;
    if (sscanf(line.c_str(), "FRONT %d %d %d", &r, &g, &b) == 3) {
      set_front_color((uint8_t)constrain(r,0,255), (uint8_t)constrain(g,0,255), (uint8_t)constrain(b,0,255));
    }
  } else if (line.startsWith("REAR")) {
    int r, g, b;
    if (sscanf(line.c_str(), "REAR %d %d %d", &r, &g, &b) == 3) {
      set_rear_color((uint8_t)constrain(r,0,255), (uint8_t)constrain(g,0,255), (uint8_t)constrain(b,0,255));
    }
  } else if (line.startsWith("ACCEL")) {
    int v = line.substring(5).toInt();
    set_accel_mode(v != 0);
  }
}

// -------------------- BLE advertisement helpers --------------------
static void set_scan_response_name(uint8_t handle, const char *name) {
  size_t n = strlen(name);
  if (n > 29) n = 29;
  uint8_t buf[31];
  uint8_t len = 0;
  buf[len++] = 1 + n;
  buf[len++] = 0x09;
  memcpy(&buf[len], name, n);
  len += n;
  sl_bt_legacy_advertiser_set_data(handle, sl_bt_advertiser_scan_response_packet, len, buf);
}

static void start_normal_advertising();

// -------------------- GATT initialisation --------------------
static void initialize_gatt_db() {
  sl_status_t sc = sl_bt_gattdb_new_session(&gattdb_session_id);
  app_assert_status(sc);

  sc = sl_bt_gattdb_add_service(gattdb_session_id,
                                sl_bt_gattdb_primary_service,
                                SL_BT_GATTDB_ADVERTISED_SERVICE,
                                sizeof(GENERIC_ACCESS_UUID_16),
                                GENERIC_ACCESS_UUID_16,
                                &generic_access_service_handle);
  app_assert_status(sc);

  const sl_bt_uuid_16_t device_name_uuid = { .data = { 0x00, 0x2A } };
  sc = sl_bt_gattdb_add_uuid16_characteristic(gattdb_session_id,
                                              generic_access_service_handle,
                                              SL_BT_GATTDB_CHARACTERISTIC_READ,
                                              0, 0,
                                              device_name_uuid,
                                              sl_bt_gattdb_fixed_length_value,
                                              strlen(DEVICE_NAME), strlen(DEVICE_NAME),
                                              reinterpret_cast<const uint8_t *>(DEVICE_NAME),
                                              &name_characteristic_handle);
  app_assert_status(sc);
  sc = sl_bt_gattdb_start_service(gattdb_session_id, generic_access_service_handle);
  app_assert_status(sc);

  sc = sl_bt_gattdb_add_service(gattdb_session_id,
                                sl_bt_gattdb_primary_service,
                                SL_BT_GATTDB_ADVERTISED_SERVICE,
                                sizeof(IMMEDIATE_ALERT_UUID_16),
                                IMMEDIATE_ALERT_UUID_16,
                                &immediate_alert_service_handle);
  app_assert_status(sc);

  uint8_t init_alert = 0;
  sc = sl_bt_gattdb_add_uuid16_characteristic(gattdb_session_id,
                                              immediate_alert_service_handle,
                                              SL_BT_GATTDB_CHARACTERISTIC_WRITE | SL_BT_GATTDB_CHARACTERISTIC_WRITE_NO_RESPONSE,
                                              0, 0,
                                              ALERT_LEVEL_UUID,
                                              sl_bt_gattdb_fixed_length_value,
                                              1, sizeof(init_alert), &init_alert,
                                              &alert_level_characteristic_handle);
  app_assert_status(sc);
  sc = sl_bt_gattdb_start_service(gattdb_session_id, immediate_alert_service_handle);
  app_assert_status(sc);

  uint8_t init_cmd = 0;
  sc = sl_bt_gattdb_add_service(gattdb_session_id,
                                sl_bt_gattdb_primary_service,
                                SL_BT_GATTDB_ADVERTISED_SERVICE,
                                sizeof(kLedAdvServiceUuid.data),
                                kLedAdvServiceUuid.data,
                                &led_adv_service_handle);
  app_assert_status(sc);

  sc = sl_bt_gattdb_add_uuid128_characteristic(gattdb_session_id,
                                               led_adv_service_handle,
                                               SL_BT_GATTDB_CHARACTERISTIC_WRITE | SL_BT_GATTDB_CHARACTERISTIC_WRITE_NO_RESPONSE,
                                               0, 0,
                                               kLedAdvCharUuid,
                                               sl_bt_gattdb_variable_length_value,
                                               32,
                                               sizeof(init_cmd), &init_cmd,
                                               &led_adv_char_handle);
  app_assert_status(sc);
  sc = sl_bt_gattdb_start_service(gattdb_session_id, led_adv_service_handle);
  app_assert_status(sc);

  sc = sl_bt_gattdb_commit(gattdb_session_id);
  app_assert_status(sc);
}

// -------------------- Advertising --------------------
static void start_normal_advertising() {
  sl_bt_advertiser_set_timing(adv_handle, 160, 240, 0, 0);
  uint8_t adv[31];
  uint8_t len = 0;
  adv[len++] = 0x02; adv[len++] = 0x01; adv[len++] = 0x06;
  adv[len++] = 1 + 16; adv[len++] = 0x07;
  memcpy(&adv[len], SERVICE_UUID_128, 16); len += 16;
  size_t name_len = strlen(DEVICE_NAME);
  if (name_len > 20) name_len = 20;
  adv[len++] = 1 + name_len; adv[len++] = 0x08;
  memcpy(&adv[len], DEVICE_NAME, name_len); len += name_len;
  sl_bt_legacy_advertiser_set_data(adv_handle, sl_bt_advertiser_advertising_data_packet, len, adv);
  set_scan_response_name(adv_handle, DEVICE_NAME);
  sl_bt_legacy_advertiser_start(adv_handle, sl_bt_legacy_advertiser_connectable);
}

// -------------------- Arduino lifecycle --------------------
void setup() {
  Serial.begin(115200);
  delay(100);
  print_version();
  print_help();

  CMU_ClockEnable(cmuClock_GPIO, true);
  GPIO_PinModeSet(WS_PORT, WS_PORT_PIN, gpioModePushPull, 0);
  GPIO_PinModeSet(FRONT_PORT, FRONT_PORT_PIN, gpioModePushPull, 0);
  GPIO_PinModeSet(REAR_PORT, REAR_PORT_PIN, gpioModePushPull, 0);
  GPIO_PinOutClear(FRONT_PORT, FRONT_PORT_PIN);
  GPIO_PinOutClear(REAR_PORT, REAR_PORT_PIN);
  dwt_init();
  refresh_cycles();
  ws_clear(3);
  g_output_enabled = false;
  force_led_off(false);

  g_imu_ready = imu_begin();
  if (!g_imu_ready) {
    Serial.println(F("[WARN] IMU init failed; acceleration mode disabled"));
  }

  sl_bt_advertiser_create_set(&adv_handle);
  initialize_gatt_db();
  start_normal_advertising();
}

void loop() {
  handle_serial();
  uint32_t now = millis();

  if (!has_active_connection()) {
    g_output_enabled = false;
    force_led_off(false);
    delay(10);
    return;
  }

  if (output_allowed()) {
    update_front_rear();
  }

  if (!g_accel_mode && !g_led_enabled && !g_rainbow_mode) {
    if (!g_idle_frame) {
      force_led_off(output_allowed());
    }
    delay(10);
    return;
  }

  if (g_accel_mode) {
    update_accel_effect(now);
  } else if (g_led_enabled) {
    if (g_rainbow_mode) {
      update_rainbow(now);
    } else {
      update_solid();
    }
  } else {
    fill_all({0, 0, 0});
  }

  if (output_allowed()) {
    ws_show();
  }
  delay(10);
}

// -------------------- BLE events --------------------
extern "C" void sl_bt_on_event(sl_bt_msg_t *evt) {
  switch (SL_BT_MSG_ID(evt->header)) {
    case sl_bt_evt_system_boot_id:
      break;

    case sl_bt_evt_connection_opened_id:
      g_connection = evt->data.evt_connection_opened.connection;
      set_accel_mode(false);
      g_output_enabled = false;
      force_led_off(false);
      break;

    case sl_bt_evt_connection_closed_id:
      g_connection = SL_BT_INVALID_CONNECTION_HANDLE;
      set_accel_mode(false);
      g_output_enabled = false;
      force_led_off(false);
      start_normal_advertising();
      break;

    case sl_bt_evt_gatt_server_attribute_value_id: {
      auto &av = evt->data.evt_gatt_server_attribute_value;
      if (av.attribute == alert_level_characteristic_handle) {
        if (av.value.len >= 1) {
          apply_alert_level(av.value.data[0]);
        }
      } else if (av.attribute == led_adv_char_handle) {
        handle_led_command(av.value.data, av.value.len);
      }
      break;
    }

    case sl_bt_evt_advertiser_timeout_id:
      start_normal_advertising();
      break;

    default:
      break;
  }
}
