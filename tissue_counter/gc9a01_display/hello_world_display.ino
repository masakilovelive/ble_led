#include <Arduino.h>
#include <TFT_eSPI.h>

// Wiring must match user/User_Setup.h (GC9A01, 240x240)
// LEDK -> GPIO12, D/C -> GPIO2, CS -> GPIO15, SCL -> GPIO14,
// SDA -> GPIO13, RESET -> GPIO16
static constexpr uint8_t PIN_BACKLIGHT = 12;

TFT_eSPI tft;

void setupBacklight() {
  pinMode(PIN_BACKLIGHT, OUTPUT);
  analogWriteRange(1023);
  analogWriteFreq(5000);
  analogWrite(PIN_BACKLIGHT, 1023);  // full brightness
}

void drawHelloWorld() {
  tft.fillScreen(TFT_BLACK);

  // Simple color test to confirm refresh works
  tft.fillRect(0, 0, tft.width(), tft.height() / 3, TFT_RED);
  tft.fillRect(0, tft.height() / 3, tft.width(), tft.height() / 3, TFT_GREEN);
  tft.fillRect(0, 2 * tft.height() / 3, tft.width(), tft.height() / 3, TFT_BLUE);
  delay(500);

  tft.fillScreen(TFT_BLACK);
  tft.setTextDatum(MC_DATUM);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextFont(4);
  tft.drawString("Hello World", tft.width() / 2, tft.height() / 2);
}

void setup() {
  Serial.begin(115200);
  Serial.println();
  Serial.println("GC9A01 hello world demo");

  setupBacklight();

  tft.init();
  tft.setRotation(0);
  drawHelloWorld();
}

void loop() {
  // nothing to do – static screen
}
