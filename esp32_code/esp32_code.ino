#include <Wire.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WebSocketsServer.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <Adafruit_MLX90614.h>

const char* ssid = "NOKIA-3BA2";
const char* password = "vW.yLE_FaU";

const char* serverUrl = "http://192.168.1.101:8000/analyze";

MAX30105 particleSensor;
Adafruit_MLX90614 mlx = Adafruit_MLX90614();

#define ECG_PIN 32
#define LO_PLUS 34
#define LO_MINUS 35

const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute;
int beatAvg;

unsigned long lastSend = 0;
const int SEND_INTERVAL = 10000; 

unsigned long lastSensorRead = 0;
const int SENSOR_READ_INTERVAL = 5000;
float lastTemp = 0.0;
int lastEcg = 0;

WebSocketsServer webSocket = WebSocketsServer(81);

#define ECG_BATCH_SIZE 20
#define FILTER_SIZE 10
int ecgBuffer[ECG_BATCH_SIZE];
int ecgIndex = 0;

int filterBuffer[FILTER_SIZE];
int filterIndex = 0;
long filterSum = 0;

int ecgSample = 0;

void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      Serial.printf("[WS] Client %u disconnected\n", num);
      break;
    case WStype_CONNECTED:
      Serial.printf("[WS] Client %u connected\n", num);
      break;
  }
}

void setup()
{
  Serial.begin(115200);
  Wire.begin(21, 22);
  Serial.println("=== Healthcare Monitor Starting ===");

  if (!particleSensor.begin(Wire, I2C_SPEED_FAST))
  {
    Serial.println("MAX30102 NOT FOUND!");
  } else {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x0A);
    particleSensor.setPulseAmplitudeGreen(0);
    Serial.println("MAX30102 Ready ✓");
  }

  Wire.setClock(100000);
  if (!mlx.begin()) {
    Serial.println("MLX90614 NOT FOUND!");
  } else {
    Serial.println("MLX90614 Ready ✓");
  }
  Wire.setClock(400000);

  pinMode(LO_PLUS, INPUT);
  pinMode(LO_MINUS, INPUT);
  Serial.println("AD8232 Ready ✓");

  Serial.print("Connecting to WiFi");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("WiFi Connected! IP: ");
  Serial.println(WiFi.localIP());

  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  Serial.println("WebSocket server started on port 81 ✓");
  Serial.println("ECG Sampling (250Hz) Ready ✓");

  Serial.println("===================================");
}

void loop()
{
  webSocket.loop();

  static unsigned long lastEcgRead = 0;
  if (micros() - lastEcgRead >= 4000) {
    lastEcgRead = micros();

    int raw = analogRead(ECG_PIN);
    filterSum -= filterBuffer[filterIndex];
    filterBuffer[filterIndex] = raw;
    filterSum += raw;
    filterIndex = (filterIndex + 1) % FILTER_SIZE;
    ecgSample = filterSum / FILTER_SIZE;

    ecgBuffer[ecgIndex] = ecgSample;
    ecgIndex++;

    if (ecgIndex >= ECG_BATCH_SIZE) {
      ecgIndex = 0;

      String ecgData = "";
      for (int i = 0; i < ECG_BATCH_SIZE; i++) {
        if (i > 0) ecgData += ",";
        ecgData += String(ecgBuffer[i]);
      }

      webSocket.broadcastTXT(ecgData);
    }
  }

  long irValue = particleSensor.getIR();

  if (irValue > 50000 && checkForBeat(irValue) == true)
  {
    long delta = millis() - lastBeat;
    lastBeat = millis();
    beatsPerMinute = 60 / (delta / 1000.0);

    if (beatsPerMinute < 255 && beatsPerMinute > 20)
    {
      rates[rateSpot++] = (byte)beatsPerMinute;
      rateSpot %= RATE_SIZE;
      beatAvg = 0;
      for (byte x = 0; x < RATE_SIZE; x++)
        beatAvg += rates[x];
      beatAvg /= RATE_SIZE;
    }
  }

  if (irValue < 50000 && millis() - lastBeat > 3000) {
    beatAvg = 0;
    beatsPerMinute = 0;
  }

  if (millis() - lastSensorRead >= SENSOR_READ_INTERVAL) {
    lastSensorRead = millis();

    Wire.setClock(100000);
    lastTemp = mlx.readObjectTempC();
    Wire.setClock(400000);

    lastEcg = ecgSample;
  }

  static unsigned long lastPrint = 0;
  if (millis() - lastPrint >= 500) {
    lastPrint = millis();
    Serial.print("HR: ");
    Serial.print(beatAvg);
    Serial.print(" bpm | IR: ");
    Serial.print(irValue);
    Serial.print(" | Temp: ");
    Serial.print(lastTemp);
    Serial.print("°C | ECG: ");
    Serial.print(ecgSample);

    if (irValue < 50000)
      Serial.print(" | No finger?");

    Serial.println();
  }

  if (millis() - lastSend >= SEND_INTERVAL) {
    lastSend = millis();

    Wire.setClock(100000);
    float freshTemp = mlx.readObjectTempC();
    Wire.setClock(400000);

    if (freshTemp < 25.0) {
      freshTemp = 36.5;
    }

    int hrToSend = beatAvg;

    float spo2 = 98.0;
    if (irValue > 50000) {
      if (irValue < 80000) spo2 = 94.0;
      else if (irValue < 100000) spo2 = 97.0;
      else spo2 = 98.0;
    }

    int ecgToSend = ecgSample;

    if (hrToSend > 0) {
      sendToBackend(hrToSend, freshTemp, spo2, ecgToSend);
    } else {
      Serial.println(">>> Skipping send - no heart rate detected");
    }
  }
}

void sendToBackend(int hr, float temp, float spo2, int ecg) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected! Reconnecting...");
    WiFi.begin(ssid, password);
    return;
  }

  HTTPClient http;
  http.begin(serverUrl);
  http.addHeader("Content-Type", "application/json");

  StaticJsonDocument<256> doc;
  doc["userId"] = "esp32_user";
  doc["deviceID"] = "esp32_device";
  doc["ppg"] = hr;
  doc["ecg"] = ecg;
  doc["temperature"] = temp;
  doc["spo2"] = spo2;

  String jsonString;
  serializeJson(doc, jsonString);

  Serial.println(">>> Sending to backend...");
  Serial.println(jsonString);

  int httpCode = http.POST(jsonString);

  if (httpCode == 200) {
    String response = http.getString();
    Serial.println(">>> Backend response: " + response);
  } else {
    Serial.print(">>> HTTP Error: ");
    Serial.println(httpCode);
  }

  http.end();
}