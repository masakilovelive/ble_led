#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_GC9A01.h>
#include <HX711.h>

// ===== GC9A01 wiring for Arduino UNO =====
// NOTE: GC9A01 は 3.3V ロジックです。UNO から直接駆動する場合はレベルシフタを使用してください。
static constexpr uint8_t PIN_TFT_CS = 10;   // SPI CS
static constexpr uint8_t PIN_TFT_DC = 9;    // Data/Command
static constexpr uint8_t PIN_TFT_RST = 8;   // Reset
static constexpr uint8_t PIN_TFT_BL = 6;    // Backlight (PWM可能なピンを推奨)

Adafruit_GC9A01 tft(PIN_TFT_CS, PIN_TFT_DC, PIN_TFT_RST);

// ===== UI colors =====
uint16_t COLOR_BG;
uint16_t COLOR_PANEL;
uint16_t COLOR_ACCENT_TITLE;
uint16_t COLOR_ACCENT_TARGET;
uint16_t COLOR_ACCENT_REMAIN;
uint16_t COLOR_ACCENT_EVENTS;

// ===== Button configuration =====
// D2/D3 は外部割り込みピン。ポーリングでも動作しますが余裕があれば attachInterrupt に変更可能です。
static constexpr uint8_t PIN_BTN_SET = 3;
static constexpr uint8_t PIN_BTN_COUNT = 2;
static constexpr uint16_t TARGET_MIN = 5;
static constexpr uint16_t TARGET_MAX = 200;
static constexpr uint16_t TARGET_STEP = 5;
static constexpr uint16_t LONG_PRESS_MS = 800;
static constexpr uint16_t DEBOUNCE_MS = 25;

struct ButtonState {
  uint8_t pin;
  bool lastReading = HIGH;
  bool stableState = HIGH;
  unsigned long lastChange = 0;
  unsigned long pressedAt = 0;
  bool longReported = false;
};

ButtonState btnSet{PIN_BTN_SET};
ButtonState btnCount{PIN_BTN_COUNT};

// ===== HX711 configuration =====
static constexpr uint8_t PIN_HX711_DATA = 4;  // DOUT
static constexpr uint8_t PIN_HX711_SCK = 5;   // SCK
static constexpr uint8_t HX_GAIN = 128;
static constexpr uint8_t HX_AVERAGE_SAMPLES = 10;
static constexpr uint16_t HX_SAMPLE_INTERVAL_MS = 200;

static constexpr long DIFF_THRESHOLD = 500;   // >0: ±検出, <0: マイナス方向のみ

HX711 scale;
bool hxReady = false;
long hxBaseline = 0;
long hxRaw = 0;
long hxDiff = 0;
unsigned long lastSample = 0;

// ===== Counters =====
uint16_t targetCount = 50;
uint16_t remainingCount = targetCount;
uint32_t sheetEvents = 0;
bool aboveThreshold = false;
bool displayDirty = true;

// ===== Serial plotter helpers =====
static constexpr uint8_t BUFFER_SIZE = 100;
long diffBuffer[BUFFER_SIZE];
uint8_t sampleCount = 0;
long graphMin = 0;
long graphMax = 0;
bool graphStatsValid = false;

// ===== Helpers =====
void setupBacklight() {
  pinMode(PIN_TFT_BL, OUTPUT);
  analogWrite(PIN_TFT_BL, 220);  // 0-255
}

void setupButtons() {
  pinMode(PIN_BTN_SET, INPUT_PULLUP);
  pinMode(PIN_BTN_COUNT, INPUT_PULLUP);
}

bool processButton(ButtonState &btn, bool &longPress) {
  unsigned long now = millis();
  bool reading = digitalRead(btn.pin);
  if (reading != btn.lastReading) {
    btn.lastReading = reading;
    btn.lastChange = now;
  }

  longPress = false;
  if (now - btn.lastChange < DEBOUNCE_MS) {
    return false;
  }

  if (reading != btn.stableState) {
    btn.stableState = reading;
    if (btn.stableState == LOW) {
      btn.pressedAt = now;
      btn.longReported = false;
    } else if (!btn.longReported && (now - btn.pressedAt) < LONG_PRESS_MS) {
      return true;  // short press
    }
  } else if (btn.stableState == LOW && !btn.longReported &&
             (now - btn.pressedAt) >= LONG_PRESS_MS) {
    btn.longReported = true;
    longPress = true;
  }

  return false;
}

void pushSample(long diff) {
  if (sampleCount < BUFFER_SIZE) {
    diffBuffer[sampleCount++] = diff;
  } else {
    memmove(diffBuffer, diffBuffer + 1, (BUFFER_SIZE - 1) * sizeof(long));
    diffBuffer[BUFFER_SIZE - 1] = diff;
  }

  if (sampleCount == 0) {
    graphStatsValid = false;
    return;
  }

  long minVal = diffBuffer[0];
  long maxVal = diffBuffer[0];
  for (uint8_t i = 1; i < sampleCount; ++i) {
    minVal = min(minVal, diffBuffer[i]);
    maxVal = max(maxVal, diffBuffer[i]);
  }
  if (minVal == maxVal) {
    minVal -= 1;
    maxVal += 1;
  }
  graphMin = minVal;
  graphMax = maxVal;
  graphStatsValid = true;
}

void publishSerialPlot() {
  if (!graphStatsValid) {
    return;
  }
  Serial.print(F("raw:"));
  Serial.print(hxRaw);
  Serial.print(F("\tdiff:"));
  Serial.print(hxDiff);
  Serial.print(F("\tmin:"));
  Serial.print(graphMin);
  Serial.print(F("\tmax:"));
  Serial.print(graphMax);
  Serial.print(F("\tcount:"));
  Serial.println(sheetEvents);
}

bool handleThreshold(long diff) {
  if (DIFF_THRESHOLD == 0) {
    return false;
  }

  long thresholdAbs = labs(DIFF_THRESHOLD);
  long releaseAbs = thresholdAbs;  // display スケッチと同じ挙動

  if (DIFF_THRESHOLD > 0) {
    long diffMagnitude = labs(diff);
    if (!aboveThreshold && diffMagnitude > thresholdAbs) {
      aboveThreshold = true;
    }
    if (aboveThreshold && diffMagnitude < releaseAbs) {
      aboveThreshold = false;
      return true;
    }
  } else {
    long trigger = -thresholdAbs;
    long release = -releaseAbs;
    if (!aboveThreshold && diff < trigger) {
      aboveThreshold = true;
    }
    if (aboveThreshold && diff > release) {
      aboveThreshold = false;
      return true;
    }
  }
  return false;
}

void setupHX711() {
  Serial.println(F("# Initializing HX711..."));
  scale.begin(PIN_HX711_DATA, PIN_HX711_SCK);
  delay(200);

  unsigned long start = millis();
  while (!scale.is_ready() && (millis() - start) < 2000UL) {
    delay(5);
  }

  if (!scale.is_ready()) {
    Serial.println(F("# HX711 not responding. Check wiring."));
    hxReady = false;
    return;
  }

  scale.set_gain(HX_GAIN);
  scale.tare(20);
  hxBaseline = scale.read_average(HX_AVERAGE_SAMPLES);
  hxReady = true;
  Serial.print(F("# HX711 ready. Gain="));
  Serial.print(HX_GAIN);
  Serial.print(F(" baseline="));
  Serial.println(hxBaseline);
}

// ===== Display helpers =====
void drawHeader() {
  tft.fillScreen(COLOR_BG);
  tft.setTextColor(COLOR_ACCENT_TITLE);
  tft.setTextSize(2);
  tft.setCursor(26, 18);
  tft.print(F("Tissue Counter"));
}

void drawPanel(int16_t x, int16_t y, int16_t w, int16_t h) {
  tft.drawRoundRect(x, y, w, h, 12, COLOR_PANEL);
}

void drawCenteredText(const __FlashStringHelper *label, uint16_t color, int16_t cx, int16_t y) {
  tft.setTextColor(color);
  tft.setTextSize(1);
  int16_t x1, y1;
  uint16_t w, h;
  tft.getTextBounds(String(label), 0, 0, &x1, &y1, &w, &h);
  int16_t labelX = cx - (w / 2);
  tft.setCursor(labelX, y);
  tft.print(label);
}

void drawCenteredNumber(long value, uint16_t color, int16_t cx, int16_t y) {
  tft.setTextColor(color);
  tft.setTextSize(3);
  char buf[12];
  ltoa(value, buf, 10);
  int16_t x1, y1;
  uint16_t w, h;
  tft.getTextBounds(buf, 0, 0, &x1, &y1, &w, &h);
  int16_t numX = cx - (w / 2);
  tft.setCursor(numX, y);
  tft.print(buf);
}

void drawLayout() {
  drawHeader();
  const int16_t panelWidth = 200;
  const int16_t centerX = SCREEN_SIZE / 2;
  const int16_t topX = centerX - panelWidth / 2;
  const int16_t topY = 52;
  const int16_t panelHeight = 60;
  const int16_t spacing = 12;

  drawPanel(topX, topY, panelWidth, panelHeight);
  drawPanel(topX, topY + panelHeight + spacing, panelWidth, panelHeight);
  drawPanel(topX, topY + (panelHeight + spacing) * 2, panelWidth, panelHeight);
}

void updateDisplay() {
  const int16_t panelWidth = 200;
  const int16_t centerX = SCREEN_SIZE / 2;
  const int16_t topX = centerX - panelWidth / 2;
  const int16_t topY = 52;
  const int16_t panelHeight = 60;
  const int16_t spacing = 12;

  // Target
  tft.fillRoundRect(topX + 2, topY + 2, panelWidth - 4, panelHeight - 4, 10, COLOR_BG);
  drawCenteredText(F("Target sheets"), COLOR_ACCENT_TARGET, centerX, topY + 10);
  drawCenteredNumber(targetCount, COLOR_ACCENT_TARGET, centerX, topY + 26);

  // Remaining
  int16_t panel2Y = topY + panelHeight + spacing;
  tft.fillRoundRect(topX + 2, panel2Y + 2, panelWidth - 4, panelHeight - 4, 10, COLOR_BG);
  drawCenteredText(F("Remaining"), COLOR_ACCENT_REMAIN, centerX, panel2Y + 10);
  drawCenteredNumber(remainingCount, COLOR_ACCENT_REMAIN, centerX, panel2Y + 26);

  // Events
  int16_t panel3Y = topY + (panelHeight + spacing) * 2;
  tft.fillRoundRect(topX + 2, panel3Y + 2, panelWidth - 4, panelHeight - 4, 10, COLOR_BG);
  drawCenteredText(F("Events counted"), COLOR_ACCENT_EVENTS, centerX, panel3Y + 10);
  drawCenteredNumber(sheetEvents, COLOR_ACCENT_EVENTS, centerX, panel3Y + 26);
}

void resetCounts(uint16_t newTarget) {
  targetCount = newTarget;
  remainingCount = newTarget;
  displayDirty = true;
}

void setupColors() {
  COLOR_BG = tft.color565(0, 0, 0);
  COLOR_PANEL = tft.color565(72, 72, 72);
  COLOR_ACCENT_TITLE = tft.color565(255, 255, 255);
  COLOR_ACCENT_TARGET = tft.color565(0, 200, 255);
  COLOR_ACCENT_REMAIN = tft.color565(255, 230, 0);
  COLOR_ACCENT_EVENTS = tft.color565(255, 140, 0);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    ;  // USB CDC待ち (UNOでは不要だが板によっては安定)
  }
  Serial.println();
  Serial.println(F("# UNO GC9A01 tissue counter..."));

  setupButtons();
  setupBacklight();

  tft.begin();
  tft.setRotation(0);
  setupColors();
  drawLayout();
  updateDisplay();

  setupHX711();
}

void loop() {
  unsigned long now = millis();

  // Buttons
  bool longPressSet = false;
  if (processButton(btnSet, longPressSet)) {
    uint16_t nextTarget = targetCount + TARGET_STEP;
    if (nextTarget > TARGET_MAX) {
      nextTarget = TARGET_MIN;
    }
    resetCounts(nextTarget);
  }
  if (longPressSet) {
    resetCounts(TARGET_MIN);
  }

  bool longPressCount = false;
  if (processButton(btnCount, longPressCount)) {
    if (remainingCount > 0) {
      --remainingCount;
      ++sheetEvents;
      displayDirty = true;
    }
  }
  if (longPressCount) {
    resetCounts(targetCount);
    sheetEvents = 0;
    displayDirty = true;
  }

  // HX711 sampling
  if (!hxReady) {
    setupHX711();
    delay(200);
    return;
  }

  if (hxReady && (now - lastSample) >= HX_SAMPLE_INTERVAL_MS) {
    lastSample = now;
    if (scale.is_ready()) {
      hxRaw = scale.read_average(HX_AVERAGE_SAMPLES);
      hxDiff = hxRaw - hxBaseline;
      pushSample(hxDiff);
      publishSerialPlot();
      Serial.print(F("# HX711 raw: "));
      Serial.print(hxRaw);
      Serial.print(F(" (diff: "));
      Serial.print(hxDiff);
      Serial.println(')');

      if (handleThreshold(hxDiff)) {
        ++sheetEvents;
        if (remainingCount > 0) {
          --remainingCount;
        }
        displayDirty = true;
        Serial.print(F("# COUNT="));
        Serial.print(sheetEvents);
        Serial.print(F(" (diff="));
        Serial.print(hxDiff);
        Serial.println(')');
      }
    } else {
      Serial.println(F("# HX711 not ready..."));
    }
  }

  if (displayDirty) {
    updateDisplay();
    displayDirty = false;
  }
}
