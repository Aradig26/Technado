/*
 * ESP32 Sensory Overload Monitoring System
 *
 * This sketch uses an ESP32 with EmotiBit and Adafruit AS7341 sensor
 * to monitor environmental conditions and send data to an iOS app.
 *
 * Components used:
 * - EmotiBit (for PPG)
 * - Adafruit AS7341 10-Channel Light/Color Sensor
 * - Sound sensor (e.g., MAX9814 microphone amplifier)
 *
 * Dependencies:
 * - EmotiBit Library: https://github.com/EmotiBit/EmotiBit_FeatherWing
 * - Adafruit AS7341 Library: https://github.com/adafruit/Adafruit_AS7341
 * - ArduinoBLE: https://www.arduino.cc/reference/en/libraries/arduinoble/
 */

#include <Wire.h>
#include <Adafruit_AS7341.h>
#include <ArduinoBLE.h>
#include "EmotiBit.h"
#include <algorithm>
#include <cmath>

// BLE UUIDs
#define SERVICE_UUID "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define SOUND_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
#define LIGHT_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A9"
#define HEARTRATE_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26AA"

// sensor objects
EmotiBit emotibit;
Adafruit_AS7341 as7341;

// BLE service + characteristics
BLEService sensorService(SERVICE_UUID);
BLEFloatCharacteristic soundChar(SOUND_UUID, BLERead | BLENotify);
BLEFloatCharacteristic lightChar(LIGHT_UUID, BLERead | BLENotify);
BLEUnsignedCharCharacteristic hrChar(HEARTRATE_UUID, BLERead | BLENotify);

// update intervals
const unsigned long PRINT_UPDATE_MS = 800;
const unsigned long BLE_UPDATE_MS = 300;
unsigned long lastPrint = 0;
unsigned long lastBle = 0;

bool wasConnected = false;

// SOUND constants
const int SOUND_PIN = 15;
const int SOUND_SAMPLES = 512;
const float VREF = 3.3f;
const float ADC_MAX = 4095.0f;
const float P_REF = 0.00002f;
const float SENSITIVITY = 2.49f;

// LIGHT constants
const int BUF_SZ = 8;
float luxBuf[BUF_SZ];
int bufIdx = 0;
bool bufFull = false;
const float V_WEIGHTS[8] = {
  0.0012, 0.0230, 0.1390, 0.5030,
  0.9950, 0.7570, 0.2650, 0.0170
};
float calM = 1.2134;
float calB = 13.5487;


// Kalman filter vars (tune Q and R to change smoothness)
float kfQ = 0.02;  // process noise covariance
float kfR = 0.5;   // measurement noise covariance
float kfP = 1.0;   // estimation error covariance, start at 1
float kfK = 1.5;   // Kalman gain
float kfX = 0.0;   // filtered value (init to zero or first reading)


// HR constants
const float HR_RATE = 25.0f;
const size_t HR_LEN = HR_RATE * 6;  // 6 s window
const float HR_RATIO = 0.6f;
const size_t HR_SKIP = HR_RATE * 0.3f;  // 0.3 s skip

float greenBuf[HR_LEN], redBuf[HR_LEN], irBuf[HR_LEN];
size_t hrIndex = 0;

// latest values
float latestSoundDb = 0;
float latestLux = 0;
float latestBpm = 0;

// --- sensor update methods ---
void updateSound() {
  float mean = 0, M2 = 0;
  for (int i = 1; i <= SOUND_SAMPLES; i++) {
    float x = analogRead(SOUND_PIN);
    float d = x - mean;
    mean += d / i;
    M2 += d * (x - mean);
  }
  float rms = sqrt(M2 / SOUND_SAMPLES);
  float volt = rms * (VREF / ADC_MAX);
  float pa = volt / SENSITIVITY;
  latestSoundDb = pa > 0
                    ? 20.8f * log10(pa / P_REF)
                    : 0.0f;
}

float kalmanFilter(float meas) {
  kfP += kfQ;                 // prediction update
  kfK = kfP / (kfP + kfR);    // compute gain
  kfX += kfK * (meas - kfX);  // update estimate
  kfP *= (1.0 - kfK);         // update error covariance
  return kfX;
}

void updateLight() {
  uint16_t data[12];
  if (!as7341.readAllChannels(data)) return;
  float sum = 0;
  for (int i = 0; i < 8; i++)
    sum += data[i] * V_WEIGHTS[i];
  float rawLux = sum;

  // keep your existing circular buffer smoothing
  luxBuf[bufIdx] = rawLux;
  bufIdx = (bufIdx + 1) % BUF_SZ;
  if (bufIdx == 0) bufFull = true;

  int cnt = bufFull ? BUF_SZ : bufIdx;
  float acc = 0;
  for (int i = 0; i < cnt; i++)
    acc += luxBuf[i];
  float avgLux = acc / cnt;

  // now apply Kalman filter to the averaged value
  latestLux = kalmanFilter(calM * avgLux + calB);
}


void updateHrBuffer() {
  emotibit.update();
  float g = 0, r = 0, ir = 0;
  if (emotibit.readData(EmotiBit::DataType::PPG_GREEN, &g, 1)
      && emotibit.readData(EmotiBit::DataType::PPG_RED, &r, 1)
      && emotibit.readData(EmotiBit::DataType::PPG_INFRARED, &ir, 1)) {
    greenBuf[hrIndex] = g;
    redBuf[hrIndex] = r;
    irBuf[hrIndex] = ir;
    hrIndex = (hrIndex + 1) % HR_LEN;
  }
}

// --- helper for HR peak count ---
size_t countPeaks(float* buf) {
  float mx = *std::max_element(buf, buf + HR_LEN);
  size_t peaks = 0;
  for (size_t i = 1; i + 1 < HR_LEN; i++) {
    if (buf[i] > buf[i - 1] && buf[i] > buf[i + 1] && buf[i] > HR_RATIO * mx) {
      peaks++;
      i += HR_SKIP;
    }
  }
  return peaks;
}

void computeBpm() {
  size_t pg = countPeaks(greenBuf);
  size_t pr = countPeaks(redBuf);
  size_t pi = countPeaks(irBuf);
  float secs = HR_LEN / HR_RATE;
  float bg = pg > 0 ? (pg / secs) * 60.0f : 0;
  float br = pr > 0 ? (pr / secs) * 60.0f : 0;
  float bi = pi > 0 ? (pi / secs) * 60.0f : 0;
  latestBpm = (bg + br + bi) / 3.0f;
}

// --- print methods ---
void printOutputs() {
  Serial.print("Sound dB: ");
  Serial.println(latestSoundDb);
  Serial.print("Light lux: ");
  Serial.println(latestLux);
  Serial.print("HR BPM: ");
  Serial.println(latestBpm);
}

// --- BLE update methods ---
void bluetoothUpdate() {
  soundChar.writeValue(latestSoundDb);
  lightChar.writeValue(latestLux);
  hrChar.writeValue((uint8_t)latestBpm);
}

void setup() {
  Serial.begin(2000000);
  while (!Serial && millis() < 5000) delay(10);
  Serial.println("Starting Sensory Overload Monitoring System");

  // init sensors
  if (!as7341.begin()) {
    Serial.println("AS7341 not found");
    while (1) delay(500);
  }
  pinMode(SOUND_PIN, INPUT);
  analogSetPinAttenuation(SOUND_PIN, ADC_11db);
  analogSetWidth(12);
  emotibit.setup();

  // init BLE
  if (!BLE.begin()) {
    Serial.println("BLE init failed");
    while (1) delay(10);
  }
  BLE.setLocalName("SensoryMonitor");
  BLE.setAdvertisedService(sensorService);
  sensorService.addCharacteristic(soundChar);
  sensorService.addCharacteristic(lightChar);
  sensorService.addCharacteristic(hrChar);
  BLE.addService(sensorService);
  soundChar.writeValue(0.0f);
  lightChar.writeValue(0.0f);
  hrChar.writeValue((uint8_t)0);
  BLE.advertise();

  Serial.println("Setup complete. Waiting for BLE connections...");
}

void loop() {
  // always refresh the readings
  updateSound();
  updateLight();
  updateHrBuffer();

  unsigned long now = millis();

  // timed prints
  if (now - lastPrint >= PRINT_UPDATE_MS) {
    computeBpm();
    printOutputs();
    lastPrint = now;
  }
  if (now - lastBle >= BLE_UPDATE_MS) {
    computeBpm();
    bluetoothUpdate();
    lastBle = now;
  }

  // connection logging
  BLEDevice central = BLE.central();
  if (central && !wasConnected) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());
    wasConnected = true;
  }
  if (!central && wasConnected) {
    Serial.println("Central disconnected");
    wasConnected = false;
    BLE.advertise();
  }
}
