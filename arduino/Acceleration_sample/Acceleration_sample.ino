#include <Arduino.h>
#include <Wire.h>
#include <LSM6DS3.h>

// XIAO MG24 (Sense) example: WS2812B LEDs + IMU
extern "C" {
#include "em_cmu.h"
#include "em_gpio.h"
}
#include <core_cm33.h>

#ifndef SystemCoreClock
#define SystemCoreClock F_CPU
#endif

#ifdef RGB
#undef RGB
#endif
struct RGB { uint8_t r, g, b; };

// GPIO assignments
#define WS_PORT gpioPortA
#define WS_PIN  3            // D8 = PA3
#define IMU_EN  PD5
#define IMU_ADDR 0x6A

// LED configuration
#define MAX_LEDS 60
static uint16_t g_num_leds = 16;
static uint8_t g_brightness = 150;

// timing defaults
static uint8_t g_tm_mode = 1;
static uint32_t g_TTOTAL_ns = 1250;
static uint32_t g_T1H_ns = 700;
static uint32_t g_T0H_ns = 350;
static uint32_t g_T1L_ns = 550;
static uint32_t g_T0L_ns = 900;
static uint32_t g_TRESET_us = 300;

static uint32_t C1H, C1L, C0H, C0L;

static inline void dwt_init() {
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  DWT->CYCCNT = 0;
  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

static inline uint32_t ns2cyc(uint32_t ns) {
  return (uint32_t)(((uint64_t)SystemCoreClock * ns) / 1000000000ULL);
}

static inline void wait_cyc(uint32_t cyc) {
  uint32_t s = DWT->CYCCNT;
  while ((uint32_t)(DWT->CYCCNT - s) < cyc) {}
}

static void refresh_cycles() {
  if (g_tm_mode) {
    C1H = ns2cyc(g_T1H_ns);
    C1L = ns2cyc(g_TTOTAL_ns - g_T1H_ns);
    C0H = ns2cyc(g_T0H_ns);
    C0L = ns2cyc(g_TTOTAL_ns - g_T0H_ns);
  } else {
    C1H = ns2cyc(g_T1H_ns);
    C1L = ns2cyc(g_T1L_ns);
    C0H = ns2cyc(g_T0H_ns);
    C0L = ns2cyc(g_T0L_ns);
  }
}

static inline void pin_hi() { GPIO_PinOutSet(WS_PORT, WS_PIN); }
static inline void pin_lo() { GPIO_PinOutClear(WS_PORT, WS_PIN); }

static inline void ws_bit(bool one) {
  uint32_t s = DWT->CYCCNT;
  if (one) {
    pin_hi();  while ((uint32_t)(DWT->CYCCNT - s) < C1H) {}
    s = DWT->CYCCNT;
    pin_lo();  while ((uint32_t)(DWT->CYCCNT - s) < C1L) {}
  } else {
    pin_hi();  while ((uint32_t)(DWT->CYCCNT - s) < C0H) {}
    s = DWT->CYCCNT;
    pin_lo();  while ((uint32_t)(DWT->CYCCNT - s) < C0L) {}
  }
}

static inline void ws_byte(uint8_t v) {
  for (int i = 7; i >= 0; --i) ws_bit((v >> i) & 1u);
}

static inline void ws_grb(uint8_t g, uint8_t r, uint8_t b) {
  ws_byte(g); ws_byte(r); ws_byte(b);
}

static RGB leds[MAX_LEDS];

static void ws_show() {
  noInterrupts();
  for (uint16_t i = 0; i < g_num_leds; i++) {
    uint16_t r = (uint16_t)leds[i].r * g_brightness / 255;
    uint16_t g = (uint16_t)leds[i].g * g_brightness / 255;
    uint16_t b = (uint16_t)leds[i].b * g_brightness / 255;
    ws_grb((uint8_t)g, (uint8_t)r, (uint8_t)b);
  }
  interrupts();
  delayMicroseconds(g_TRESET_us);
}

static void ws_clear_many(uint8_t times = 4) {
  for (uint16_t i = 0; i < g_num_leds; i++) leds[i] = {0, 0, 0};
  for (uint8_t t = 0; t < times; t++) ws_show();
}

static inline void setPixel(uint16_t i, uint8_t r, uint8_t g, uint8_t b) {
  if (i < g_num_leds) leds[i] = {r, g, b};
}

static inline void fillAll(uint8_t r, uint8_t g, uint8_t b) {
  for (uint16_t i = 0; i < g_num_leds; i++) leds[i] = {r, g, b};
}

LSM6DS3 imu(I2C_MODE, IMU_ADDR);
static float g_lp = 0.f;

static void imu_begin() {
  pinMode(IMU_EN, OUTPUT);
  digitalWrite(IMU_EN, HIGH);
  delay(10);
  Wire.begin();
  Wire.setClock(400000);
  imu.begin();
}

static void imu_read(float &ax, float &ay, float &az) {
  ax = imu.readFloatAccelX();
  ay = imu.readFloatAccelY();
  az = imu.readFloatAccelZ();
}

enum Mode { MODE_SHAKE, MODE_TILT, MODE_RAINBOW, MODE_STATIC };
static Mode g_mode = MODE_SHAKE;
static RGB g_base = {0, 0, 255};

struct HSV { float h, s, v; };

static RGB hsv2rgb(float h, float s, float v) {
  while (h < 0) h += 360.f;
  while (h >= 360.f) h -= 360.f;
  float c = v * s;
  float x = c * (1 - fabs(fmod(h / 60.f, 2) - 1));
  float m = v - c;
  float r, g, b;
  if (h < 60)      { r = c; g = x; b = 0; }
  else if (h < 120) { r = x; g = c; b = 0; }
  else if (h < 180) { r = 0; g = c; b = x; }
  else if (h < 240) { r = 0; g = x; b = c; }
  else if (h < 300) { r = x; g = 0; b = c; }
  else              { r = c; g = 0; b = x; }
  RGB out;
  out.r = (uint8_t)roundf((r + m) * 255);
  out.g = (uint8_t)roundf((g + m) * 255);
  out.b = (uint8_t)roundf((b + m) * 255);
  return out;
}

static void fx_shake() {
  float ax, ay, az;
  imu_read(ax, ay, az);
  float mag = sqrtf(ax * ax + ay * ay + az * az);
  float delta = fabsf(mag - 1.f);
  g_lp = 0.9f * g_lp + 0.1f * delta;
  uint8_t level = (uint8_t)constrain(g_lp * 400.f, 0.f, 255.f);
  fillAll(level, 0, 255 - level);
}

static void fx_tilt() {
  float ax, ay, az;
  imu_read(ax, ay, az);
  float roll = atan2f(ay, az) * 180.0f / PI;
  float pitch = atan2f(-ax, sqrtf(ay * ay + az * az)) * 180.0f / PI;
  float mag = sqrtf(ax * ax + ay * ay + az * az);
  g_lp = 0.9f * g_lp + 0.1f * fabsf(mag - 1.f);
  float baseHue = roll + 180.f;
  float val = constrain(0.2f + g_lp, 0.f, 1.f);
  for (uint16_t i = 0; i < g_num_leds; i++) {
    float h = baseHue + 360.0f * i / max<uint16_t>(1, g_num_leds);
    leds[i] = hsv2rgb(h, 1.0f, val);
  }
}

static void fx_rainbow() {
  float ax, ay, az;
  imu_read(ax, ay, az);
  float mag = sqrtf(ax * ax + ay * ay + az * az);
  g_lp = 0.9f * g_lp + 0.1f * fabsf(mag - 1.f);
  static float hue = 0.f;
  hue += 60.f * (0.02f + g_lp);
  for (uint16_t i = 0; i < g_num_leds; i++) {
    float h = hue + 360.0f * i / max<uint16_t>(1, g_num_leds);
    leds[i] = hsv2rgb(h, 1.0f, 1.0f);
  }
}

static void print_help() {
  Serial.println(F("CMD: m0/m1/m2/m3, cls, B n, C r g b, S i r g b, N n"));
  Serial.println(F("Timing: TM 1|0, TT ns, T1H ns, T0H ns, T4 t1h t1l t0h t0l, TR us"));
  Serial.println(F("Fade: RB steps delay_ms"));
}

static void handle_serial() {
  static char buf[96];
  static uint8_t p = 0;
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (p == 0) continue;
      buf[p] = 0;
    } else if (p < sizeof(buf) - 1) {
      buf[p++] = c;
      buf[p] = 0;
    }
    if (c == '\n' || c == '\r' || !Serial.available() || p >= sizeof(buf) - 2) {
      for (uint8_t i = 0; i < p; i++)
        if (buf[i] >= 'a' && buf[i] <= 'z') buf[i] -= 32;

      if (!strncmp(buf, "M0", 2)) g_mode = MODE_SHAKE;
      else if (!strncmp(buf, "M1", 2)) g_mode = MODE_TILT;
      else if (!strncmp(buf, "M2", 2)) g_mode = MODE_RAINBOW;
      else if (!strncmp(buf, "M3", 2)) g_mode = MODE_STATIC;
      else if (!strncmp(buf, "CLS", 3)) {
        fillAll(0, 0, 0);
      } else if (buf[0] == 'B') {
        int v = atoi(buf + 1);
        g_brightness = constrain(v, 0, 255);
      } else if (!strncmp(buf, "C ", 2) || buf[0] == 'C') {
        int r, g, b;
        if (sscanf(buf, "C %d %d %d", &r, &g, &b) == 3) {
          g_base = {(uint8_t)r, (uint8_t)g, (uint8_t)b};
          fillAll(g_base.r, g_base.g, g_base.b);
          g_mode = MODE_STATIC;
        }
      } else if (!strncmp(buf, "S ", 2)) {
        int i, r, g, b;
        if (sscanf(buf, "S %d %d %d %d", &i, &r, &g, &b) == 4) {
          if (i >= 0 && i < g_num_leds) setPixel(i, (uint8_t)r, (uint8_t)g, (uint8_t)b);
          g_mode = MODE_STATIC;
        }
      } else if (!strncmp(buf, "N ", 2)) {
        int n;
        if (sscanf(buf, "N %d", &n) == 1) {
          g_num_leds = constrain(n, 1, (int)MAX_LEDS);
          ws_clear_many(4);
        }
      } else if (!strncmp(buf, "RB ", 3)) {
        int steps = 0, dms = 10;
        sscanf(buf, "RB %d %d", &steps, &dms);
        steps = constrain(steps, 1, 1000);
        dms = constrain(dms, 1, 1000);
        g_mode = MODE_STATIC;
        for (int k = 0; k <= steps; k++) {
          uint8_t r = (uint8_t)round(255.0 * (1.0 - (double)k / steps));
          uint8_t b = (uint8_t)round(255.0 * ((double)k / steps));
          fillAll(r, 0, b);
          ws_show();
          delay(dms);
        }
      } else if (!strncmp(buf, "TM ", 3)) {
        int m;
        if (sscanf(buf, "TM %d", &m) == 1) {
          g_tm_mode = (m ? 1 : 0);
          refresh_cycles();
        }
      } else if (!strncmp(buf, "TT ", 3)) {
        int ns;
        if (sscanf(buf, "TT %d", &ns) == 1) {
          g_TTOTAL_ns = max(800, ns);
          refresh_cycles();
        }
      } else if (!strncmp(buf, "T1H ", 4)) {
        int ns;
        if (sscanf(buf, "T1H %d", &ns) == 1) {
          g_T1H_ns = max(100, ns);
          refresh_cycles();
        }
      } else if (!strncmp(buf, "T0H ", 4)) {
        int ns;
        if (sscanf(buf, "T0H %d", &ns) == 1) {
          g_T0H_ns = max(100, ns);
          refresh_cycles();
        }
      } else if (!strncmp(buf, "T4 ", 3)) {
        int t1h, t1l, t0h, t0l;
        if (sscanf(buf, "T4 %d %d %d %d", &t1h, &t1l, &t0h, &t0l) == 4) {
          g_T1H_ns = max(100, t1h);
          g_T1L_ns = max(100, t1l);
          g_T0H_ns = max(100, t0h);
          g_T0L_ns = max(100, t0l);
          g_tm_mode = 0;
          refresh_cycles();
        }
      } else if (!strncmp(buf, "TR ", 3)) {
        int us;
        if (sscanf(buf, "TR %d", &us) == 1) {
          g_TRESET_us = max(80, us);
        }
      } else if (!strncmp(buf, "HELP", 4)) {
        print_help();
      }
      p = 0;
      buf[0] = 0;
    }
  }
}

void setup() {
  Serial.begin(115200);
  while (!Serial) {}
  Serial.println(F("WS2812B + IMU ready. type HELP"));

  CMU_ClockEnable(cmuClock_GPIO, true);
  GPIO_PinModeSet(WS_PORT, WS_PIN, gpioModePushPull, 0);
  dwt_init();
  refresh_cycles();
  imu_begin();
  ws_clear_many(6);
  print_help();
}

void loop() {
  handle_serial();
  switch (g_mode) {
    case MODE_SHAKE:   fx_shake();   break;
    case MODE_TILT:    fx_tilt();    break;
    case MODE_RAINBOW: fx_rainbow(); break;
    case MODE_STATIC:  break;
  }
  ws_show();
  delay(10);
}
