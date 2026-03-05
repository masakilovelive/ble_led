#include <Arduino.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <HX711.h>

// ===== Display configuration =====
// user/User_Setup.h must define GC9A01 (240x240) with correct pins.
static constexpr uint8_t PIN_BACKLIGHT = 2;
static constexpr uint16_t COLOR_BG = TFT_BLACK;
static constexpr uint16_t COLOR_PANEL = TFT_DARKGREY;
static constexpr uint16_t COLOR_PRIMARY = TFT_CYAN;
static constexpr uint16_t COLOR_SECONDARY = TFT_YELLOW;
static constexpr uint16_t COLOR_ACCENT = TFT_ORANGE;

static constexpr int SCREEN_SIZE = 240;
static constexpr int PANEL_MARGIN = 20;
static constexpr int PANEL_RADIUS = 10;
static constexpr int PANEL_HEIGHT_PRIMARY = 56;
static constexpr int PANEL_SPACING = 10;

TFT_eSPI tft = TFT_eSPI();

// ===== Button configuration =====
// NOTE: BTN_COUNT uses GPIO0. Keep the button HIGH during reset/programming.
static constexpr uint8_t PIN_BTN_SET = 12;   // increments target sheets
static constexpr uint8_t PIN_BTN_COUNT = 0;  // manual decrement / reset
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
static constexpr uint8_t PIN_HX711_DATA = 5;  // DT
static constexpr uint8_t PIN_HX711_SCK = 4;   // SCK
static constexpr uint8_t HX_GAIN = 128;
static constexpr uint8_t HX_AVERAGE_SAMPLES = 10;
static constexpr uint16_t HX_SAMPLE_INTERVAL_MS = 200;

static constexpr long DIFF_THRESHOLD = 500;  // >0: +/- detection, <0: negative-only detection

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
static constexpr int BUFFER_SIZE = 120;
long diffBuffer[BUFFER_SIZE];
int sampleCount = 0;
long graphMin = 0;
long graphMax = 0;
bool graphStatsValid = false;

void setupBacklight() {
  pinMode(PIN_BACKLIGHT, OUTPUT);
  analogWriteRange(1023);
  analogWriteFreq(5000);
  analogWrite(PIN_BACKLIGHT, 900);
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
      return true;
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
  for (int i = 1; i < sampleCount; ++i) {
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
  Serial.print("raw:");
  Serial.print(hxRaw);
  Serial.print("\tdiff:");
  Serial.print(hxDiff);
  Serial.print("\tmin:");
  Serial.print(graphMin);
  Serial.print("\tmax:");
  Serial.print(graphMax);
  Serial.print("\tcount:");
  Serial.println(sheetEvents);
}

bool handleThreshold(long diff) {
  if (DIFF_THRESHOLD == 0) {
    return false;
  }

  long thresholdAbs = labs(DIFF_THRESHOLD);
  long releaseAbs = thresholdAbs;

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
  Serial.println("# Initializing HX711...");
  scale.begin(PIN_HX711_DATA, PIN_HX711_SCK);
  delay(200);

  unsigned long start = millis();
  while (!scale.is_ready() && millis() - start < 2000) {
    delay(5);
  }

  if (!scale.is_ready()) {
    Serial.println("# HX711 not responding. Check wiring.");
    hxReady = false;
    return;
  }

  scale.set_gain(HX_GAIN);
  scale.tare(20);
  hxBaseline = scale.read_average(HX_AVERAGE_SAMPLES);
  hxReady = true;
  Serial.print("# HX711 ready. Gain=");
  Serial.print(HX_GAIN);
  Serial.print(" baseline=");
  Serial.println(hxBaseline);
}

void drawLayout() {
  tft.fillScreen(COLOR_BG);
  tft.setTextDatum(TC_DATUM);
  tft.setTextColor(TFT_WHITE, COLOR_BG);
  tft.setTextFont(3);
  tft.drawString("Tissue Counter", SCREEN_SIZE / 2, 28);

  int panelWidth = SCREEN_SIZE - PANEL_MARGIN * 2;
  int topY = 52;
  int secondY = topY + PANEL_HEIGHT_PRIMARY + PANEL_SPACING;
  int thirdY = secondY + PANEL_HEIGHT_PRIMARY + PANEL_SPACING;

  tft.drawRoundRect(PANEL_MARGIN, topY, panelWidth, PANEL_HEIGHT_PRIMARY, PANEL_RADIUS, COLOR_PANEL);
  tft.drawRoundRect(PANEL_MARGIN, secondY, panelWidth, PANEL_HEIGHT_PRIMARY, PANEL_RADIUS, COLOR_PANEL);
  tft.drawRoundRect(PANEL_MARGIN, thirdY, panelWidth, PANEL_HEIGHT_PRIMARY, PANEL_RADIUS, COLOR_PANEL);
}

void updateDisplay() {
  const int panelWidth = SCREEN_SIZE - PANEL_MARGIN * 2;
  const int centerX = SCREEN_SIZE / 2;
  const int topY = 52;
  const int secondY = topY + PANEL_HEIGHT_PRIMARY + PANEL_SPACING;
  const int thirdY = secondY + PANEL_HEIGHT_PRIMARY + PANEL_SPACING;

  // Target panel
  tft.fillRoundRect(PANEL_MARGIN + 2, topY + 2, panelWidth - 4, PANEL_HEIGHT_PRIMARY - 4, PANEL_RADIUS - 2, COLOR_BG);
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(2);
  tft.setTextColor(COLOR_PRIMARY, COLOR_BG);
  tft.drawString("Target sheets", centerX, topY + 18);
  tft.setTextFont(4);
  tft.drawString(String(targetCount), centerX, topY + PANEL_HEIGHT_PRIMARY - 14);

  // Remaining panel
  tft.fillRoundRect(PANEL_MARGIN + 2, secondY + 2, panelWidth - 4, PANEL_HEIGHT_PRIMARY - 4, PANEL_RADIUS - 2, COLOR_BG);
  tft.setTextColor(COLOR_SECONDARY, COLOR_BG);
  tft.setTextFont(2);
  tft.drawString("Remaining", centerX, secondY + 18);
  tft.setTextFont(4);
  tft.drawString(String(remainingCount), centerX, secondY + PANEL_HEIGHT_PRIMARY - 14);

  // Events panel
  tft.fillRoundRect(PANEL_MARGIN + 2, thirdY + 2, panelWidth - 4, PANEL_HEIGHT_PRIMARY - 4, PANEL_RADIUS - 2, COLOR_BG);
  tft.setTextColor(COLOR_ACCENT, COLOR_BG);
  tft.setTextFont(2);
  tft.drawString("Events counted", centerX, thirdY + 18);
  tft.setTextFont(4);
  tft.drawString(String(sheetEvents), centerX, thirdY + PANEL_HEIGHT_PRIMARY - 14);
}

void resetCounts(uint16_t newTarget) {
  targetCount = newTarget;
  remainingCount = newTarget;
  displayDirty = true;
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println();
  Serial.println("# Tissue counter (dashboard)...");

  setupBacklight();
  setupButtons();
  tft.init();
  tft.setRotation(0);
  drawLayout();
  updateDisplay();

  setupHX711();
}

void loop() {
  unsigned long now = millis();

  // Handle buttons
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
      Serial.printf("# HX711 raw: %ld (diff: %ld)\n", hxRaw, hxDiff);

      if (handleThreshold(hxDiff)) {
        ++sheetEvents;
        if (remainingCount > 0) {
          --remainingCount;
        }
        displayDirty = true;
        Serial.printf("# COUNT=%lu (diff=%ld)\n", sheetEvents, hxDiff);
      }
    } else {
      Serial.println("# HX711 not ready...");
    }
  }

  if (displayDirty) {
    updateDisplay();
    displayDirty = false;
  }
}
