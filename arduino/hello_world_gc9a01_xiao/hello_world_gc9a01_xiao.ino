#include <Arduino.h>
#include <SPI.h>

// ----- Inline TFT_eSPI user setup for GC9A01 + XIAO ESP32-C3 -----
#define USER_SETUP_LOADED
#define GC9A01_DRIVER
#define TFT_WIDTH 240
#define TFT_HEIGHT 240
#define TFT_SPI_PORT 1         // use FSPI
#define TFT_MOSI 10            // XIAO header MOSI
#define TFT_MISO 9             // physical MISO (can stay unconnected)
#define TFT_SCLK 8             // header SCK
#define TFT_CS   5             // user-selected CS pin
#define TFT_DC   4             // D4
#define TFT_RST  2             // D2
#define SPI_FREQUENCY 27000000
#define SPI_READ_FREQUENCY 20000000

#include <TFT_eSPI.h>
TFT_eSPI tft = TFT_eSPI();

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\nGC9A01 hello-world test starting...");

  tft.init();
  tft.setRotation(0);   // 0=portrait, try 1/2/3 if向きを変えたい
}

void loop() {
  static uint32_t lastChange = 0;
  static uint8_t colorIndex = 0;
  uint32_t now = millis();
  if (now - lastChange >= 500) {
    lastChange = now;
    uint16_t colors[] = {TFT_RED, TFT_GREEN, TFT_BLUE, TFT_YELLOW,
                         TFT_MAGENTA, TFT_CYAN, TFT_WHITE, TFT_BLACK};
    tft.fillScreen(colors[colorIndex]);
    colorIndex = (colorIndex + 1) % (sizeof(colors) / sizeof(colors[0]));
  }
}
