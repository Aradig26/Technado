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
#include <algorithm>  // For std::max_element


// BLE Service and Characteristic UUIDs (must match iOS app)
#define SERVICE_UUID "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define SOUND_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
#define LIGHT_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A9"
#define HEARTRATE_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26AA"

float heartRate = 0.0f;
portMUX_TYPE HRbpmMutex_async = portMUX_INITIALIZER_UNLOCKED;
volatile float latestHRLevelBpm_async = 0.0f;
EmotiBit emotibit;

// BLE setup
BLEService sensorService(SERVICE_UUID);
BLEFloatCharacteristic soundLevelChar(SOUND_UUID, BLERead | BLENotify);
BLEFloatCharacteristic lightLevelChar(LIGHT_UUID, BLERead | BLENotify);
BLEUnsignedCharCharacteristic heartRateChar(HEARTRATE_UUID, BLERead | BLENotify);

// Variables for sensor readings
float soundLevel = 0.0f;
const int soundSensorPin = 15;  // Analog pin for sound sensor

volatile float latestSoundLevelDb_async = 0;
portMUX_TYPE soundLevelMutex_async = portMUX_INITIALIZER_UNLOCKED;
TaskHandle_t SoundSamplingTaskHandle_async = NULL;

Adafruit_AS7341 as7341;
float lightLevel = 0.0f;

// Timing variables
unsigned long lastReadingTime = 0;
const unsigned long readingInterval = 1000;  // 1 s

void setup() {
  Serial.begin(2000000);
  while (!Serial && millis() < 5000)
    ;

  Serial.println("Starting Sensory Overload Monitoring System");

  // Initialize AS7341 light sensor
  if (!as7341.begin()) {
    Serial.println("Could not find AS7341 light sensor");
    while (1)
      delay(500);
  }

  // Initialize sound sensor
  pinMode(soundSensorPin, INPUT);
  analogSetPinAttenuation(soundSensorPin, ADC_11db);  // 0–3.3 V range
  analogSetWidth(12);

  const BaseType_t coreToRunSoundTaskOn = 0;
  const UBaseType_t soundTaskPriority = 1;
  BaseType_t xReturned = xTaskCreatePinnedToCore(
    soundSamplingTask_async,
    "SoundSamplingTask",
    2048,
    NULL,
    soundTaskPriority,
    &SoundSamplingTaskHandle_async,
    coreToRunSoundTaskOn);

  if (xReturned != pdPASS) {
    Serial.println("Sound Task Creation Failed!");
  }

  emotibit.setup();
  xTaskCreatePinnedToCore(hrSamplingTask_async, "HRSamplingTask", 4096, &emotibit, 1, NULL, 1);

  // Initialize BLE
  if (!BLE.begin()) {
    Serial.println("Starting Bluetooth® Low Energy failed!");
    while (1)
      delay(10);
  }

  // Configure BLE service + characteristics
  BLE.setLocalName("SensoryMonitor");
  BLE.setAdvertisedService(sensorService);

  sensorService.addCharacteristic(soundLevelChar);
  sensorService.addCharacteristic(lightLevelChar);
  sensorService.addCharacteristic(heartRateChar);
  BLE.addService(sensorService);

  // Set initial values
  soundLevelChar.writeValue(0.0f);
  lightLevelChar.writeValue(0.0f);
  heartRateChar.writeValue((uint8_t)0);

  // Start advertising
  BLE.advertise();
  Serial.println("Bluetooth® device active, waiting for connections...");
}

void loop() {
  // Wait for a central to connect
  BLEDevice central = BLE.central();
  if (!central)
    return;

  Serial.print("Connected to central: ");
  Serial.println(central.address());

  while (central.connected()) {
    // Periodic sensor read & BLE update
    if (millis() - lastReadingTime >= readingInterval) {
      readSensors();
      updateBLECharacteristics();
      lastReadingTime = millis();
    }
  }

  Serial.print("Disconnected from central: ");
  Serial.println(central.address());
  BLE.advertise();
}

void readSensors() {
  // Sound
  portENTER_CRITICAL(&soundLevelMutex_async);
  soundLevel = latestSoundLevelDb_async;
  portEXIT_CRITICAL(&soundLevelMutex_async);
  Serial.print("Sound Level (dB): ");
  Serial.println(soundLevel);

  // Light
  lightLevel = readLightLevel();
  Serial.print("Light Level (lux): ");
  Serial.println(lightLevel);

  // Heart‑rate via PPG peak detection
  portENTER_CRITICAL(&HRbpmMutex_async);
  heartRate = latestHRLevelBpm_async;
  portEXIT_CRITICAL(&HRbpmMutex_async);
  Serial.print("Heart Rate (BPM): ");
  Serial.println(heartRate);
}

// ===== SOUND SAMPLING =====
const int SOUND_PIN = 15;
const int SOUND_SAMPLES = 512;
const float VREF = 3.3f;
const float ADC_MAX = 4095.0f;    // 12‑bit
const float P_REF = 0.00002f;     // 20 µPa
const float SENSITIVITY = 2.49f;  // ← replace with your calibrated V/Pa

float soundMean = 0, soundM2 = 0;
int soundCount = 0;
float latestSoundDb = 0;

void soundSamplingTask_async(void* pvParameters) {
  for (;;) {  // <- Infinite loop!
    // remove DC bias + get true RMS (Welford)
    float mean = 0, M2 = 0;
    for (int i = 1; i <= SOUND_SAMPLES; i++) {
      float x = analogRead(SOUND_PIN);
      float d = x - mean;
      mean += d / i;
      M2 += d * (x - mean);
    }
    float rmsCounts = sqrt(M2 / SOUND_SAMPLES);
    // convert to volts & pressure
    float voltageRMS = rmsCounts * (VREF / ADC_MAX);
    float pressurePa = voltageRMS / SENSITIVITY;
    float dBSPL = (pressurePa > 0)
                    ? 20.8f * log10(pressurePa / P_REF)
                    : 0.0f;

    portENTER_CRITICAL(&soundLevelMutex_async);
    latestSoundLevelDb_async = dBSPL;
    portEXIT_CRITICAL(&soundLevelMutex_async);

    vTaskDelay(pdMS_TO_TICKS(40));  // Wait 40ms = 25Hz
  }
}


// ====== LIGHT SAMPLING ======
const int BUF_SZ = 8;  // how many past readings to keep
float luxBuf[BUF_SZ];
int bufIdx = 0;
bool bufFilled = false;

const float CALIBRATION_FACTOR = 0.812;
const float V_LAMBDA_WEIGHTS[] = {
  0.0012, 0.0230, 0.1390, 0.5030,
  0.9950, 0.7570, 0.2650, 0.0170
};

float readRawLux() {
  uint16_t channel_data[12];
  if (!as7341.readAllChannels(channel_data))
    return -1.0;

  float sum = 0;
  for (int i = 0; i < 8; i++) {
    sum += channel_data[i] * V_LAMBDA_WEIGHTS[i];
  }
  return sum * CALIBRATION_FACTOR/8;
}

float readLightLevel() {
  // 1) read raw
  float lux = readRawLux();
  if (lux < 0)
    return -1.0;

  // 2) store in ring buffer
  luxBuf[bufIdx] = lux;
  bufIdx = (bufIdx + 1) % BUF_SZ;
  if (bufIdx == 0)
    bufFilled = true;

  // 3) compute average of buffer
  int count = bufFilled ? BUF_SZ : bufIdx;
  float acc = 0;
  for (int i = 0; i < count; i++)
    acc += luxBuf[i];
  float avg = acc / count;

  return avg;
}

// ====== HEART RATE SMAPLING ======
// ====================
// Heart Rate Detection (EmotiBit, Async Task, ESP32)
// ====================

// ----- Constants -----
const float HR_SAMPLING_RATE_HZ = 25.0f;                           // Sampling rate (Hz)
const size_t HR_WINDOW_SEC = 6;                                    // Window for HR calc (seconds)
const size_t HR_BUFFER_LEN = HR_SAMPLING_RATE_HZ * HR_WINDOW_SEC;  // Samples per window

const float HR_PEAK_THRESHOLD_RATIO = 0.6f;   // 60% of max = valid peak
const float HR_MIN_PEAK_INTERVAL_SEC = 0.3f;  // Ignore peaks closer than this
const size_t HR_MIN_PEAK_INTERVAL_SAMPLES = HR_SAMPLING_RATE_HZ * HR_MIN_PEAK_INTERVAL_SEC;

const TickType_t HR_TASK_DELAY_TICKS = pdMS_TO_TICKS(40);  // 25 Hz (40 ms)

// ----- Data Buffers -----
float greenBuf[HR_BUFFER_LEN];
float redBuf[HR_BUFFER_LEN];
float irBuf[HR_BUFFER_LEN];

// ----- EmotiBit DataType Defines -----
#define PPG_GREEN_CHANNEL EmotiBit::DataType::PPG_GREEN
#define PPG_RED_CHANNEL EmotiBit::DataType::PPG_RED
#define PPG_IR_CHANNEL EmotiBit::DataType::PPG_INFRARED

// ====================
// Heartbeat Detection Function
// ====================
float detectHeartBeats(float* green, float* red, float* ir, size_t len, float samplingRate = HR_SAMPLING_RATE_HZ) {
  // Use green for primary, combine if you want more robust
  float* channel = green;  // For now, use green

  // Find global max for dynamic thresholding
  float maxVal = *std::max_element(channel, channel + len);
  int peakCount = 0;
  for (size_t i = 1; i < len - 1; i++) {
    if (
      channel[i] > channel[i - 1] && channel[i] > channel[i + 1] && channel[i] > HR_PEAK_THRESHOLD_RATIO * maxVal) {
      peakCount++;
      // Skip samples to avoid double-counting the same beat
      i += HR_MIN_PEAK_INTERVAL_SAMPLES;
    }
  }
  float timeSec = len / samplingRate;
  if (timeSec == 0) return 0;
  float bpm = (peakCount / timeSec) * 60.0f;
  return bpm;
}

// ====================
// Async Heart Rate Task
// ====================
void hrSamplingTask_async(void* pvParameters) {
  EmotiBit* emotibit = (EmotiBit*)pvParameters;  // Pass pointer if needed, or use global
  while (1) {
    // Collect a window of samples (green, red, IR)
    size_t idx = 0;
    while (idx < HR_BUFFER_LEN) {
      // For each sample, grab new data for all channels
      size_t gCount = emotibit->readData(PPG_GREEN_CHANNEL, &greenBuf[idx], 1);
      size_t rCount = emotibit->readData(PPG_RED_CHANNEL, &redBuf[idx], 1);
      size_t iCount = emotibit->readData(PPG_IR_CHANNEL, &irBuf[idx], 1);

      if (gCount > 0 && rCount > 0 && iCount > 0) {
        idx++;
      }
      vTaskDelay(HR_TASK_DELAY_TICKS);  // 25Hz
    }

    // Process HR from window
    float bpmG = detectHeartBeats(greenBuf, redBuf, irBuf, HR_BUFFER_LEN, HR_SAMPLING_RATE_HZ);
    // Optionally, use red/IR or average/more logic for robustness
    // float bpmR = detectHeartBeats(redBuf, greenBuf, irBuf, HR_BUFFER_LEN, HR_SAMPLING_RATE_HZ);
    // float bpmI = detectHeartBeats(irBuf, greenBuf, redBuf, HR_BUFFER_LEN, HR_SAMPLING_RATE_HZ);
    // float bpmFinal = (bpmG + bpmR + bpmI) / 3.0f;

    portENTER_CRITICAL(&HRbpmMutex_async);
    latestHRLevelBpm_async = bpmG;  // Or use averaged/median value if wanted
    portEXIT_CRITICAL(&HRbpmMutex_async);

    Serial.print("Heart Rate (BPM): ");
    Serial.println(latestHRLevelBpm_async);
    // Repeat
  }
}
void updateBLECharacteristics() {
  soundLevelChar.writeValue(soundLevel);
  lightLevelChar.writeValue(lightLevel);
  heartRateChar.writeValue((uint8_t)heartRate);
}
