/*
  UNO endurance test helper
  - Digital light sensor monitor on D12 / D13
  - X9C103S digital potentiometer control (INC/U-D/CS)

  Serial monitor: 115200 baud
*/

#include <Arduino.h>

// --------------------------- Pin assignment ---------------------------
static const uint8_t PIN_SENSOR_A = 12;
static const uint8_t PIN_SENSOR_B = 13;

static const uint8_t PIN_X9C_INC = 9;
static const uint8_t PIN_X9C_UD = 8;
static const uint8_t PIN_X9C_CS = 10;

// --------------------------- Behavior config ---------------------------
static const bool SENSOR_USE_PULLUP = false;
static const bool CALIBRATE_TO_MIN_ON_BOOT = true;

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

// --------------------------- Utility ---------------------------
static const char* hl(bool v) { return v ? "HIGH" : "LOW"; }

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
  Serial.print(F("[SENS] D12="));
  Serial.print(hl(g_stableA));
  Serial.print(F(", D13="));
  Serial.println(hl(g_stableB));
}

void printHelp() {
  Serial.println();
  Serial.println(F("=== UNO endurance test command list ==="));
  Serial.println(F("  r           : print sensor + x9c status"));
  Serial.println(F("  +           : x9c tap +1"));
  Serial.println(F("  -           : x9c tap -1"));
  Serial.println(F("  min         : x9c -> tap 0"));
  Serial.println(F("  max         : x9c -> tap 99"));
  Serial.println(F("  s<N>        : x9c set tap (0..99), ex: s45"));
  Serial.println(F("  sweep       : x9c sweep 0->99->0"));
  Serial.println(F("  ?           : help"));
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

// --------------------------- Sensor monitor ---------------------------
bool readSensorPin(uint8_t pin) {
  return digitalRead(pin) == HIGH;
}

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
    printSensorStatus();
  }
}

// --------------------------- Serial command ---------------------------
void handleCommand(const String& line) {
  if (line.length() == 0) return;

  if (line == "?" || line == "help") {
    printHelp();
    return;
  }
  if (line == "r") {
    printSensorStatus();
    printX9CStatus();
    return;
  }
  if (line == "+") {
    x9cStep(+1);
    printX9CStatus();
    return;
  }
  if (line == "-") {
    x9cStep(-1);
    printX9CStatus();
    return;
  }
  if (line == "min") {
    x9cSetTap(0);
    printX9CStatus();
    return;
  }
  if (line == "max") {
    x9cSetTap(X9C_MAX_TAP);
    printX9CStatus();
    return;
  }
  if (line == "sweep") {
    x9cSweepDemo();
    printX9CStatus();
    return;
  }
  if (line.startsWith("s")) {
    int target = line.substring(1).toInt();
    x9cSetTap(target);
    printX9CStatus();
    return;
  }

  Serial.print(F("[ERR] unknown command: "));
  Serial.println(line);
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

  g_lastRawA = readSensorPin(PIN_SENSOR_A);
  g_lastRawB = readSensorPin(PIN_SENSOR_B);
  g_stableA = g_lastRawA;
  g_stableB = g_lastRawB;
  g_lastRawChangeAMs = millis();
  g_lastRawChangeBMs = millis();

  if (CALIBRATE_TO_MIN_ON_BOOT) {
    x9cMoveToMin();
  } else {
    g_currentTap = 0;
  }

  Serial.println(F("[BOOT] UNO endurance mcu test ready"));
  printSensorStatus();
  printX9CStatus();
  printHelp();
}

void loop() {
  pollSensors();
  pollSerial();
}
