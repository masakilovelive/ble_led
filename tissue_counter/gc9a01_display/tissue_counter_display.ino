#include <Arduino.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <HX711.h>

// ===== Display configuration =====
// user/User_Setup.h must define GC9A01 (240x240) with pins:
// MOSI=13, SCLK=14, CS=15, DC=2, RST=16, BL=12 (backlight control pin)
static constexpr uint8_t PIN_BACKLIGHT = 2;
static constexpr uint16_t COLOR_BG = TFT_BLACK;
static constexpr uint16_t COLOR_AXIS = TFT_DARKGREY;
static constexpr uint16_t COLOR_TRACE = TFT_CYAN;
static constexpr uint16_t COLOR_TEXT = TFT_WHITE;

static constexpr int SCREEN_SIZE = 240;
static constexpr int CENTER_X = SCREEN_SIZE / 2;
static constexpr int CENTER_Y = SCREEN_SIZE / 2;

// Graph area inside circular display
static constexpr int GRAPH_WIDTH = 220;
static constexpr int GRAPH_HEIGHT = 180;
static constexpr int GRAPH_LEFT = (SCREEN_SIZE - GRAPH_WIDTH) / 2;
static constexpr int GRAPH_TOP = (SCREEN_SIZE - GRAPH_HEIGHT) / 2;
static constexpr int GRAPH_BOTTOM = GRAPH_TOP + GRAPH_HEIGHT;

TFT_eSPI tft = TFT_eSPI();

// ===== HX711 configuration =====
static constexpr uint8_t PIN_HX711_DATA = 5;  // DT
static constexpr uint8_t PIN_HX711_SCK = 4;   // SCK
static constexpr uint8_t HX_GAIN = 128;       // Channel A gain
static constexpr uint8_t HX_AVERAGE_SAMPLES = 10;
static constexpr uint16_t HX_SAMPLE_INTERVAL_MS = 200;

static constexpr long DIFF_THRESHOLD = 500;  // >0: +/- detection, <0: negative-only detection

HX711 scale;
bool hxReady = false;
long hxBaseline = 0;
long hxRaw = 0;
long hxDiff = 0;
unsigned long lastSample = 0;

// Sample buffer (scrolling line graph)
static constexpr int BUFFER_SIZE = GRAPH_WIDTH;
long diffBuffer[BUFFER_SIZE];
int sampleCount = 0;
uint32_t sheetCount = 0;
bool aboveThreshold = false;
long graphMin = 0;
long graphMax = 0;
bool graphStatsValid = false;

void setupBacklight() {
  pinMode(PIN_BACKLIGHT, OUTPUT);
  analogWriteRange(1023);   // ESP8266 specific
  analogWriteFreq(5000);
  analogWrite(PIN_BACKLIGHT, 900);  // adjust brightness as needed
}

void drawBackground() {
  tft.fillScreen(COLOR_BG);
  // emphasize circular bezel
  tft.drawCircle(CENTER_X, CENTER_Y, SCREEN_SIZE / 2 - 1, COLOR_AXIS);
  tft.drawCircle(CENTER_X, CENTER_Y, SCREEN_SIZE / 2 - 2, COLOR_AXIS);
  // graph boundary (rectangle inside the circle)
  tft.drawRect(GRAPH_LEFT, GRAPH_TOP, GRAPH_WIDTH, GRAPH_HEIGHT, COLOR_AXIS);
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

long mapDiffToY(long value, long minVal, long maxVal) {
  if (maxVal == minVal) return GRAPH_TOP + GRAPH_HEIGHT / 2;
  value = constrain(value, minVal, maxVal);
  float norm = (float)(value - minVal) / (float)(maxVal - minVal);
  return GRAPH_TOP + GRAPH_HEIGHT - 1 - (int)(norm * (GRAPH_HEIGHT - 1));
}

bool computeGraphRange(long &minVal, long &maxVal) {
  if (sampleCount == 0) {
    graphStatsValid = false;
    return false;
  }

  minVal = diffBuffer[0];
  maxVal = diffBuffer[0];
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
  return true;
}

void drawGraph() {
  long minVal = 0;
  long maxVal = 0;
  if (!computeGraphRange(minVal, maxVal)) {
    return;
  }

  // Clear graph area
  tft.fillRect(GRAPH_LEFT + 1, GRAPH_TOP + 1, GRAPH_WIDTH - 2, GRAPH_HEIGHT - 2, COLOR_BG);
  tft.drawRect(GRAPH_LEFT, GRAPH_TOP, GRAPH_WIDTH, GRAPH_HEIGHT, COLOR_AXIS);

  // Zero line
  int zeroY = mapDiffToY(0, minVal, maxVal);
  if (zeroY >= GRAPH_TOP && zeroY < GRAPH_TOP + GRAPH_HEIGHT) {
    tft.drawFastHLine(GRAPH_LEFT, zeroY, GRAPH_WIDTH, COLOR_AXIS);
  }

  // Plot trace
  if (sampleCount >= 2) {
    int prevY = mapDiffToY(diffBuffer[0], minVal, maxVal);
    for (int i = 1; i < sampleCount; ++i) {
      int x = GRAPH_LEFT + i;
      int currY = mapDiffToY(diffBuffer[i], minVal, maxVal);
      tft.drawLine(x - 1, prevY, x, currY, COLOR_TRACE);
      prevY = currY;
    }
  } else {
    int singleY = mapDiffToY(diffBuffer[0], minVal, maxVal);
    int x = GRAPH_LEFT + sampleCount - 1;
    tft.drawPixel(x, singleY, COLOR_TRACE);
  }

  // Display latest values
  tft.setTextDatum(TC_DATUM);
  tft.setTextFont(2);
  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.fillRect(GRAPH_LEFT, GRAPH_TOP - 26, GRAPH_WIDTH, 24, COLOR_BG);
  tft.drawString("raw: " + String(hxRaw), CENTER_X, GRAPH_TOP - 20);
  tft.fillRect(GRAPH_LEFT, GRAPH_BOTTOM + 2, GRAPH_WIDTH, 32, COLOR_BG);
  tft.drawString("diff: " + String(hxDiff), CENTER_X, GRAPH_BOTTOM + 10);
  tft.setTextDatum(TL_DATUM);
  tft.drawString("min: " + String(minVal), GRAPH_LEFT, GRAPH_BOTTOM + 18);
  tft.setTextDatum(TR_DATUM);
  tft.drawString("max: " + String(maxVal), GRAPH_LEFT + GRAPH_WIDTH, GRAPH_BOTTOM + 18);
  tft.setTextDatum(TC_DATUM);

  // Display sheet count near bottom center
  tft.fillRect(GRAPH_LEFT, SCREEN_SIZE - 20, GRAPH_WIDTH, 18, COLOR_BG);
  tft.drawString("count: " + String(sheetCount), CENTER_X, SCREEN_SIZE - 12);
}

void pushSample(long diff) {
  if (sampleCount < BUFFER_SIZE) {
    diffBuffer[sampleCount++] = diff;
  } else {
    memmove(diffBuffer, diffBuffer + 1, (BUFFER_SIZE - 1) * sizeof(long));
    diffBuffer[BUFFER_SIZE - 1] = diff;
  }
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
  Serial.println(sheetCount);
}

bool handleThreshold(long diff) {
  if (DIFF_THRESHOLD == 0) {
    return false;
  }

  long thresholdAbs = labs(DIFF_THRESHOLD);
  long releaseAbs = max(1L, thresholdAbs / 2);

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
    long trigger = -thresholdAbs;   // e.g. -500
    long release = -releaseAbs;     // e.g. -250
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

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println();
  Serial.println("# HX711 graph demo (diff only)...");

  setupBacklight();
  tft.init();
  tft.setRotation(0);
  drawBackground();

  setupHX711();
}

void loop() {
  unsigned long now = millis();
  if (!hxReady) {
    setupHX711();
    delay(200);
    return;
  }

  if (hxReady && now - lastSample >= HX_SAMPLE_INTERVAL_MS) {
    lastSample = now;
    if (scale.is_ready()) {
      hxRaw = scale.read_average(HX_AVERAGE_SAMPLES);
      hxDiff = hxRaw - hxBaseline;
      pushSample(hxDiff);
      drawGraph();
      publishSerialPlot();

      // serial monitor message (ignored by Serial Plotter)
      Serial.printf("# HX711 raw: %ld (diff: %ld)\n", hxRaw, hxDiff);

      // threshold detection for count
      if (handleThreshold(hxDiff)) {
        sheetCount++;
        Serial.printf("# COUNT=%lu (diff=%ld)\n", sheetCount, hxDiff);
      }
    } else {
      Serial.println("# HX711 not ready...");
    }
  }
}
