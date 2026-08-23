/*
  UNO endurance test helper
  - Digital light sensor monitor on D12 / D13
  - X9C103S digital potentiometer control (INC/U-D/CS)
1234567891011121314151617181920212223
/*
  UNO endurance test helper
  - Digital light sensor monitor on D12 / D13
  - X9C103S digital potentiometer control (INC/U-D/CS)
  - Stock A / Stock B power rail control with boot sequence

  Serial monitor: 115200 baud
*/

#include <Arduino.h>


  - Stock A / Stock B power rail control with boot sequence

  Serial monitor: 115200 baud
*/

#include <Arduino.h>

// --------------------------- Pin assignment ---------------------------
static const uint8_t PIN_SENSOR_A = 12;
static const uint8_t PIN_SENSOR_B = 13;

static const uint8_t PIN_X9C_INC = 9;
static const uint8_t PIN_X9C_UD = 8;
static const uint8_t PIN_X9C_CS = 10;

// Power rail control pins (change to match your board wiring)
static const uint8_t PIN_PWR_A = 6;
static const uint8_t PIN_PWR_B = 7;

// --------------------------- Behavior config ---------------------------
static const bool SENSOR_USE_PULLUP = false;
static const bool SENSOR_STATUS_LOG_ENABLED = false;
static const bool CALIBRATE_TO_MIN_ON_BOOT = true;

// Power output polarity and sequence timing.
static const bool POWER_ACTIVE_HIGH = true;
static const bool AUTO_BOOT_STOCK_SEQUENCE_ON_BOOT = true;
static const uint16_t POWER_OFF_GUARD_MS = 300;
static const uint16_t POWER_A_TO_B_DELAY_MS = 700;
static const uint16_t POWER_BOOT_SETTLE_MS = 1500;

static const uint16_t SENSOR_POLL_MS = 20;
static const uint16_t SENSOR_DEBOUNCE_MS = 10;

static const uint16_t X9C_PULSE_US = 5;
static const uint16_t X9C_STEP_DELAY_MS = 2;
static const int X9C_MAX_TAP = 99;
static const long X9C_TOTAL_OHMS = 10000L;  // X9C103S = 10k

// --------------------------- Runtime state ---------------------------
static int g_currentTap = -1;
static uint32_t g_lastSensorPollMs = 0;

static bool g_lastRawA = LOW;
static bool g_lastRawB = LOW;
static bool g_stableA = LOW;
static bool g_stableB = LOW;
static uint32_t g_lastRawChangeAMs = 0;
static uint32_t g_lastRawChangeBMs = 0;

static bool g_powerAEnabled = false;
static bool g_powerBEnabled = false;

// --------------------------- Utility ---------------------------
static const char *hl(bool v) { return v ? "HIGH" : "LOW"; }
static const char *onoff(bool v) { return v ? "ON" : "OFF"; }

bool readSensorPin(uint8_t pin) {
  return digitalRead(pin) == HIGH;
}

void printX9CStatus() {
  long approx = (X9C_TOTAL_OHMS * (long)g_currentTap) / X9C_MAX_TAP;
  Serial.print(F("[X9C] tap="));
  Serial.print(g_currentTap);
  Serial.print(F(" / "));
  Serial.print(X9C_MAX_TAP);
  Serial.print(F(", approx="));
  Serial.print(approx);
  Serial.println(F(" ohm"));
}

void printSensorStatus() {
  if (!SENSOR_STATUS_LOG_ENABLED) {
    return;
  }
  Serial.print(F("[SENS] D12="));
  Serial.print(hl(g_stableA));
  Serial.print(F(", D13="));
  Serial.println(hl(g_stableB));
}

void printPowerStatus() {
  Serial.print(F("[PWR] A="));
  Serial.print(onoff(g_powerAEnabled));
  Serial.print(F(", B="));
  Serial.println(onoff(g_powerBEnabled));
}

void printHelp() {
  Serial.println();
  Serial.println(F("=== UNO endurance test command list ==="));
  Serial.println(F("  r             : print sensor + x9c + power status"));
  Serial.println(F("  +             : x9c tap +1"));
  Serial.println(F("  -             : x9c tap -1"));
  Serial.println(F("  min           : x9c -> tap 0"));
  Serial.println(F("  max           : x9c -> tap 99"));
  Serial.println(F("  s<N>          : x9c set tap (0..99), ex: s45"));
  Serial.println(F("  sweep         : x9c sweep 0->99->0"));
  Serial.println(F("  pa on|off     : stock A power"));
  Serial.println(F("  pb on|off     : stock B power"));
  Serial.println(F("  pon           : power ON both A/B"));
  Serial.println(F("  poff          : power OFF both A/B"));
  Serial.println(F("  boot          : power boot seq (OFF->A->B)"));
  Serial.println(F("  cycle         : same as boot (for endurance cycle)"));
  Serial.println(F("  ?             : help"));
  Serial.println();
}

// --------------------------- X9C103S control ---------------------------
void x9cPulseInc() {
  digitalWrite(PIN_X9C_INC, HIGH);
  delayMicroseconds(X9C_PULSE_US);
  digitalWrite(PIN_X9C_INC, LOW);
  delayMicroseconds(X9C_PULSE_US);
  digitalWrite(PIN_X9C_INC, HIGH);
}

void x9cStepRaw(bool up) {
  digitalWrite(PIN_X9C_CS, LOW);
  digitalWrite(PIN_X9C_UD, up ? HIGH : LOW);
  delayMicroseconds(X9C_PULSE_US);
  x9cPulseInc();
  delay(X9C_STEP_DELAY_MS);
  digitalWrite(PIN_X9C_CS, HIGH);  // store new position
  delayMicroseconds(X9C_PULSE_US);
}

void x9cMoveToMin() {
  // Over-step to guarantee minimum position.
  digitalWrite(PIN_X9C_CS, LOW);
  digitalWrite(PIN_X9C_UD, LOW);
  delayMicroseconds(X9C_PULSE_US);
  for (int i = 0; i < 120; ++i) {
    x9cPulseInc();
    delay(X9C_STEP_DELAY_MS);
  }
  digitalWrite(PIN_X9C_CS, HIGH);
  delayMicroseconds(X9C_PULSE_US);
  g_currentTap = 0;
}

void x9cSetTap(int target) {
  if (target < 0) target = 0;
  if (target > X9C_MAX_TAP) target = X9C_MAX_TAP;

  if (g_currentTap < 0) {
    x9cMoveToMin();
  }

  while (g_currentTap < target) {
    x9cStepRaw(true);
    g_currentTap++;
  }
  while (g_currentTap > target) {
    x9cStepRaw(false);
    g_currentTap--;
  }
}

void x9cStep(int delta) {
  if (g_currentTap < 0) {
    x9cMoveToMin();
  }
  int next = g_currentTap + delta;
  x9cSetTap(next);
}

void x9cSweepDemo() {
  Serial.println(F("[X9C] sweep start"));
  x9cSetTap(0);
  for (int i = 1; i <= X9C_MAX_TAP; ++i) {
    x9cSetTap(i);
  }
  for (int i = X9C_MAX_TAP - 1; i >= 0; --i) {
    x9cSetTap(i);
  }
  Serial.println(F("[X9C] sweep done"));
}

// --------------------------- Stock power control ---------------------------
bool toPowerPinLevel(bool enabled) {
  return POWER_ACTIVE_HIGH ? enabled : !enabled;
}

void writePowerPin(uint8_t pin, bool enabled) {
  digitalWrite(pin, toPowerPinLevel(enabled) ? HIGH : LOW);
}

void syncSensorSnapshot() {
  const uint32_t now = millis();
  g_lastRawA = readSensorPin(PIN_SENSOR_A);
  g_lastRawB = readSensorPin(PIN_SENSOR_B);
  g_stableA = g_lastRawA;
  g_stableB = g_lastRawB;
  g_lastRawChangeAMs = now;
  g_lastRawChangeBMs = now;
}

void setStockPowerA(bool enabled, bool verbose) {
  g_powerAEnabled = enabled;
  writePowerPin(PIN_PWR_A, enabled);
  if (verbose) {
    Serial.print(F("[PWR] A -> "));
    Serial.println(onoff(enabled));
  }
}

void setStockPowerB(bool enabled, bool verbose) {
  g_powerBEnabled = enabled;
  writePowerPin(PIN_PWR_B, enabled);
  if (verbose) {
    Serial.print(F("[PWR] B -> "));
    Serial.println(onoff(enabled));
  }
}

void setBothPower(bool enabled, bool verbose) {
  setStockPowerA(enabled, verbose);
  setStockPowerB(enabled, verbose);
}

void runStockStartupSequence(const __FlashStringHelper *tag) {
  Serial.print(F("[PWR] "));
  Serial.print(tag);
  Serial.println(F(" start"));

  setBothPower(false, true);
  delay(POWER_OFF_GUARD_MS);

  setStockPowerA(true, true);
  delay(POWER_A_TO_B_DELAY_MS);

  setStockPowerB(true, true);
  delay(POWER_BOOT_SETTLE_MS);

  syncSensorSnapshot();
  printPowerStatus();
  printSensorStatus();
  Serial.print(F("[PWR] "));
  Serial.print(tag);
  Serial.println(F(" done"));
}

void runStockCycleSequence() {
  runStockStartupSequence(F("CYCLE"));
}

// --------------------------- Sensor monitor ---------------------------
void pollSensors() {
  uint32_t now = millis();
  if (now - g_lastSensorPollMs < SENSOR_POLL_MS) return;
  g_lastSensorPollMs = now;

  bool rawA = readSensorPin(PIN_SENSOR_A);
  bool rawB = readSensorPin(PIN_SENSOR_B);

  if (rawA != g_lastRawA) {
    g_lastRawA = rawA;
    g_lastRawChangeAMs = now;
  }
  if (rawB != g_lastRawB) {
    g_lastRawB = rawB;
    g_lastRawChangeBMs = now;
  }

  bool updated = false;
  if ((now - g_lastRawChangeAMs) >= SENSOR_DEBOUNCE_MS && g_stableA != rawA) {
    g_stableA = rawA;
    updated = true;
  }
  if ((now - g_lastRawChangeBMs) >= SENSOR_DEBOUNCE_MS && g_stableB != rawB) {
    g_stableB = rawB;
    updated = true;
  }

  if (updated) {
    if (SENSOR_STATUS_LOG_ENABLED) {
      printSensorStatus();
    }
  }
}

// --------------------------- Serial command ---------------------------
bool parseOnOffArg(const String &arg, bool *out) {
  if (!out) return false;
  if (arg == "on" || arg == "1" || arg == "high") {
    *out = true;
    return true;
  }
  if (arg == "off" || arg == "0" || arg == "low") {
    *out = false;
    return true;
  }
  return false;
}

bool isUnsignedNumber(const String &s) {
  if (s.length() == 0) return false;
  for (size_t i = 0; i < s.length(); ++i) {
    if (!isDigit(s[i])) return false;
  }
  return true;
}

void handleCommand(const String &lineRaw) {
  if (lineRaw.length() == 0) return;

  String line = lineRaw;
  line.trim();
  if (line.length() == 0) return;

  String cmd = line;
  cmd.toLowerCase();

  if (cmd == "?" || cmd == "help") {
    printHelp();
    return;
  }
  if (cmd == "r") {
    printSensorStatus();
    printX9CStatus();
    printPowerStatus();
    return;
  }
  if (cmd == "+") {
    x9cStep(+1);
    printX9CStatus();
    return;
  }
  if (cmd == "-") {
    x9cStep(-1);
    printX9CStatus();
    return;
  }
  if (cmd == "min") {
    x9cSetTap(0);
    printX9CStatus();
    return;
  }
  if (cmd == "max") {
    x9cSetTap(X9C_MAX_TAP);
    printX9CStatus();
    return;
  }
  if (cmd == "sweep") {
    x9cSweepDemo();
    printX9CStatus();
    return;
  }
  if (cmd == "pon") {
    setBothPower(true, true);
    printPowerStatus();
    return;
  }
  if (cmd == "poff") {
    setBothPower(false, true);
    printPowerStatus();
    return;
  }
  if (cmd == "boot") {
    runStockStartupSequence(F("BOOT"));
    return;
  }
  if (cmd == "cycle") {
    runStockCycleSequence();
    return;
  }

  if (cmd.startsWith("pa ")) {
    String arg = cmd.substring(3);
    arg.trim();
    bool enabled = false;
    if (!parseOnOffArg(arg, &enabled)) {
      Serial.println(F("[ERR] pa expects on/off"));
      return;
    }
    setStockPowerA(enabled, true);
    printPowerStatus();
    return;
  }

  if (cmd.startsWith("pb ")) {
    String arg = cmd.substring(3);
    arg.trim();
    bool enabled = false;
    if (!parseOnOffArg(arg, &enabled)) {
      Serial.println(F("[ERR] pb expects on/off"));
      return;
    }
    setStockPowerB(enabled, true);
    printPowerStatus();
    return;
  }

  if (cmd.startsWith("s")) {
    String n = cmd.substring(1);
    n.trim();
    if (isUnsignedNumber(n)) {
      int target = n.toInt();
      x9cSetTap(target);
      printX9CStatus();
      return;
    }
  }

  Serial.print(F("[ERR] unknown command: "));
  Serial.println(lineRaw);
}

void pollSerial() {
  if (!Serial.available()) return;
  String line = Serial.readStringUntil('\n');
  line.trim();
  handleCommand(line);
}

// --------------------------- Arduino ---------------------------
void setup() {
  Serial.begin(115200);
  delay(1200);

  pinMode(PIN_SENSOR_A, SENSOR_USE_PULLUP ? INPUT_PULLUP : INPUT);
  pinMode(PIN_SENSOR_B, SENSOR_USE_PULLUP ? INPUT_PULLUP : INPUT);

  pinMode(PIN_X9C_INC, OUTPUT);
  pinMode(PIN_X9C_UD, OUTPUT);
  pinMode(PIN_X9C_CS, OUTPUT);
  digitalWrite(PIN_X9C_INC, HIGH);
  digitalWrite(PIN_X9C_UD, HIGH);
  digitalWrite(PIN_X9C_CS, HIGH);

  pinMode(PIN_PWR_A, OUTPUT);
  pinMode(PIN_PWR_B, OUTPUT);
  setBothPower(false, false);

  syncSensorSnapshot();

  if (CALIBRATE_TO_MIN_ON_BOOT) {
    x9cMoveToMin();
  } else {
    g_currentTap = 0;
  }

  if (AUTO_BOOT_STOCK_SEQUENCE_ON_BOOT) {
    runStockStartupSequence(F("AUTO_BOOT"));
  }

  Serial.println(F("[BOOT] UNO endurance mcu test ready"));
  printSensorStatus();
  printX9CStatus();
  printPowerStatus();
  printHelp();
}

void loop() {
  pollSensors();
  pollSerial();
}
