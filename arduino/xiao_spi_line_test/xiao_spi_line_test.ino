#include <Arduino.h>

// XIAO ESP32-C3 pin definitions (match GC9A01 wiring)
static constexpr uint8_t PIN_CS   = D5;
static constexpr uint8_t PIN_DC   = D4;
static constexpr uint8_t PIN_RST  = D2;
static constexpr uint8_t PIN_SCLK = D8;
static constexpr uint8_t PIN_MOSI = D10;

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\n=== XIAO SPI line toggle test ===");
  Serial.println("Monitor CS/DC/RST/SCLK/MOSI with a multimeter or logic probe.");

  pinMode(PIN_CS, OUTPUT);
  pinMode(PIN_DC, OUTPUT);
  pinMode(PIN_RST, OUTPUT);
  pinMode(PIN_SCLK, OUTPUT);
  pinMode(PIN_MOSI, OUTPUT);

  digitalWrite(PIN_CS, HIGH);
  digitalWrite(PIN_DC, HIGH);
  digitalWrite(PIN_RST, HIGH);
  digitalWrite(PIN_SCLK, LOW);
  digitalWrite(PIN_MOSI, LOW);
}

void toggle(uint8_t pin, const char *name) {
  digitalWrite(pin, !digitalRead(pin));
  Serial.print("Toggled ");
  Serial.print(name);
  Serial.print(" -> ");
  Serial.println(digitalRead(pin) ? "HIGH" : "LOW");
}

void loop() {
  toggle(PIN_CS, "CS");
  delay(500);
  toggle(PIN_DC, "DC");
  delay(500);
  toggle(PIN_RST, "RST");
  delay(500);

  Serial.println("Pulsing SCLK and MOSI 16 times...");
  for (uint8_t i = 0; i < 16; ++i) {
    digitalWrite(PIN_SCLK, HIGH);
    digitalWrite(PIN_MOSI, (i & 1) ? HIGH : LOW);
    delay(50);
    digitalWrite(PIN_SCLK, LOW);
    delay(50);
  }

  Serial.println("---");
  delay(1000);
}
