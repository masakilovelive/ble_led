/*
  UNO endurance automation helper
  - Stock A/B power control with staged boot sequence
  - Sensor monitor on D12 / D13
  - X9C103S digital potentiometer control (INC/U-D/CS)
  - Automated endurance cycle runner for GUI endurance workflow

  Serial monitor: 115200 baud
*/

#include <Arduino.h>
#include <string.h>

// --------------------------- Pin assignment ---------------------------
static const uint8_t PIN_SENSOR_A = 12;
static const uint8_t PIN_SENSOR_B = 13;

static const uint8_t PIN_X9C_INC = 9;
static const uint8_t PIN_X9C_UD = 8;
static const uint8_t PIN_X9C_CS = 10;

static const uint8_t PIN_PWR_A = 6;
static const uint8_t PIN_PWR_B = 7;

// --------------------------- Behavior config ---------------------------
static const bool SENSOR_USE_PULLUP = false;
static const bool SENSOR_ON_LEVEL_HIGH = true;
static const bool CALIBRATE_TO_MIN_ON_BOOT = true;

static const bool POWER_ACTIVE_HIGH = true;
static const bool AUTO_BOOT_STOCK_SEQUENCE_ON_BOOT = true;

static const uint16_t SENSOR_POLL_MS = 20;
static const uint16_t SENSOR_DEBOUNCE_MS = 10;

static const uint16_t X9C_PULSE_US = 5;
static const uint16_t X9C_STEP_DELAY_MS = 2;
static const int X9C_MAX_TAP = 99;
static const long X9C_TOTAL_OHMS = 10000L;  // X9C103S = 10k

// Default endurance timing (aligned with GUI defaults)
static const uint16_t DEF_POWER_OFF_GUARD_MS = 300;
static const uint16_t DEF_POWER_A_TO_B_DELAY_MS = 700;
static const uint16_t DEF_POWER_BOOT_SETTLE_MS = 1500;
static const uint16_t DEF_CONNECT_WAIT_MS = 500;
static const uint16_t DEF_DISCONNECT_WAIT_MS = 500;

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

// --------------------------- Endurance runtime ---------------------------
enum EnduranceStage : uint8_t {
  END_IDLE = 0,
  END_POWER_OFF_GUARD,
  END_POWER_A_DELAY,
  END_POWER_BOOT_SETTLE,
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
static uint16_t g_powerAToBDelayMs = DEF_POWER_A_TO_B_DELAY_MS;
static uint16_t g_powerBootSettleMs = DEF_POWER_BOOT_SETTLE_MS;
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
  Serial.print(F("  a_to_b_ms="));
  Serial.println(g_powerAToBDelayMs);
  Serial.print(F("  boot_settle_ms="));
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
  Serial.println(F("  boot                  : OFF->A->B one-shot boot sequence"));
  Serial.println(F("x9c control:"));
  Serial.println(F("  +  -  min  max  sweep : x9c commands"));
  Serial.println(F("  s<N>                  : set x9c tap (0..99), ex: s45"));
  Serial.println(F("endurance automation:"));
  Serial.println(F("  run <cycles> [cw] [dw]: start endurance, cw/dw in ms"));
  Serial.println(F("  stop                  : request stop"));
  Serial.println(F("  set off <ms>          : power off guard"));
  Serial.println(F("  set ab <ms>           : A->B delay"));
  Serial.println(F("  set bs <ms>           : boot settle"));
  Serial.println(F("  set cw <ms>           : connect wait"));
  Serial.println(F("  set dw <ms>           : disconnect wait"));
  Serial.println(F("  set son <0|1>         : check sensor in power-on phase"));
  Serial.println(F("  set sof <0|1>         : check sensor in power-off phase"));
  Serial.println(F("  set stopfail <0|1>    : stop endurance on first fail"));
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

// --------------------------- Power control ---------------------------
bool toPowerPinLevel(bool enabled) {
  return POWER_ACTIVE_HIGH ? enabled : !enabled;
}

void writePowerPin(uint8_t pin, bool enabled) {
  digitalWrite(pin, toPowerPinLevel(enabled) ? HIGH : LOW);
}

void setStockPowerA(bool enabled, bool verbose) {
  g_powerAEnabled = enabled;
  writePowerPin(PIN_PWR_A, enabled);
  if (verbose) {
    Serial.print(F("[PWR] A -> "));
    Serial.println(onoff(enabled));
  }
  emitState(enabled ? F("POWER_A_ON") : F("POWER_A_OFF"));
}

void setStockPowerB(bool enabled, bool verbose) {
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
        setStockPowerA(true, true);
        enterEnduranceStage(END_POWER_A_DELAY);
      }
      break;

    case END_POWER_A_DELAY:
      if (elapsed >= g_powerAToBDelayMs) {
        setStockPowerB(true, true);
        enterEnduranceStage(END_POWER_BOOT_SETTLE);
      }
      break;

    case END_POWER_BOOT_SETTLE:
      if (elapsed >= g_powerBootSettleMs) {
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
  setStockPowerA(true, true);
  delay(g_powerAToBDelayMs);
  setStockPowerB(true, true);
  delay(g_powerBootSettleMs);
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
    g_powerOffGuardMs = (uint16_t)max(1L, min(60000L, v));
  } else if (key == "ab") {
    g_powerAToBDelayMs = (uint16_t)max(1L, min(60000L, v));
  } else if (key == "bs") {
    g_powerBootSettleMs = (uint16_t)max(1L, min(60000L, v));
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
    printX9CStatus();
    printPowerStatus();
    printEnduranceStatus();
    return;
  }
  if (cmd == "cfg") {
    printConfig();
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
  if (cmd.startsWith("s")) {
    String n = cmd.substring(1);
    n.trim();
    if (isUnsignedNumber(n)) {
      x9cSetTap(n.toInt());
      printX9CStatus();
      return;
    }
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

  emitState(F("MCU_READY"));
  Serial.println(F("[BOOT] UNO endurance automation ready"));

  if (AUTO_BOOT_STOCK_SEQUENCE_ON_BOOT) {
    runStockStartupSequence(F("AUTO_BOOT"));
  }

  printSensorStatus();
  printX9CStatus();
  printPowerStatus();
  printConfig();
  printHelp();
}

void loop() {
  pollSensors();
  pollSerial();
  updateEndurance();
}
