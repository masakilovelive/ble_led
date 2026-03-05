#include <Arduino.h>
extern "C" {
  #include "em_gpio.h"
  #include "em_cmu.h"
}
#include <core_cm33.h>

// WS2812 timing (ns).
static uint32_t g_TTOTAL_ns = 1250;
static uint32_t g_T1H_ns = 800;
static uint32_t g_T0H_ns = 200;
static uint32_t g_TRESET_us = 300;

static uint32_t C1H, C1L, C0H, C0L;

// Pin map: XIAO MG24 D9=PA4, D10=PA5.
static constexpr GPIO_Port_TypeDef FRONT_PORT = gpioPortA;
static constexpr uint8_t FRONT_PORT_PIN = 4;  // D9
static constexpr GPIO_Port_TypeDef REAR_PORT = gpioPortA;
static constexpr uint8_t REAR_PORT_PIN = 5;   // D10

struct RGB { uint8_t r, g, b; };

// 0 = D9 only, 1 = D10 only, 2 = D9+D10, 3 = cycle.
static constexpr uint8_t TEST_MODE = 3;
static constexpr uint32_t MODE_INTERVAL_MS = 3000;
static constexpr uint32_t FRAME_INTERVAL_MS = 20;
static const RGB FRONT_COLOR = {255, 0, 0};
static const RGB REAR_COLOR = {0, 0, 255};

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
  for (int i = 7; i >= 0; --i) {
    ws_bit_port(port, pin, (v >> i) & 1);
  }
}

static inline void ws_grb_port(GPIO_Port_TypeDef port, uint8_t pin, uint8_t g, uint8_t r, uint8_t b) {
  ws_byte_port(port, pin, g);
  ws_byte_port(port, pin, r);
  ws_byte_port(port, pin, b);
}

static void show_front(const RGB &c) {
  noInterrupts();
  ws_grb_port(FRONT_PORT, FRONT_PORT_PIN, c.g, c.r, c.b);
  interrupts();
  delayMicroseconds(g_TRESET_us);
}

static void show_rear(const RGB &c) {
  noInterrupts();
  ws_grb_port(REAR_PORT, REAR_PORT_PIN, c.g, c.r, c.b);
  interrupts();
  delayMicroseconds(g_TRESET_us);
}

static void show_front_off_once() {
  static bool sent = false;
  if (sent) return;
  show_front({0, 0, 0});
  sent = true;
}

static void show_rear_off_once() {
  static bool sent = false;
  if (sent) return;
  show_rear({0, 0, 0});
  sent = true;
}

void setup() {
  CMU_ClockEnable(cmuClock_GPIO, true);
  GPIO_PinModeSet(FRONT_PORT, FRONT_PORT_PIN, gpioModePushPull, 0);
  GPIO_PinModeSet(REAR_PORT, REAR_PORT_PIN, gpioModePushPull, 0);
  GPIO_PinOutClear(FRONT_PORT, FRONT_PORT_PIN);
  GPIO_PinOutClear(REAR_PORT, REAR_PORT_PIN);

  dwt_init();
  refresh_cycles();
}

void loop() {
  static uint8_t mode = (TEST_MODE == 3) ? 0 : TEST_MODE;
  static uint32_t last_mode_ms = 0;

  uint32_t now = millis();
  if (TEST_MODE == 3 && (now - last_mode_ms) >= MODE_INTERVAL_MS) {
    last_mode_ms = now;
    mode = (mode + 1) % 3;
  }

  if (mode == 0) {
    show_front(FRONT_COLOR);
    show_rear_off_once();
  } else if (mode == 1) {
    show_rear(REAR_COLOR);
    show_front_off_once();
  } else {
    show_front(FRONT_COLOR);
    show_rear(REAR_COLOR);
  }

  delay(FRAME_INTERVAL_MS);
}
