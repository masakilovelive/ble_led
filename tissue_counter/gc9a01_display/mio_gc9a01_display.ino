#include <FS.h>
#include <LittleFS.h>
#include <SPI.h>
#include <TFT_eSPI.h>

// Adjust these pins/setup macros to match your TFT_eSPI User_Setup.h
// Example for ESP-12S (ESP8266):
// #define TFT_MISO -1
// #define TFT_MOSI 13
// #define TFT_SCLK 14
// #define TFT_CS   15
// #define TFT_DC   2
// #define TFT_RST  5
// #define GC9A01_DRIVER
static constexpr uint8_t PIN_BL = 4;  // backlight PWM pin

static constexpr char kImagePath[] = "/mio_rgb565.bin";
static constexpr uint16_t kImageWidth = 240;
static constexpr uint16_t kImageHeight = 240;

TFT_eSPI tft = TFT_eSPI();

bool drawImageFromFS(const char *path) {
  File img = LittleFS.open(path, "r");
  if (!img) {
    Serial.println("Failed to open image file");
    return false;
  }

  tft.startWrite();
  const int16_t x = (tft.width() - kImageWidth) / 2;
  const int16_t y = (tft.height() - kImageHeight) / 2;
  tft.setAddrWindow(x, y, kImageWidth, kImageHeight);

  uint8_t buffer[512];
  while (img.available()) {
    size_t readBytes = img.read(buffer, sizeof(buffer));
    tft.pushColors(reinterpret_cast<uint16_t *>(buffer), readBytes / 2, false);
  }
  tft.endWrite();
  img.close();
  return true;
}

void setup() {
  pinMode(PIN_BL, OUTPUT);
  analogWriteRange(1023);
  analogWriteFreq(5000);
  analogWrite(PIN_BL, 1023);  // max brightness

  Serial.begin(115200);
  Serial.println();
  Serial.println("GC9A01 image viewer");

  if (!LittleFS.begin()) {
    Serial.println("LittleFS mount failed");
    while (true) {
      delay(1000);
    }
  }

  tft.init();
  tft.setRotation(0);  // 0 or 1 fits round displays
  tft.fillScreen(TFT_BLACK);
  tft.setSwapBytes(true);  // RGB565 binary is big-endian

  if (!drawImageFromFS(kImagePath)) {
    tft.setTextColor(TFT_RED, TFT_BLACK);
    tft.setTextDatum(MC_DATUM);
    tft.drawString("Missing mio_rgb565.bin", tft.width() / 2, tft.height() / 2);
  }
}

void loop() {
  // Nothing to update – static image.
}
