/*
  X9C103S controller (Arduino UNO)
  - Serial command based wiper control
  - Pins: INC, U/D, CS

  Serial monitor: 115200 baud
*/

#include <Arduino.h>

// --------------------------- Pin assignment ---------------------------
static const uint8_t PIN_X9C_INC = 9;
static const uint8_t PIN_X9C_UD = 8;
static const uint8_t PIN_X9C_CS = 10;

// --------------------------- Config ---------------------------
static const uint16_t X9C_PULSE_US = 5;
static const uint16_t X9C_STEP_DELAY_MS = 2;
static const int X9C_MAX_TAP = 99;
static const long X9C_TOTAL_OHMS = 10000L;  // X9C103S = 10k
static const bool CALIBRATE_TO_MIN_ON_BOOT = true;

// --------------------------- Runtime ---------------------------
static int g_currentTap = -1;

// --------------------------- Utility ---------------------------
void printStatus() {
  long approxOhm = (X9C_TOTAL_OHMS * (long)g_currentTap) / X9C_MAX_TAP;
  Serial.print(F("[X9C] tap="));
  Serial.print(g_currentTap);
  Serial.print(F(" / "));
  Serial.print(X9C_MAX_TAP);
  Serial.print(F(", approx="));
  Serial.print(approxOhm);
  Serial.println(F(" ohm"));
}

void printHelp() {
  Serial.println();
  Serial.println(F("=== X9C103S command list ==="));
  Serial.println(F("  r         : status"));
  Serial.println(F("  +         : tap +1"));
  Serial.println(F("  -         : tap -1"));
  Serial.println(F("  min       : tap 0"));
  Serial.println(F("  max       : tap 99"));
  Serial.println(F("  s<N>      : set tap (0..99), ex: s45"));
  Serial.println(F("  sweep     : 0 -> 99 -> 0"));
  Serial.println(F("  ? / help  : help"));
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
  digitalWrite(PIN_X9C_CS, HIGH);  // Store new position to NVM
  delayMicroseconds(X9C_PULSE_US);
}

void x9cMoveToMin() {
  // Over-step so the internal counter surely reaches 0.
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
  x9cSetTap(g_currentTap + delta);
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

// --------------------------- Serial command ---------------------------
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
    printStatus();
    return;
  }
  if (cmd == "+") {
    x9cStep(+1);
    printStatus();
    return;
  }
  if (cmd == "-") {
    x9cStep(-1);
    printStatus();
    return;
  }
  if (cmd == "min") {
    x9cSetTap(0);
    printStatus();
    return;
  }
  if (cmd == "max") {
    x9cSetTap(X9C_MAX_TAP);
    printStatus();
    return;
  }
  if (cmd == "sweep") {
    x9cSweepDemo();
    printStatus();
    return;
  }
  if (cmd.startsWith("s")) {
    String n = cmd.substring(1);
    n.trim();
    if (isUnsignedNumber(n)) {
      x9cSetTap(n.toInt());
      printStatus();
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
  delay(300);

  pinMode(PIN_X9C_INC, OUTPUT);
  pinMode(PIN_X9C_UD, OUTPUT);
  pinMode(PIN_X9C_CS, OUTPUT);
  digitalWrite(PIN_X9C_INC, HIGH);
  digitalWrite(PIN_X9C_UD, HIGH);
  digitalWrite(PIN_X9C_CS, HIGH);

  if (CALIBRATE_TO_MIN_ON_BOOT) {
    x9cMoveToMin();
  } else {
    g_currentTap = 0;
  }

  Serial.println(F("[BOOT] X9C103S controller ready"));
  printStatus();
  printHelp();
}

void loop() {
  pollSerial();
}
