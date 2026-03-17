/*
  UNO endurance automation helper
  - D6/D7 simultaneous power control for endurance sequence
  - D5 start pulse for target MCU startup
  - Sensor monitor on D12 / D13
  - Automated endurance cycle runner for GUI endurance workflow

  Serial monitor: 115200 baud
*/

#include <Arduino.h>
#include <string.h>

// --------------------------- Pin assignment ---------------------------
static const uint8_t PIN_SENSOR_A = 12;
static const uint8_t PIN_SENSOR_B = 13;

// Optional manual X9C control is kept on module A only and initialized on demand.
static const uint8_t PIN_X9C_A_INC = 9;
static const uint8_t PIN_X9C_A_UD = 8;
static const uint8_t PIN_X9C_A_CS = 10;

static const uint8_t PIN_PWR_A = 6;
static const uint8_t PIN_PWR_B = 7;
static const uint8_t PIN_START_PULSE = 5;

// --------------------------- Behavior config ---------------------------
static const bool SENSOR_USE_PULLUP = false;
static const bool SENSOR_ON_LEVEL_HIGH = true;

static const bool POWER_ACTIVE_HIGH = true;
static const bool START_PULSE_ACTIVE_HIGH = true;
static const bool AUTO_BOOT_STOCK_SEQUENCE_ON_BOOT = false;

static const uint16_t SENSOR_POLL_MS = 20;
static const uint16_t SENSOR_DEBOUNCE_MS = 10;

static const uint16_t X9C_PULSE_US = 5;
static const uint16_t X9C_STEP_DELAY_MS = 2;
static const int X9C_MAX_TAP = 99;
static const long X9C_TOTAL_OHMS = 10000L;  // X9C103S = 10k

// Default endurance timing (aligned with GUI defaults)
static const uint16_t DEF_POWER_OFF_GUARD_MS = 0;
static const uint16_t DEF_POWER_A_TO_B_DELAY_MS = 2000;
static const uint16_t DEF_POWER_BOOT_SETTLE_MS = 2000;
static const uint16_t DEF_CONNECT_WAIT_MS = 500;
static const uint16_t DEF_DISCONNECT_WAIT_MS = 500;

// --------------------------- Runtime state ---------------------------
static uint32_t g_lastSensorPollMs = 0;

static bool g_lastRawA = LOW;
static bool g_lastRawB = LOW;
static bool g_stableA = LOW;
static bool g_stableB = LOW;
static uint32_t g_lastRawChangeAMs = 0;
static uint32_t g_lastRawChangeBMs = 0;

static bool g_powerAEnabled = false;
static bool g_powerBEnabled = false;
static bool g_startPulseEnabled = false;
static bool g_sequencePinsConfigured = false;
static bool g_x9cPinsInitialized = false;

struct X9cModuleState {
  const char *name;
  uint8_t pinInc;
  uint8_t pinUd;
  uint8_t pinCs;
  int currentTap;
};

static X9cModuleState g_x9cModules[] = {
    {"A", PIN_X9C_A_INC, PIN_X9C_A_UD, PIN_X9C_A_CS, -1},
};
static const uint8_t X9C_MODULE_COUNT = sizeof(g_x9cModules) / sizeof(g_x9cModules[0]);

bool isUnsignedNumber(const String &s);

// --------------------------- Endurance runtime ---------------------------
enum EnduranceStage : uint8_t {
  END_IDLE = 0,
  END_POWER_OFF_GUARD,
  END_POWER_ON_DELAY,
  END_START_PULSE,
  END_CONNECT_WINDOW,
  END_DISCONNECT_WINDOW,
};

static bool g_enduranceRunning = false;
static bool g_enduranceStopRequested = false;
static bool g_enduranceStopOnFail = false;
static bool g_enduranceCheckSensorOn = true;
static bool g_enduranceCheckSensorOff = true;

static uint16_t g_enduranceCyclesTarget = 0;
static uint16_t g_enduranceCycleCurrent = 0;
static uint16_t g_endurancePass = 0;
static uint16_t g_enduranceFail = 0;

static uint16_t g_powerOffGuardMs = DEF_POWER_OFF_GUARD_MS;
static uint16_t g_powerAToBDelayMs = DEF_POWER_A_TO_B_DELAY_MS;   // D6/D7 ON -> D5 ON delay
static uint16_t g_powerBootSettleMs = DEF_POWER_BOOT_SETTLE_MS;   // D5 ON duration
static uint16_t g_connectWaitMs = DEF_CONNECT_WAIT_MS;
static uint16_t g_disconnectWaitMs = DEF_DISCONNECT_WAIT_MS;

static EnduranceStage g_enduranceStage = END_IDLE;
static uint32_t g_enduranceStageStartMs = 0;
static bool g_cycleFailed = false;
static char g_cycleFailureClass[40] = "PASS";

// --------------------------- Utility ---------------------------
static const char *hl(bool v) { return v ? "HIGH" : "LOW"; }
static const char *onoff(bool v) { return v ? "ON" : "OFF"; }

void emitState(const __FlashStringHelper *state) {
  Serial.print(F("[STATE] "));
  Serial.println(state);
}

void emitStateText(const __FlashStringHelper *state, const char *text) {
  Serial.print(F("[STATE] "));
  Serial.print(state);
  Serial.print(F(" "));
  Serial.println(text ? text : "");
}

void emitStateKVU16(const __FlashStringHelper *state, const __FlashStringHelper *key, uint16_t value) {
  Serial.print(F("[STATE] "));
  Serial.print(state);
  Serial.print(F(" "));
  Serial.print(key);
  Serial.print(F("="));
  Serial.println(value);
}

bool readSensorPin(uint8_t pin) {
  return digitalRead(pin) == HIGH;
}

void printSensorStatus() {
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

void printX9CStatus(const X9cModuleState &module) {
  Serial.print(F("[X9C] "));
  Serial.print(module.name);
  Serial.print(F(" tap="));
  Serial.print(module.currentTap);
  Serial.print(F(" / "));
  Serial.print(X9C_MAX_TAP);
  Serial.print(F(", approx="));
  Serial.print((X9C_TOTAL_OHMS * (long)module.currentTap) / X9C_MAX_TAP);
  Serial.println(F(" ohm"));
}

void printAllX9CStatus() {
  for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) {
    printX9CStatus(g_x9cModules[i]);
  }
}

void printEnduranceStatus() {
  Serial.print(F("[END] running="));
  Serial.print(g_enduranceRunning ? F("1") : F("0"));
  Serial.print(F(" cycle="));
  Serial.print(g_enduranceCycleCurrent);
  Serial.print(F("/"));
  Serial.print(g_enduranceCyclesTarget);
  Serial.print(F(" pass="));
  Serial.print(g_endurancePass);
  Serial.print(F(" fail="));
  Serial.print(g_enduranceFail);
  Serial.print(F(" stage="));
  Serial.println((int)g_enduranceStage);
}

void printConfig() {
  Serial.println(F("[CFG] endurance config"));
  Serial.print(F("  off_guard_ms="));
  Serial.println(g_powerOffGuardMs);
  Serial.print(F("  power_to_d5_ms="));
  Serial.println(g_powerAToBDelayMs);
  Serial.print(F("  d5_pulse_ms="));
  Serial.println(g_powerBootSettleMs);
  Serial.print(F("  connect_wait_ms="));
  Serial.println(g_connectWaitMs);
  Serial.print(F("  disconnect_wait_ms="));
  Serial.println(g_disconnectWaitMs);
  Serial.print(F("  check_sensor_on="));
  Serial.println(g_enduranceCheckSensorOn ? F("1") : F("0"));
  Serial.print(F("  check_sensor_off="));
  Serial.println(g_enduranceCheckSensorOff ? F("1") : F("0"));
  Serial.print(F("  stop_on_fail="));
  Serial.println(g_enduranceStopOnFail ? F("1") : F("0"));
}

void printHelp() {
  Serial.println();
  Serial.println(F("=== UNO endurance automation command list ==="));
  Serial.println(F("status and debug:"));
  Serial.println(F("  r                     : print sensor + x9c + power + endurance status"));
  Serial.println(F("  cfg                   : print endurance config"));
  Serial.println(F("  ? / help              : help"));
  Serial.println(F("manual power control:"));
  Serial.println(F("  pa on|off             : stock A power"));
  Serial.println(F("  pb on|off             : stock B power"));
  Serial.println(F("  pon / poff            : both ON / both OFF"));
  Serial.println(F("  boot                  : D6/D7 ON -> wait -> D5 pulse"));
  Serial.println(F("x9c control (module A only):"));
  Serial.println(F("  +  -  min  max  sweep : apply to X9C A"));
  Serial.println(F("  s<N>                  : set X9C A tap (0..99), ex: s45"));
  Serial.println(F("  xa r|+|-|min|max|s<N>|sweep"));
  Serial.println(F("endurance automation:"));
  Serial.println(F("  run <cycles> [cw] [dw]: start endurance, cw/dw in ms"));
  Serial.println(F("  stop                  : request stop"));
  Serial.println(F("  set off <ms>          : power off guard"));
  Serial.println(F("  set ab <ms>           : D6/D7 ON -> D5 ON delay"));
  Serial.println(F("  set bs <ms>           : D5 ON duration"));
  Serial.println(F("  set cw <ms>           : connect wait"));
  Serial.println(F("  set dw <ms>           : power-OFF interval (500ms = 2Hz)"));
  Serial.println(F("  set son <0|1>         : check sensor in power-on phase"));
  Serial.println(F("  set sof <0|1>         : check sensor in power-off phase"));
  Serial.println(F("  set stopfail <0|1>    : stop endurance on first fail"));
  Serial.println();
}

// --------------------------- X9C103S control ---------------------------
void ensureX9cPinsReady() {
  if (g_x9cPinsInitialized) return;
  for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) {
    pinMode(g_x9cModules[i].pinInc, OUTPUT);
    pinMode(g_x9cModules[i].pinUd, OUTPUT);
    pinMode(g_x9cModules[i].pinCs, OUTPUT);
    digitalWrite(g_x9cModules[i].pinInc, HIGH);
    digitalWrite(g_x9cModules[i].pinUd, HIGH);
    digitalWrite(g_x9cModules[i].pinCs, HIGH);
  }
  g_x9cPinsInitialized = true;
}

void x9cPulseInc(const X9cModuleState &module) {
  ensureX9cPinsReady();
  digitalWrite(module.pinInc, HIGH);
  delayMicroseconds(X9C_PULSE_US);
  digitalWrite(module.pinInc, LOW);
  delayMicroseconds(X9C_PULSE_US);
  digitalWrite(module.pinInc, HIGH);
}

void x9cStepRaw(const X9cModuleState &module, bool up) {
  ensureX9cPinsReady();
  digitalWrite(module.pinCs, LOW);
  digitalWrite(module.pinUd, up ? HIGH : LOW);
  delayMicroseconds(X9C_PULSE_US);
  x9cPulseInc(module);
  delay(X9C_STEP_DELAY_MS);
  digitalWrite(module.pinCs, HIGH);  // store new position
  delayMicroseconds(X9C_PULSE_US);
}

void x9cMoveToMin(X9cModuleState &module) {
  ensureX9cPinsReady();
  // Over-step to guarantee minimum position.
  digitalWrite(module.pinCs, LOW);
  digitalWrite(module.pinUd, LOW);
  delayMicroseconds(X9C_PULSE_US);
  for (int i = 0; i < 120; ++i) {
    x9cPulseInc(module);
    delay(X9C_STEP_DELAY_MS);
  }
  digitalWrite(module.pinCs, HIGH);
  delayMicroseconds(X9C_PULSE_US);
  module.currentTap = 0;
}

void x9cSetTap(X9cModuleState &module, int target) {
  if (target < 0) target = 0;
  if (target > X9C_MAX_TAP) target = X9C_MAX_TAP;

  if (module.currentTap < 0) {
    x9cMoveToMin(module);
  }

  while (module.currentTap < target) {
    x9cStepRaw(module, true);
    module.currentTap++;
  }
  while (module.currentTap > target) {
    x9cStepRaw(module, false);
    module.currentTap--;
  }
}

void x9cStep(X9cModuleState &module, int delta) {
  if (module.currentTap < 0) {
    x9cMoveToMin(module);
  }
  x9cSetTap(module, module.currentTap + delta);
}

void x9cSweepDemo(X9cModuleState &module) {
  Serial.print(F("[X9C] "));
  Serial.print(module.name);
  Serial.println(F(" sweep start"));
  x9cSetTap(module, 0);
  for (int i = 1; i <= X9C_MAX_TAP; ++i) {
    x9cSetTap(module, i);
  }
  for (int i = X9C_MAX_TAP - 1; i >= 0; --i) {
    x9cSetTap(module, i);
  }
  Serial.print(F("[X9C] "));
  Serial.print(module.name);
  Serial.println(F(" sweep done"));
}

bool handleX9cModuleCommand(const String &cmd, X9cModuleState &module) {
  if (cmd == "r" || cmd == "status") {
    printX9CStatus(module);
    return true;
  }
  if (cmd == "+") {
    x9cStep(module, +1);
    printX9CStatus(module);
    return true;
  }
  if (cmd == "-") {
    x9cStep(module, -1);
    printX9CStatus(module);
    return true;
  }
  if (cmd == "min") {
    x9cSetTap(module, 0);
    printX9CStatus(module);
    return true;
  }
  if (cmd == "max") {
    x9cSetTap(module, X9C_MAX_TAP);
    printX9CStatus(module);
    return true;
  }
  if (cmd == "sweep") {
    x9cSweepDemo(module);
    printX9CStatus(module);
    return true;
  }
  if (cmd.startsWith("s")) {
    String n = cmd.substring(1);
    n.trim();
    if (isUnsignedNumber(n)) {
      x9cSetTap(module, n.toInt());
      printX9CStatus(module);
      return true;
    }
  }
  return false;
}

bool handleX9cAllCommand(const String &cmd) {
  const bool isTapSetCommand = cmd.startsWith("s") && isUnsignedNumber(cmd.substring(1));
  const bool isX9cCommand =
      (cmd == "+") || (cmd == "-") || (cmd == "min") || (cmd == "max") || (cmd == "sweep") || isTapSetCommand;

  if (!isX9cCommand) {
    return false;
  }
  if (cmd == "+") {
    for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) x9cStep(g_x9cModules[i], +1);
    printAllX9CStatus();
    return true;
  }
  if (cmd == "-") {
    for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) x9cStep(g_x9cModules[i], -1);
    printAllX9CStatus();
    return true;
  }
  if (cmd == "min") {
    for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) x9cSetTap(g_x9cModules[i], 0);
    printAllX9CStatus();
    return true;
  }
  if (cmd == "max") {
    for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) x9cSetTap(g_x9cModules[i], X9C_MAX_TAP);
    printAllX9CStatus();
    return true;
  }
  if (cmd == "sweep") {
    for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) x9cSweepDemo(g_x9cModules[i]);
    printAllX9CStatus();
    return true;
  }
  if (cmd.startsWith("s")) {
    String n = cmd.substring(1);
    n.trim();
    if (isUnsignedNumber(n)) {
      const int target = n.toInt();
      for (uint8_t i = 0; i < X9C_MODULE_COUNT; ++i) x9cSetTap(g_x9cModules[i], target);
      printAllX9CStatus();
      return true;
    }
  }
  return false;
}

// --------------------------- Power control ---------------------------
bool toPowerPinLevel(bool enabled) {
  return POWER_ACTIVE_HIGH ? enabled : !enabled;
}

bool toStartPulseLevel(bool enabled) {
  return START_PULSE_ACTIVE_HIGH ? enabled : !enabled;
}

void writePowerPin(uint8_t pin, bool enabled) {
  digitalWrite(pin, toPowerPinLevel(enabled) ? HIGH : LOW);
}

void writeStartPulsePin(bool enabled) {
  digitalWrite(PIN_START_PULSE, toStartPulseLevel(enabled) ? HIGH : LOW);
}

void ensureSequencePinsReady() {
  if (g_sequencePinsConfigured) return;
  pinMode(PIN_PWR_A, OUTPUT);
  pinMode(PIN_PWR_B, OUTPUT);
  pinMode(PIN_START_PULSE, OUTPUT);
  writePowerPin(PIN_PWR_A, false);
  writePowerPin(PIN_PWR_B, false);
  writeStartPulsePin(false);
  g_sequencePinsConfigured = true;
}

void releaseSequencePins() {
  if (!g_sequencePinsConfigured) return;
  writeStartPulsePin(false);
  writePowerPin(PIN_PWR_A, false);
  writePowerPin(PIN_PWR_B, false);
  digitalWrite(PIN_START_PULSE, LOW);
  digitalWrite(PIN_PWR_A, LOW);
  digitalWrite(PIN_PWR_B, LOW);
  pinMode(PIN_START_PULSE, INPUT);
  pinMode(PIN_PWR_A, INPUT);
  pinMode(PIN_PWR_B, INPUT);
  g_sequencePinsConfigured = false;
  g_powerAEnabled = false;
  g_powerBEnabled = false;
  g_startPulseEnabled = false;
}

void setStartPulse(bool enabled, bool verbose) {
  ensureSequencePinsReady();
  g_startPulseEnabled = enabled;
  writeStartPulsePin(enabled);
  if (verbose) {
    Serial.print(F("[PULSE] D5 -> "));
    Serial.println(onoff(enabled));
    emitState(enabled ? F("START_PULSE_ON") : F("START_PULSE_OFF"));
  }
}

void runStartPulseSequence(const __FlashStringHelper *tag) {
  Serial.print(F("[PULSE] "));
  Serial.print(tag);
  Serial.print(F(" D5 pulse "));
  Serial.print(g_powerBootSettleMs);
  Serial.println(F(" ms"));
  setStartPulse(true, true);
  delay(g_powerBootSettleMs);
  setStartPulse(false, true);
}

void setStockPowerA(bool enabled, bool verbose) {
  ensureSequencePinsReady();
  g_powerAEnabled = enabled;
  writePowerPin(PIN_PWR_A, enabled);
  if (verbose) {
    Serial.print(F("[PWR] A -> "));
    Serial.println(onoff(enabled));
  }
  emitState(enabled ? F("POWER_A_ON") : F("POWER_A_OFF"));
}

void setStockPowerB(bool enabled, bool verbose) {
  ensureSequencePinsReady();
  g_powerBEnabled = enabled;
  writePowerPin(PIN_PWR_B, enabled);
  if (verbose) {
    Serial.print(F("[PWR] B -> "));
    Serial.println(onoff(enabled));
  }
  emitState(enabled ? F("POWER_B_ON") : F("POWER_B_OFF"));
}

void setBothPower(bool enabled, bool verbose) {
  setStockPowerA(enabled, verbose);
  setStockPowerB(enabled, verbose);
  if (!enabled && g_startPulseEnabled) {
    setStartPulse(false, verbose);
  }
}

// --------------------------- Sensor monitor ---------------------------
void syncSensorSnapshot() {
  const uint32_t now = millis();
  g_lastRawA = readSensorPin(PIN_SENSOR_A);
  g_lastRawB = readSensorPin(PIN_SENSOR_B);
  g_stableA = g_lastRawA;
  g_stableB = g_lastRawB;
  g_lastRawChangeAMs = now;
  g_lastRawChangeBMs = now;
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

bool expectedSensorOnLevel() {
  return SENSOR_ON_LEVEL_HIGH ? HIGH : LOW;
}

void markCycleFail(const char *klass) {
  if (!g_cycleFailed) {
    g_cycleFailed = true;
    strncpy(g_cycleFailureClass, klass, sizeof(g_cycleFailureClass) - 1);
    g_cycleFailureClass[sizeof(g_cycleFailureClass) - 1] = '\0';
    emitStateText(F("CYCLE_FAIL"), g_cycleFailureClass);
  }
}

bool checkSensorAtCheckpoint(bool expectOn, const __FlashStringHelper *phaseName) {
  const bool expected = expectOn ? expectedSensorOnLevel() : !expectedSensorOnLevel();
  const bool okA = (g_stableA == expected);
  const bool okB = (g_stableB == expected);
  Serial.print(F("[CHK] "));
  Serial.print(phaseName);
  Serial.print(F(" expect="));
  Serial.print(hl(expected));
  Serial.print(F(" A="));
  Serial.print(hl(g_stableA));
  Serial.print(F(" B="));
  Serial.println(hl(g_stableB));
  if (okA && okB) {
    emitState(expectOn ? F("SENSOR_ON_OK") : F("SENSOR_OFF_OK"));
    return true;
  }
  emitState(expectOn ? F("SENSOR_ON_NG") : F("SENSOR_OFF_NG"));
  if (expectOn) {
    markCycleFail("SENSOR_ON_MISMATCH");
  } else {
    markCycleFail("SENSOR_OFF_MISMATCH");
  }
  return false;
}

// --------------------------- Endurance automation ---------------------------
void enterEnduranceStage(EnduranceStage stage) {
  g_enduranceStage = stage;
  g_enduranceStageStartMs = millis();
}

void beginCycle() {
  g_cycleFailed = false;
  strncpy(g_cycleFailureClass, "PASS", sizeof(g_cycleFailureClass) - 1);
  g_cycleFailureClass[sizeof(g_cycleFailureClass) - 1] = '\0';

  Serial.print(F("[END] cycle "));
  Serial.print(g_enduranceCycleCurrent);
  Serial.print(F("/"));
  Serial.print(g_enduranceCyclesTarget);
  Serial.println(F(" start"));
  Serial.print(F("[STATE] CYCLE_START "));
  Serial.print(g_enduranceCycleCurrent);
  Serial.print(F("/"));
  Serial.println(g_enduranceCyclesTarget);

  setBothPower(false, true);
  enterEnduranceStage(END_POWER_OFF_GUARD);
}

void finishEndurance(bool stopped) {
  g_enduranceRunning = false;
  g_enduranceStopRequested = false;
  g_enduranceStage = END_IDLE;
  setBothPower(false, true);
  releaseSequencePins();

  Serial.print(F("[END] done pass="));
  Serial.print(g_endurancePass);
  Serial.print(F(" fail="));
  Serial.println(g_enduranceFail);

  Serial.print(F("[STATE] ENDURANCE_DONE pass="));
  Serial.print(g_endurancePass);
  Serial.print(F(" fail="));
  Serial.print(g_enduranceFail);
  Serial.print(F(" stopped="));
  Serial.println(stopped ? F("1") : F("0"));
}

void finalizeCycle() {
  if (g_cycleFailed) {
    g_enduranceFail++;
  } else {
    g_endurancePass++;
    emitState(F("CYCLE_PASS"));
  }

  Serial.print(F("[END] cycle "));
  Serial.print(g_enduranceCycleCurrent);
  Serial.print(F(" result="));
  if (g_cycleFailed) {
    Serial.println(g_cycleFailureClass);
  } else {
    Serial.println(F("PASS"));
  }

  const bool shouldStop =
      g_enduranceStopRequested ||
      (g_enduranceStopOnFail && g_cycleFailed) ||
      (g_enduranceCycleCurrent >= g_enduranceCyclesTarget);

  if (shouldStop) {
    finishEndurance(g_enduranceStopRequested || (g_enduranceStopOnFail && g_cycleFailed));
    return;
  }

  g_enduranceCycleCurrent++;
  beginCycle();
}

void startEndurance(uint16_t cycles) {
  if (g_enduranceRunning) {
    Serial.println(F("[ERR] endurance already running"));
    return;
  }
  if (cycles == 0) {
    Serial.println(F("[ERR] run cycles must be >= 1"));
    return;
  }
  g_enduranceCyclesTarget = cycles;
  g_enduranceCycleCurrent = 1;
  g_endurancePass = 0;
  g_enduranceFail = 0;
  g_enduranceStopRequested = false;
  g_enduranceRunning = true;

  Serial.print(F("[END] start cycles="));
  Serial.print(cycles);
  Serial.print(F(" cw="));
  Serial.print(g_connectWaitMs);
  Serial.print(F(" dw="));
  Serial.println(g_disconnectWaitMs);

  Serial.print(F("[STATE] ENDURANCE_START cycles="));
  Serial.print(cycles);
  Serial.print(F(" connect_wait_ms="));
  Serial.print(g_connectWaitMs);
  Serial.print(F(" disconnect_wait_ms="));
  Serial.println(g_disconnectWaitMs);

  beginCycle();
}

void requestStopEndurance() {
  if (!g_enduranceRunning) {
    Serial.println(F("[END] stop ignored (not running)"));
    return;
  }
  g_enduranceStopRequested = true;
  emitState(F("ENDURANCE_STOP_REQUEST"));
}

void updateEndurance() {
  if (!g_enduranceRunning) return;
  const uint32_t now = millis();
  const uint32_t elapsed = now - g_enduranceStageStartMs;

  switch (g_enduranceStage) {
    case END_POWER_OFF_GUARD:
      if (elapsed >= g_powerOffGuardMs) {
        setBothPower(true, true);
        enterEnduranceStage(END_POWER_ON_DELAY);
      }
      break;

    case END_POWER_ON_DELAY:
      if (elapsed >= g_powerAToBDelayMs) {
        setStartPulse(true, true);
        enterEnduranceStage(END_START_PULSE);
      }
      break;

    case END_START_PULSE:
      if (elapsed >= g_powerBootSettleMs) {
        setStartPulse(false, true);
        if (g_enduranceCheckSensorOn) {
          checkSensorAtCheckpoint(true, F("POWER_ON_CHECK"));
        }
        emitStateKVU16(F("CONNECT_WINDOW_BEGIN"), F("ms"), g_connectWaitMs);
        enterEnduranceStage(END_CONNECT_WINDOW);
      }
      break;

    case END_CONNECT_WINDOW:
      if (elapsed >= g_connectWaitMs) {
        emitState(F("CONNECT_WINDOW_END"));
        setBothPower(false, true);
        emitStateKVU16(F("DISCONNECT_WINDOW_BEGIN"), F("ms"), g_disconnectWaitMs);
        enterEnduranceStage(END_DISCONNECT_WINDOW);
      }
      break;

    case END_DISCONNECT_WINDOW:
      if (elapsed >= g_disconnectWaitMs) {
        emitState(F("DISCONNECT_WINDOW_END"));
        if (g_enduranceCheckSensorOff) {
          checkSensorAtCheckpoint(false, F("POWER_OFF_CHECK"));
        }
        finalizeCycle();
      }
      break;

    case END_IDLE:
    default:
      break;
  }
}

void runStockStartupSequence(const __FlashStringHelper *tag) {
  Serial.print(F("[PWR] "));
  Serial.print(tag);
  Serial.println(F(" start"));
  setBothPower(false, true);
  delay(g_powerOffGuardMs);
  setBothPower(true, true);
  delay(g_powerAToBDelayMs);
  runStartPulseSequence(tag);
  syncSensorSnapshot();
  printPowerStatus();
  printSensorStatus();
  Serial.print(F("[PWR] "));
  Serial.print(tag);
  Serial.println(F(" done"));
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

void applySetCommand(const String &key, const String &value) {
  if (!isUnsignedNumber(value)) {
    Serial.println(F("[ERR] set value must be unsigned number"));
    return;
  }
  const long v = value.toInt();

  if (key == "off") {
    g_powerOffGuardMs = (uint16_t)max(0L, min(60000L, v));
  } else if (key == "ab") {
    g_powerAToBDelayMs = (uint16_t)max(0L, min(60000L, v));
  } else if (key == "bs") {
    g_powerBootSettleMs = (uint16_t)max(0L, min(60000L, v));
  } else if (key == "cw") {
    g_connectWaitMs = (uint16_t)max(0L, min(60000L, v));
  } else if (key == "dw") {
    g_disconnectWaitMs = (uint16_t)max(0L, min(60000L, v));
  } else if (key == "son") {
    g_enduranceCheckSensorOn = (v != 0);
  } else if (key == "sof") {
    g_enduranceCheckSensorOff = (v != 0);
  } else if (key == "stopfail") {
    g_enduranceStopOnFail = (v != 0);
  } else {
    Serial.print(F("[ERR] unknown set key: "));
    Serial.println(key);
    return;
  }

  emitStateText(F("CONFIG_UPDATED"), key.c_str());
  printConfig();
}

void handleRunCommand(const String &cmd) {
  String rest = cmd.substring(3);
  rest.trim();
  if (rest.length() == 0) {
    Serial.println(F("[ERR] usage: run <cycles> [connect_wait_ms] [disconnect_wait_ms]"));
    return;
  }

  int firstSpace = rest.indexOf(' ');
  String cyclesText = rest;
  String remain = "";
  if (firstSpace >= 0) {
    cyclesText = rest.substring(0, firstSpace);
    remain = rest.substring(firstSpace + 1);
    remain.trim();
  }

  if (!isUnsignedNumber(cyclesText)) {
    Serial.println(F("[ERR] run cycles must be number"));
    return;
  }
  const uint16_t cycles = (uint16_t)max(1L, min(10000L, cyclesText.toInt()));

  if (remain.length() > 0) {
    int secondSpace = remain.indexOf(' ');
    String cwText = remain;
    String dwText = "";
    if (secondSpace >= 0) {
      cwText = remain.substring(0, secondSpace);
      dwText = remain.substring(secondSpace + 1);
      dwText.trim();
    }
    if (!isUnsignedNumber(cwText)) {
      Serial.println(F("[ERR] run connect_wait_ms must be number"));
      return;
    }
    g_connectWaitMs = (uint16_t)max(0L, min(60000L, cwText.toInt()));
    if (dwText.length() > 0) {
      if (!isUnsignedNumber(dwText)) {
        Serial.println(F("[ERR] run disconnect_wait_ms must be number"));
        return;
      }
      g_disconnectWaitMs = (uint16_t)max(0L, min(60000L, dwText.toInt()));
    }
  }

  startEndurance(cycles);
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
  if (cmd == "r" || cmd == "status") {
    printSensorStatus();
    printAllX9CStatus();
    printPowerStatus();
    printEnduranceStatus();
    return;
  }
  if (cmd == "cfg") {
    printConfig();
    return;
  }

  if (cmd.startsWith("xa ")) {
    String sub = cmd.substring(3);
    sub.trim();
    if (handleX9cModuleCommand(sub, g_x9cModules[0])) {
      return;
    }
    Serial.print(F("[ERR] unknown X9C A command: "));
    Serial.println(sub);
    return;
  }
  if (cmd.startsWith("xb ")) {
    Serial.println(F("[ERR] X9C B is not available in this sequence build"));
    return;
  }
  if (handleX9cAllCommand(cmd)) {
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
  if (cmd == "stop") {
    requestStopEndurance();
    return;
  }
  if (cmd.startsWith("run")) {
    handleRunCommand(cmd);
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

  if (cmd.startsWith("set ")) {
    String remain = cmd.substring(4);
    remain.trim();
    const int sp = remain.indexOf(' ');
    if (sp <= 0) {
      Serial.println(F("[ERR] usage: set <key> <value>"));
      return;
    }
    String key = remain.substring(0, sp);
    key.trim();
    String value = remain.substring(sp + 1);
    value.trim();
    applySetCommand(key, value);
    return;
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

  pinMode(PIN_PWR_A, INPUT);
  pinMode(PIN_PWR_B, INPUT);
  pinMode(PIN_START_PULSE, INPUT);
  digitalWrite(PIN_PWR_A, LOW);
  digitalWrite(PIN_PWR_B, LOW);
  digitalWrite(PIN_START_PULSE, LOW);

  syncSensorSnapshot();

  emitState(F("MCU_READY"));
  Serial.println(F("[BOOT] UNO endurance automation ready"));

  if (AUTO_BOOT_STOCK_SEQUENCE_ON_BOOT) {
    runStockStartupSequence(F("AUTO_BOOT"));
  }

  printSensorStatus();
  printAllX9CStatus();
  printPowerStatus();
  printConfig();
  printHelp();
}

void loop() {
  pollSensors();
  pollSerial();
  updateEndurance();
}
