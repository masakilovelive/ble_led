#include <Arduino.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>
#include <HX711.h>

// ==== TFT (128x160 ST7735) wiring ====
static constexpr uint8_t PIN_TFT_CS  = D5;
static constexpr uint8_t PIN_TFT_DC  = D4;
static constexpr uint8_t PIN_TFT_RST = D2;
Adafruit_ST7735 tft(PIN_TFT_CS, PIN_TFT_DC, PIN_TFT_RST);

// ==== Buttons (active LOW) ====
static constexpr uint8_t BTN_UP     = D0;
static constexpr uint8_t BTN_DOWN   = D1;
static constexpr uint8_t BTN_SELECT = D3;

enum class UiState { Display, EditMax };
enum class MenuItem { Setting, Reset };

struct ButtonState {
  int prev = HIGH;
};

ButtonState btnUp, btnDown, btnSel;
UiState uiState   = UiState::Display;
MenuItem menuItem = MenuItem::Setting;

uint16_t maxCount    = 350;
uint16_t remainCount = 300;
uint16_t editValue   = maxCount;
int      editDigit   = 2;   // 2: hundreds, 1: tens, 0: ones
bool     blinkVisible = true;
uint32_t lastBlink    = 0;
bool     valuesDirty  = true;

// ==== HX711 (weight trigger) ====
static constexpr uint8_t  PIN_HX711_DATA         = D6;
static constexpr uint8_t  PIN_HX711_SCK          = D7;
static constexpr uint16_t HX_SAMPLE_INTERVAL_MS  = 200;
static constexpr uint8_t  HX_AVG_SAMPLES         = 10;
static constexpr uint8_t  HX_GAIN                = 128;
static constexpr long     DIFF_THRESHOLD         = 500;  // positive=abs, negative=down only

HX711 scale;
bool hxReady        = false;
long hxBaseline     = 0;
long hxRaw          = 0;
long hxDiff         = 0;
uint32_t lastHxSample = 0;
bool aboveThreshold = false;

void setupHX711();
void updateHX711();
bool handleHxThreshold(long diff);
void printHxStatus(const char *tag = nullptr);
void publishSerialPlot();

bool readPress(ButtonState &info, uint8_t pin) {
  int level = digitalRead(pin);
  bool pressed = (info.prev == HIGH && level == LOW);
  info.prev = level;
  if (pressed) {
    Serial.print("[BTN] ");
    Serial.println((pin == BTN_UP) ? "UP" : (pin == BTN_DOWN ? "DOWN" : "SELECT"));
  }
  return pressed;
}

// ---------- Drawing ----------
void drawBase() {
  tft.fillScreen(ST77XX_BLACK);
  tft.drawRect(0, 0, 100, 160, ST77XX_WHITE);
  tft.drawRect(100, 0, 28, 160, ST77XX_WHITE);
  tft.drawLine(100, 80, 128, 80, ST77XX_WHITE);
  tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
  tft.setTextSize(1);
  tft.setCursor(8, 15);  tft.print("MAX");
  tft.setCursor(8, 90);  tft.print("REMAIN");
}

void drawMenu() {
  auto drawTab = [&](MenuItem item, const __FlashStringHelper *label, uint16_t color) {
    bool active = (uiState == UiState::Display && menuItem == item);
    uint16_t fill  = active ? color : ST77XX_BLACK;
    uint16_t text  = active ? ST77XX_BLACK : ST77XX_WHITE;
    uint16_t y = (item == MenuItem::Setting) ? 1 : 81;
    tft.fillRect(101, y, 26, 78, fill);
    tft.setTextSize(1);
    tft.setTextColor(text, fill);
    tft.setCursor(105, y + 35);
    tft.print(label);
  };
  drawTab(MenuItem::Setting, F("SET"), ST77XX_CYAN);
  drawTab(MenuItem::Reset,   F("RST"), ST77XX_YELLOW);
}

void drawEditMenu() {
  tft.fillRect(101, 1, 26, 78, ST77XX_CYAN);
  tft.fillRect(101, 81, 26, 78, ST77XX_BLACK);
  tft.setTextSize(1);
  tft.setTextColor(ST77XX_BLACK, ST77XX_CYAN);
  tft.setCursor(105, 15); tft.print("UP");
  tft.setCursor(105, 35); tft.print("DOWN");
  tft.setCursor(105, 55); tft.print("SET");
  tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
  tft.setCursor(105, 115); tft.print("RST");
}

void drawValues(bool clearDirty = true) {
  char buf[8];
  uint16_t value = (uiState == UiState::EditMax) ? editValue : maxCount;
  snprintf(buf, sizeof(buf), "%3u", value);
  if (uiState == UiState::EditMax && !blinkVisible) {
    int pos = (editDigit == 2) ? 0 : (editDigit == 1 ? 1 : 2);
    buf[pos] = ' ';
  }
  tft.setTextColor(ST77XX_YELLOW, ST77XX_BLACK);
  tft.setTextSize(2);
  tft.fillRect(10, 40, 80, 30, ST77XX_BLACK);
  tft.setCursor(10, 40);
  tft.print(buf);

  tft.fillRect(10, 110, 80, 30, ST77XX_BLACK);
  snprintf(buf, sizeof(buf), "%3u", remainCount);
  tft.setCursor(10, 110);
  tft.print(buf);

  if (clearDirty) {
    valuesDirty = false;
  }
}

// ---------- State helpers ----------
void enterEditMode() {
  uiState = UiState::EditMax;
  editValue = maxCount;
  editDigit = 2;
  blinkVisible = true;
  lastBlink = millis();
  drawEditMenu();
  drawValues(false);
}

void exitEditMode(bool commit) {
  if (commit) {
    maxCount = editValue;
    remainCount = maxCount;
  }
  valuesDirty = true;
  uiState = UiState::Display;
  blinkVisible = true;
  drawMenu();
}

void adjustDigit(int delta) {
  uint16_t pow10 = (editDigit == 2) ? 100 : (editDigit == 1 ? 10 : 1);
  int digit = (editValue / pow10) % 10;
  digit = (digit + delta + 10) % 10;
  editValue = (editValue / (pow10 * 10)) * (pow10 * 10) + digit * pow10 + (editValue % pow10);
  editValue = constrain(editValue, 1u, 999u);
  drawValues(false);
}

// ---------- Handlers ----------
void handleDisplayMode(bool upPressed, bool downPressed, bool selPressed) {
  if (upPressed) {
    menuItem = MenuItem::Setting;
    drawMenu();
  }
  if (downPressed) {
    menuItem = MenuItem::Reset;
    drawMenu();
  }
  if (selPressed) {
    if (menuItem == MenuItem::Setting) {
      enterEditMode();
    } else {
      remainCount = maxCount;
      menuItem = MenuItem::Setting;
      drawMenu();
      valuesDirty = true;
    }
  }
}

void handleEditMode(bool upPressed, bool downPressed, bool selPressed) {
  if (upPressed)  adjustDigit(+1);
  if (downPressed) adjustDigit(-1);

  if (selPressed) {
    if (editDigit == 0) {
      exitEditMode(true);
    } else {
      editDigit--;
      drawValues(false);
    }
  }

  uint32_t now = millis();
  if (now - lastBlink > 350) {
    lastBlink = now;
    blinkVisible = !blinkVisible;
    drawValues(false);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(BTN_UP, INPUT_PULLUP);
  pinMode(BTN_DOWN, INPUT_PULLUP);
  pinMode(BTN_SELECT, INPUT_PULLUP);
  btnUp.prev = digitalRead(BTN_UP);
  btnDown.prev = digitalRead(BTN_DOWN);
  btnSel.prev = digitalRead(BTN_SELECT);

  tft.initR(INITR_BLACKTAB);
  tft.setRotation(1);

  drawBase();
  drawMenu();
  drawValues();
  setupHX711();
}

void loop() {
  bool upPressed   = readPress(btnUp, BTN_UP);
  bool downPressed = readPress(btnDown, BTN_DOWN);
  bool selPressed  = readPress(btnSel, BTN_SELECT);

  if (uiState == UiState::Display) {
    handleDisplayMode(upPressed, downPressed, selPressed);
  } else {
    handleEditMode(upPressed, downPressed, selPressed);
  }

  updateHX711();
  if (valuesDirty && uiState == UiState::Display) {
    drawValues();
  }

  delay(10);
}

void setupHX711() {
  Serial.println("# Initializing HX711...");
  scale.begin(PIN_HX711_DATA, PIN_HX711_SCK);
  delay(100);

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
  hxBaseline = scale.read_average(HX_AVG_SAMPLES);
  hxReady = true;
  lastHxSample = millis();
  Serial.print("# HX711 ready. baseline=");
  Serial.println(hxBaseline);
}

bool handleHxThreshold(long diff) {
  if (DIFF_THRESHOLD == 0) {
    return false;
  }

  long thresholdAbs = labs(DIFF_THRESHOLD);
  long releaseAbs = max(1L, thresholdAbs / 2);

  if (DIFF_THRESHOLD > 0) {
    long magnitude = labs(diff);
    if (!aboveThreshold && magnitude > thresholdAbs) {
      aboveThreshold = true;
    }
    if (aboveThreshold && magnitude < releaseAbs) {
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

void updateHX711() {
  if (!hxReady) {
    setupHX711();
    return;
  }

  uint32_t now = millis();
  if (now - lastHxSample < HX_SAMPLE_INTERVAL_MS) {
    return;
  }
  lastHxSample = now;

  if (!scale.is_ready()) {
    Serial.println("# HX711 not ready...");
    return;
  }

  hxRaw = scale.read_average(HX_AVG_SAMPLES);
  hxDiff = hxRaw - hxBaseline;
  printHxStatus("# SAMPLE");
  publishSerialPlot();

  if (handleHxThreshold(hxDiff)) {
    if (remainCount > 0) {
      remainCount--;
      valuesDirty = true;
      printHxStatus("# COUNT");
    } else {
      Serial.println("# Sheet count already at zero.");
    }
  }
}

void printHxStatus(const char *tag) {
  if (tag) {
    Serial.print(tag);
    Serial.print(" ");
  }
  Serial.print("[HX711] raw=");
  Serial.print(hxRaw);
  Serial.print(" diff=");
  Serial.print(hxDiff);
  Serial.print(" baseline=");
  Serial.print(hxBaseline);
  Serial.print(" remain=");
  Serial.println(remainCount);
}

void publishSerialPlot() {
  Serial.print("raw:");
  Serial.print(hxRaw);
  Serial.print('\t');
  Serial.print("diff:");
  Serial.print(hxDiff);
  Serial.print('\t');
  Serial.print("baseline:");
  Serial.print(hxBaseline);
  Serial.print('\t');
  Serial.print("remain:");
  Serial.println(remainCount);
}
