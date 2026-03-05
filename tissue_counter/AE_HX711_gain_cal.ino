// File: AE_HX711_gain_cal.ino

#include <Arduino.h>

// ===== Public API =====
void AE_HX711_Init(void);
void AE_HX711_Reset(void);
void AE_HX711_SetGain(uint8_t g);
long AE_HX711_Read(void);                    // 互換API（現在ゲイン）
long AE_HX711_ReadGain(uint8_t g);           // 新API（指定ゲインで読み、次回ゲインを設定）
long AE_HX711_Averaging(long adc, char num); // 互換API（adc引数は未使用のまま）
long AE_HX711_AveragingGain(uint8_t g, uint8_t num);
void AE_HX711_Tare(uint8_t num, uint8_t g);
void AE_HX711_Calibrate(double known_g, uint8_t num, uint8_t g);
float AE_HX711_getGram(char num);            // 互換API（現在ゲイン）

// ===== Pins =====
#define pin_dout  8
#define pin_slk   9

// ===== Loadcell spec (choose one) =====
// SC301A 100kg
// #define OUT_VOL 0.002f
// #define LOAD    100000.0f
// SC601 120kg
// #define OUT_VOL 0.001f
// #define LOAD    120000.0f
// SC133 20kg  (active)
#define OUT_VOL 0.002f
#define LOAD    20000.0f
// SC616C 500g
// #define OUT_VOL 0.0007f
// #define LOAD    500.0f

// ===== Gain / Channel mapping =====
// 値=追加クロック回数（「次回」変換のゲイン/CHを設定）
enum HX711Gain : uint8_t { HX711_A_128 = 1, HX711_B_32 = 2, HX711_A_64 = 3 };

// ===== User options =====
#define SERIAL_BAUD       9600
#define STARTUP_GAIN      HX711_A_128
#define TARE_SAMPLES      30
#define READ_SAMPLES      5
#define CALIB_WEIGHT_G    0.0  // 既知分銅[g]（>0で起動時に自動校正）

// ===== Internal state =====
static volatile uint8_t g_gain = STARTUP_GAIN;
static volatile long    g_offset = 0;
static volatile double  g_gramsPerCount = 0.0;
static volatile bool    g_calibrated = false;

// ===== Helpers =====
static inline uint16_t pga_from_gain(uint8_t g) {
  switch (g) {
    case HX711_A_128: return 128;
    case HX711_B_32:  return 32;
    case HX711_A_64:  return 64;
    default:          return 128;
  }
}
// 理論スケール（AVDDは相殺される）
static inline double gramsPerCountTheoretical(uint8_t g) {
  const double two24 = 16777216.0;
  return (double)LOAD / (two24 * (double)OUT_VOL * (double)pga_from_gain(g));
}

// ===== Impl =====
void AE_HX711_Init(void) {
  pinMode(pin_slk, OUTPUT);
  pinMode(pin_dout, INPUT);
  digitalWrite(pin_slk, LOW);
}

void AE_HX711_Reset(void) {
  // なぜ: 電源相当のリセットを与えて不定状態を避ける
  digitalWrite(pin_slk, HIGH);
  delayMicroseconds(100);
  digitalWrite(pin_slk, LOW);
  delayMicroseconds(100);
}

void AE_HX711_SetGain(uint8_t g) {
  g_gain = g;
  // なぜ: 追加クロックは「次回」ゲインを設定するため、1回捨て読みで反映
  (void)AE_HX711_ReadGain(g_gain);
}

static bool hx711_wait_ready(uint32_t timeout_ms = 1000) {
  uint32_t t0 = millis();
  while (digitalRead(pin_dout) != LOW) {
    if ((millis() - t0) > timeout_ms) return false; // 未接続/ビジー
    delay(1);
  }
  return true;
}

long AE_HX711_ReadGain(uint8_t g) {
  if (!hx711_wait_ready()) return LONG_MIN;
  unsigned long value = 0UL;

  for (uint8_t i = 0; i < 24; ++i) {
    digitalWrite(pin_slk, HIGH);
    delayMicroseconds(1);
    value = (value << 1) | (digitalRead(pin_dout) ? 1UL : 0UL);
    digitalWrite(pin_slk, LOW);
    delayMicroseconds(1);
  }

  // 追加クロック：次回ゲイン/CHを設定
  for (uint8_t i = 0; i < g; ++i) {
    digitalWrite(pin_slk, HIGH);
    delayMicroseconds(1);
    digitalWrite(pin_slk, LOW);
    delayMicroseconds(1);
  }

  // 24bit 符号拡張（two's complement）
  if (value & 0x800000UL) {
    value |= 0xFF000000UL;
  }
  return (long)value;
}

long AE_HX711_Read(void) {
  return AE_HX711_ReadGain(g_gain);
}

long AE_HX711_AveragingGain(uint8_t g, uint8_t num) {
  if (num == 0) num = 1;
  long sum = 0;
  uint8_t ok = 0;
  for (uint8_t i = 0; i < num; ++i) {
    long v = AE_HX711_ReadGain(g);
    if (v == LONG_MIN) continue;
    sum += v;
    ++ok;
  }
  if (!ok) return LONG_MIN;
  return sum / ok;
}

// 既存互換（adcは未使用のままにしておく）
long AE_HX711_Averaging(long /*adc*/, char num) {
  return AE_HX711_AveragingGain(g_gain, (uint8_t)num);
}

void AE_HX711_Tare(uint8_t num, uint8_t g) {
  long avg = AE_HX711_AveragingGain(g, num);
  if (avg != LONG_MIN) g_offset = avg;
}

void AE_HX711_Calibrate(double known_g, uint8_t num, uint8_t g) {
  // なぜ: 実機校正は理論誤差（配線, 室温, 実AVDD）を吸収できる
  long avg = AE_HX711_AveragingGain(g, num);
  if (avg == LONG_MIN) return;
  long net = avg - g_offset;
  if (net == 0) return;
  g_gramsPerCount = known_g / (double)net;
  g_calibrated = true;
}

float AE_HX711_getGram(char num) {
  long avg = AE_HX711_AveragingGain(g_gain, (uint8_t)num);
  if (avg == LONG_MIN) return NAN;

  long net = avg - g_offset;
  double gpc = g_calibrated ? g_gramsPerCount
                            : gramsPerCountTheoretical(g_gain);
  double grams = (double)net * gpc;
  return (float)grams;
}

// ===== Demo sketch =====
static float offset_demo = 0.0f;

void setup() {
  Serial.begin(SERIAL_BAUD);
  Serial.println(F("AE_HX711 gain+cal demo"));

  AE_HX711_Init();
  AE_HX711_Reset();

  AE_HX711_SetGain(STARTUP_GAIN);
  AE_HX711_Tare(TARE_SAMPLES, STARTUP_GAIN);

  if (CALIB_WEIGHT_G > 0.0) {
    Serial.print(F("Calibrating with known weight [g]: "));
    Serial.println(CALIB_WEIGHT_G, 3);
    AE_HX711_Calibrate(CALIB_WEIGHT_G, TARE_SAMPLES, STARTUP_GAIN);
  } else {
    // なぜ: 実重校正未実施でも動くように理論スケールで暫定動作
    g_gramsPerCount = gramsPerCountTheoretical(STARTUP_GAIN);
    g_calibrated = false;
  }

  // 古い表示互換: offsetを保持
  offset_demo = AE_HX711_getGram(READ_SAMPLES);
}

void loop() {
  // 現在ゲインでの重量
  float grams = AE_HX711_getGram(READ_SAMPLES);

  // Rawも参考出力（上位24bitをHEX表示）
  long raw = AE_HX711_Read();

  char s[20], buf[64];
  dtostrf((grams - offset_demo), 7, 3, s);
  snprintf(buf, sizeof(buf), "%s [g] (raw=0x%06lX) GAIN=%u",
           s, (raw & 0x00FFFFFF), (unsigned)pga_from_gain(g_gain));
  Serial.println(buf);

  delay(500);

  // 例: ゲイン切替デモ（コメントアウトで固定運用）
  // static uint32_t t0 = millis();
  // if (millis() - t0 > 5000) {
  //   t0 = millis();
  //   if (g_gain == HX711_A_128) AE_HX711_SetGain(HX711_A_64);
  //   else if (g_gain == HX711_A_64) AE_HX711_SetGain(HX711_B_32);
  //   else AE_HX711_SetGain(HX711_A_128);
  //   AE_HX711_Tare(TARE_SAMPLES, g_gain); // なぜ: 切替ごとにオフセットが変動するため
  // }
}
