#include <Arduino.h>
#include <SPI.h>

// ----- Inline TFT_eSPI setup for XIAO MG24 Sense + GC9A01 -----
// XIAO MG24 Sense shares the XIAO pin layout:
//   D10 = MOSI, D9 = MISO, D8 = SCK, D5 = D/C, D4 = CS, D2 = RST
#define USER_SETUP_LOADED
#define GC9A01_DRIVER
#define TFT_WIDTH  240
#define TFT_HEIGHT 240
#define USE_HSPI_PORT          // VSPI on ESP32-class cores; works with MG24 Arduino core
#define TFT_MOSI 10
#define TFT_MISO 9             // GC9A01 SDO 未使用なら未配線で可
#define TFT_SCLK 8
#define TFT_CS   4
#define TFT_DC   5
#define TFT_RST  2
#define SPI_FREQUENCY 27000000
#define SPI_READ_FREQUENCY 20000000

#include <TFT_eSPI.h>
TFT_eSPI tft;

static constexpr uint32_t SCREEN_BG = TFT_BLACK;

void drawLayout() {
  tft.fillScreen(SCREEN_BG);
  tft.setTextDatum(TC_DATUM);
  tft.setTextColor(TFT_WHITE, SCREEN_BG);
  tft.setTextFont(4);
  tft.drawString("XIAO MG24", TFT_WIDTH / 2, 24);
  tft.setTextFont(2);
  tft.drawString("GC9A01 test panel", TFT_WIDTH / 2, 48);

  tft.drawCircle(TFT_WIDTH / 2, TFT_HEIGHT / 2, TFT_WIDTH / 2 - 4, TFT_DARKGREY);

  uint16_t colors[] = {TFT_RED, TFT_ORANGE, TFT_YELLOW, TFT_GREEN, TFT_CYAN, TFT_BLUE, TFT_MAGENTA};
  for (uint8_t i = 0; i < 7; ++i) {
    int16_t inner = 84;
    int16_t outer = 104;
    float start = radians(i * 45.0f);
    float end = radians((i + 1) * 45.0f);
    int16_t x0 = TFT_WIDTH / 2 + inner * cos(start);
    int16_t y0 = TFT_HEIGHT / 2 + inner * sin(start);
    int16_t x1 = TFT_WIDTH / 2 + outer * cos(start);
    int16_t y1 = TFT_HEIGHT / 2 + outer * sin(start);
    int16_t x2 = TFT_WIDTH / 2 + outer * cos(end);
    int16_t y2 = TFT_HEIGHT / 2 + outer * sin(end);
    int16_t x3 = TFT_WIDTH / 2 + inner * cos(end);
    int16_t y3 = TFT_HEIGHT / 2 + inner * sin(end);
    tft.fillTriangle(x0, y0, x1, y1, x2, y2, colors[i]);
    tft.fillTriangle(x0, y0, x2, y2, x3, y3, colors[i]);
  }

  tft.setTextDatum(MC_DATUM);
  tft.setTextColor(TFT_WHITE, SCREEN_BG);
  tft.setTextFont(4);
  tft.drawString("HELLO", TFT_WIDTH / 2, TFT_HEIGHT / 2 - 10);
  tft.setTextFont(2);
  tft.drawString("Touch-free demo", TFT_WIDTH / 2, TFT_HEIGHT / 2 + 24);
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\nXIAO MG24 GC9A01 demo starting...");

  tft.init();
  tft.setRotation(0);
  drawLayout();
}

void loop() {
  // オレンジと青を交互に光らせる簡単なアニメーション
  static uint32_t lastToggle = 0;
  static bool toggle = false;
  uint32_t now = millis();
  if (now - lastToggle > 500) {
    lastToggle = now;
    toggle = !toggle;
    uint16_t color = toggle ? TFT_SKYBLUE : TFT_ORANGE;
    tft.fillCircle(TFT_WIDTH / 2, TFT_HEIGHT - 30, 18, color);
    tft.setTextDatum(MC_DATUM);
    tft.setTextColor(TFT_BLACK, color);
    tft.setTextFont(2);
    tft.drawString(toggle ? "OK" : "MG24", TFT_WIDTH / 2, TFT_HEIGHT - 30);
  }
}
