#include <Arduino.h>
#include <Wire.h>
#include <LSM6DS3.h>
#include <math.h>
#include "firmware_versions.h"
extern "C" {
  #include "em_gpio.h"
  #include "em_cmu.h"
  #include "sl_bt_api.h"
  #include "app_assert.h"
}
#include <core_cm33.h>

#if !defined(ARDUINO_SILABS_STACK_BLE_SILABS)
#error "Tools -> Protocol Stack: select BLE (SiLabs BGAPI)."
#endif

// BLE command codes (from gui_ble_D9.py)
static constexpr uint8_t CMD_SET_BRIGHTNESS = 0x01;
static constexpr uint8_t CMD_SET_FRONT_COLOR = 0x07;
static constexpr uint8_t CMD_SET_REAR_COLOR  = 0x08;
static constexpr uint8_t CMD_SET_OUTPUT_ENABLE = 0x09;
static constexpr uint8_t CMD_START_RAINBOW = 0x03;
static constexpr uint8_t CMD_STOP_RAINBOW = 0x04;
static constexpr uint8_t CMD_ACCEL_MODE = 0x06;

static const char *FIRMWARE_NAME = "xiao_mg24_ble_d9_front";
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

// WS2812 on D9 (front) and D10 (rear).
static constexpr GPIO_Port_TypeDef FRONT_PORT = gpioPortA; // D9 -> PA4
static constexpr uint8_t FRONT_PORT_PIN = 4;
static constexpr GPIO_Port_TypeDef REAR_PORT = gpioPortA;  // D10 -> PA5
static constexpr uint8_t REAR_PORT_PIN = 5;
static constexpr uint8_t FRONT_LED_COUNT = 12;
static constexpr uint8_t REAR_LED_COUNT = 16;
static constexpr uint8_t CLEAR_REPEATS = 2;

struct RGB { uint8_t r, g, b; };
static RGB g_front_color {0, 0, 0};
static RGB g_rear_color {0, 0, 0};
static RGB g_saved_front_color {0, 0, 0};
static RGB g_saved_rear_color {0, 0, 0};
static bool g_front_dirty = true;
static bool g_rear_dirty = true;
static bool g_front_user_selected = false;
static bool g_rear_user_selected = false;
static bool g_saved_front_valid = false;
static bool g_saved_rear_valid = false;
static uint8_t g_brightness = 255;
static bool g_output_enabled = false;
static bool g_output_guard_active = false;
static bool g_rainbow_mode = false;
static bool g_rainbow_dirty = false;
static uint32_t g_last_rainbow_ms = 0;
static uint16_t g_rainbow_interval_ms = 40;
static float g_rainbow_hue = 0.0f;
static bool g_accel_mode = false;
static bool g_imu_ready = false;
static float g_tilt_lp = 0.2f;
static uint32_t g_last_imu_print_ms = 0;
static uint32_t g_last_imu_fail_ms = 0;
static bool g_accel_restore_pending = false;

// -------------------- IMU (LSM6DS3) --------------------
static constexpr uint8_t IMU_EN_PIN = 5; // PD5
static constexpr uint8_t IMU_ADDR = 0x6A;
LSM6DS3 imu(I2C_MODE, IMU_ADDR);

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
  GPIO_PinOutSet(port, pin);
  wait_cyc(one ? C1H : C0H);
  GPIO_PinOutClear(port, pin);
  wait_cyc(one ? C1L : C0L);
}
static inline void ws_byte_port(GPIO_Port_TypeDef port, uint8_t pin, uint8_t v) {
  for (int i = 7; i >= 0; --i) ws_bit_port(port, pin, (v >> i) & 1);
}
static inline void ws_grb_port(GPIO_Port_TypeDef port, uint8_t pin, uint8_t g, uint8_t r, uint8_t b) {
  ws_byte_port(port, pin, g);
  ws_byte_port(port, pin, r);
  ws_byte_port(port, pin, b);
}

static void set_front_color(uint8_t r, uint8_t g, uint8_t b) {
  g_front_color = { r, g, b };
  g_front_dirty = true;
}

static void set_rear_color(uint8_t r, uint8_t g, uint8_t b) {
  g_rear_color = { r, g, b };
  g_rear_dirty = true;
}

static RGB hsv_to_rgb(float h, float s, float v) {
  while (h < 0.0f) h += 360.0f;
  while (h >= 360.0f) h -= 360.0f;
  float c = v * s;
  float x = c * (1.0f - fabsf(fmodf(h / 60.0f, 2.0f) - 1.0f));
  float m = v - c;
  float r1, g1, b1;
  if (h < 60.0f)      { r1 = c; g1 = x; b1 = 0.0f; }
  else if (h < 120.0f){ r1 = x; g1 = c; b1 = 0.0f; }
  else if (h < 180.0f){ r1 = 0.0f; g1 = c; b1 = x; }
  else if (h < 240.0f){ r1 = 0.0f; g1 = x; b1 = c; }
  else if (h < 300.0f){ r1 = x; g1 = 0.0f; b1 = c; }
  else               { r1 = c; g1 = 0.0f; b1 = x; }
  RGB out;
  out.r = (uint8_t)roundf((r1 + m) * 255.0f);
  out.g = (uint8_t)roundf((g1 + m) * 255.0f);
  out.b = (uint8_t)roundf((b1 + m) * 255.0f);
  return out;
}

static void update_rainbow(uint32_t now_ms) {
  if (!g_rainbow_mode) {
    return;
  }
  if (now_ms - g_last_rainbow_ms < g_rainbow_interval_ms) {
    return;
  }
  g_last_rainbow_ms = now_ms;
  g_rainbow_hue += 3.0f;
  if (g_rainbow_hue >= 360.0f) {
    g_rainbow_hue -= 360.0f;
  }
  g_rainbow_dirty = true;
}

static void update_front_rear() {
  if (g_rainbow_mode) {
    if (!g_rainbow_dirty) {
      return;
    }
  } else if (!g_front_dirty && !g_rear_dirty) {
    return;
  }
  noInterrupts();
  if (g_rainbow_mode) {
    for (uint8_t i = 0; i < FRONT_LED_COUNT; ++i) {
      float hue = g_rainbow_hue + (360.0f / FRONT_LED_COUNT) * i;
      RGB c = hsv_to_rgb(hue, 1.0f, 1.0f);
      uint16_t r = (uint16_t)c.r * g_brightness / 255;
      uint16_t g = (uint16_t)c.g * g_brightness / 255;
      uint16_t b = (uint16_t)c.b * g_brightness / 255;
      ws_grb_port(FRONT_PORT, FRONT_PORT_PIN, (uint8_t)g, (uint8_t)r, (uint8_t)b);
    }
    for (uint8_t i = 0; i < REAR_LED_COUNT; ++i) {
      float hue = g_rainbow_hue + (360.0f / REAR_LED_COUNT) * i;
      RGB c = hsv_to_rgb(hue, 1.0f, 1.0f);
      uint16_t r = (uint16_t)c.r * g_brightness / 255;
      uint16_t g = (uint16_t)c.g * g_brightness / 255;
      uint16_t b = (uint16_t)c.b * g_brightness / 255;
      ws_grb_port(REAR_PORT, REAR_PORT_PIN, (uint8_t)g, (uint8_t)r, (uint8_t)b);
    }
    g_rainbow_dirty = false;
  } else {
    if (g_front_dirty) {
      for (uint8_t i = 0; i < FRONT_LED_COUNT; ++i) {
        uint16_t r = (uint16_t)g_front_color.r * g_brightness / 255;
        uint16_t g = (uint16_t)g_front_color.g * g_brightness / 255;
        uint16_t b = (uint16_t)g_front_color.b * g_brightness / 255;
        ws_grb_port(FRONT_PORT, FRONT_PORT_PIN, (uint8_t)g, (uint8_t)r, (uint8_t)b);
      }
      g_front_dirty = false;
    }
    if (g_rear_dirty) {
      for (uint8_t i = 0; i < REAR_LED_COUNT; ++i) {
        uint16_t r = (uint16_t)g_rear_color.r * g_brightness / 255;
        uint16_t g = (uint16_t)g_rear_color.g * g_brightness / 255;
        uint16_t b = (uint16_t)g_rear_color.b * g_brightness / 255;
        ws_grb_port(REAR_PORT, REAR_PORT_PIN, (uint8_t)g, (uint8_t)r, (uint8_t)b);
      }
      g_rear_dirty = false;
    }
  }
  interrupts();
  delayMicroseconds(g_TRESET_us);
}

static void force_led_off(bool allow_output) {
  g_rainbow_mode = false;
  g_rainbow_dirty = false;
  g_accel_mode = false;
  g_accel_restore_pending = false;
  g_front_user_selected = false;
  g_rear_user_selected = false;
  g_saved_front_valid = false;
  g_saved_rear_valid = false;
  if (allow_output) {
    for (uint8_t i = 0; i < CLEAR_REPEATS; ++i) {
      set_front_color(0, 0, 0);
      set_rear_color(0, 0, 0);
      update_front_rear();
    }
  } else {
    set_front_color(0, 0, 0);
    set_rear_color(0, 0, 0);
  }
  GPIO_PinOutClear(FRONT_PORT, FRONT_PORT_PIN);
  GPIO_PinOutClear(REAR_PORT, REAR_PORT_PIN);
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
  imu.settings.accelRange = 2;
  imu.settings.accelSampleRate = 104;
  imu.settings.accelBandWidth = 100;
  imu.begin();
  return true;
}

static bool imu_read(float &ax, float &ay, float &az) {
  if (!g_imu_ready) {
    return false;
  }
  ax = imu.readFloatAccelX();
  ay = imu.readFloatAccelY();
  az = imu.readFloatAccelZ();
  if (!isfinite(ax) || !isfinite(ay) || !isfinite(az)) {
    return false;
  }
  return true;
}

static void update_accel_effect() {
  uint32_t now_ms = millis();
  float ax, ay, az;
  if (!imu_read(ax, ay, az)) {
    set_front_color(0, 0, 0);
    set_rear_color(0, 0, 0);
    if (now_ms - g_last_imu_fail_ms >= 500) {
      g_last_imu_fail_ms = now_ms;
      Serial.println(F("[IMU] read failed"));
    }
    return;
  }
  float tilt_mag = sqrtf(ax * ax + ay * ay);
  g_tilt_lp = 0.9f * g_tilt_lp + 0.1f * tilt_mag;

  float brightness = 1.0f;
  float heading = atan2f(ay, ax) * 180.0f / PI;
  heading += 180.0f;
  RGB base = hsv_to_rgb(heading, 0.9f, brightness);

  g_front_color = base;
  g_rear_color = base;
  g_front_dirty = true;
  g_rear_dirty = true;

  if (now_ms - g_last_imu_print_ms >= 200) {
    g_last_imu_print_ms = now_ms;
    Serial.print(F("[IMU] ax="));
    Serial.print(ax, 3);
    Serial.print(F(" ay="));
    Serial.print(ay, 3);
    Serial.print(F(" az="));
    Serial.print(az, 3);
    Serial.print(F(" hue="));
    Serial.print(heading, 1);
    Serial.print(F(" bright="));
    Serial.println(brightness, 2);
  }
}


// -------------------- BLE helpers --------------------
static void apply_alert_level(uint8_t level) {
  if (level == 0) {
    force_led_off(g_output_enabled);
  }
}

static void handle_led_command(const uint8_t *data, uint16_t len) {
  if (!data || len == 0) return;
  if (data[0] == CMD_SET_OUTPUT_ENABLE) {
    if (len >= 2) {
      bool enable = data[1] != 0;
      bool was_enabled = g_output_enabled;
      g_output_guard_active = true;
      if (!enable) {
        g_output_enabled = false;
        g_rainbow_mode = false;
        g_rainbow_dirty = false;
        g_accel_mode = false;
        g_accel_restore_pending = false;
        g_front_user_selected = false;
        g_rear_user_selected = false;
        g_saved_front_valid = false;
        g_saved_rear_valid = false;
        force_led_off(was_enabled);
      } else {
        g_output_enabled = true;
        g_front_dirty = false;
        g_rear_dirty = false;
        g_rainbow_dirty = false;
        g_front_user_selected = false;
        g_rear_user_selected = false;
        g_saved_front_valid = false;
        g_saved_rear_valid = false;
        g_accel_restore_pending = false;
        g_front_color = {0, 0, 0};
        g_rear_color = {0, 0, 0};
      }
    }
    return;
  }
  switch (data[0]) {
    case CMD_SET_BRIGHTNESS:
      if (len >= 2) {
        g_brightness = data[1];
        if (g_rainbow_mode) {
          g_rainbow_dirty = true;
        }
        if (g_accel_mode) {
          g_front_dirty = true;
          g_rear_dirty = true;
        }
        if (g_front_user_selected) {
          g_front_dirty = true;
        }
        if (g_rear_user_selected) {
          g_rear_dirty = true;
        }
      }
      break;
    case CMD_START_RAINBOW:
      g_rainbow_mode = true;
      g_rainbow_dirty = true;
      g_last_rainbow_ms = millis();
      g_accel_mode = false;
      g_accel_restore_pending = false;
      g_saved_front_valid = false;
      g_saved_rear_valid = false;
      if (len >= 3) {
        uint16_t interval = (uint16_t)data[1] | ((uint16_t)data[2] << 8);
        if (interval > 0) {
          g_rainbow_interval_ms = interval;
        }
      }
      break;
    case CMD_STOP_RAINBOW:
      g_rainbow_mode = false;
      g_rainbow_dirty = false;
      g_front_dirty = true;
      g_rear_dirty = true;
      break;
    case CMD_ACCEL_MODE:
      if (len >= 2) {
        bool enable = data[1] != 0;
        if (enable && g_imu_ready) {
          if (!g_accel_mode) {
            g_saved_front_valid = g_front_user_selected;
            g_saved_rear_valid = g_rear_user_selected;
            g_saved_front_color = g_front_user_selected ? g_front_color : RGB{0, 0, 0};
            g_saved_rear_color = g_rear_user_selected ? g_rear_color : RGB{0, 0, 0};
            g_accel_restore_pending = g_saved_front_valid || g_saved_rear_valid;
          }
          g_accel_mode = true;
          g_rainbow_mode = false;
          g_rainbow_dirty = false;
          Serial.println(F("[IMU] accel mode ON"));
        } else {
          g_accel_mode = false;
          if (g_accel_restore_pending) {
            if (g_saved_front_valid) {
              set_front_color(g_saved_front_color.r, g_saved_front_color.g, g_saved_front_color.b);
            } else {
              set_front_color(0, 0, 0);
            }
            if (g_saved_rear_valid) {
              set_rear_color(g_saved_rear_color.r, g_saved_rear_color.g, g_saved_rear_color.b);
            } else {
              set_rear_color(0, 0, 0);
            }
            g_front_user_selected = g_saved_front_valid;
            g_rear_user_selected = g_saved_rear_valid;
            g_saved_front_valid = false;
            g_saved_rear_valid = false;
            g_accel_restore_pending = false;
          } else {
            set_front_color(0, 0, 0);
            set_rear_color(0, 0, 0);
            g_front_user_selected = false;
            g_rear_user_selected = false;
          }
          Serial.println(F("[IMU] accel mode OFF"));
        }
      }
      break;
    case CMD_SET_FRONT_COLOR:
      if (len >= 4) {
        g_rainbow_mode = false;
        g_rainbow_dirty = false;
        g_accel_mode = false;
        g_accel_restore_pending = false;
        g_saved_front_valid = false;
        g_saved_rear_valid = false;
        g_front_user_selected = true;
        set_front_color(data[1], data[2], data[3]);
      }
      break;
    case CMD_SET_REAR_COLOR:
      if (len >= 4) {
        g_rainbow_mode = false;
        g_rainbow_dirty = false;
        g_accel_mode = false;
        g_accel_restore_pending = false;
        g_saved_front_valid = false;
        g_saved_rear_valid = false;
        g_rear_user_selected = true;
        set_rear_color(data[1], data[2], data[3]);
      }
      break;
    default:
      break;
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

// -------------------- GATT initialization --------------------
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

static void print_version() {
  Serial.print(F("Firmware: "));
  Serial.print(FIRMWARE_NAME);
  Serial.print(F(" v"));
  Serial.println(FW_VERSION_D9_FRONT);
}

// -------------------- Arduino lifecycle --------------------
void setup() {
  Serial.begin(115200);
  delay(100);
  print_version();

  CMU_ClockEnable(cmuClock_GPIO, true);
  GPIO_PinModeSet(FRONT_PORT, FRONT_PORT_PIN, gpioModePushPull, 0);
  GPIO_PinModeSet(REAR_PORT, REAR_PORT_PIN, gpioModePushPull, 0);
  GPIO_PinOutClear(FRONT_PORT, FRONT_PORT_PIN);
  GPIO_PinOutClear(REAR_PORT, REAR_PORT_PIN);
  dwt_init();
  refresh_cycles();
  g_output_enabled = false;
  force_led_off(false);
  g_imu_ready = imu_begin();
  if (g_imu_ready) {
    Serial.println(F("[IMU] init OK"));
  } else {
    Serial.println(F("[IMU] init failed"));
  }

  sl_bt_advertiser_create_set(&adv_handle);
  initialize_gatt_db();
  start_normal_advertising();
}

void loop() {
  uint32_t now = millis();
  if (g_output_enabled) {
    if (g_accel_mode) {
      update_accel_effect();
    } else if (g_rainbow_mode) {
      update_rainbow(now);
    }
    update_front_rear();
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
      if (g_output_guard_active) {
        g_output_enabled = false;
      }
      force_led_off(false);
      break;

    case sl_bt_evt_connection_closed_id:
      g_connection = SL_BT_INVALID_CONNECTION_HANDLE;
      if (g_output_guard_active) {
        g_output_enabled = false;
      }
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










