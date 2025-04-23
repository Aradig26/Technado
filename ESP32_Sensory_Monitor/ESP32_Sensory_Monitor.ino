/*
 * ESP32 Sensory Overload Monitoring System
 * 
 * This sketch uses an ESP32 with EmotiBit and Adafruit AS7341 sensor
 * to monitor environmental conditions and send data to an iOS app.
 * 
 * Components used:
 * - EmotiBit (for heart rate monitoring)
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

// BLE Service and Characteristic UUIDs (must match iOS app)
#define SERVICE_UUID        "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define SOUND_UUID          "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
#define LIGHT_UUID          "BEB5483E-36E1-4688-B7F5-EA07361B26A9"
#define HEARTRATE_UUID      "BEB5483E-36E1-4688-B7F5-EA07361B26AA"

// Initialize sensors
Adafruit_AS7341 as7341;
EmotiBit emotibit;

// Pin assignments
const int soundSensorPin = A0;  // Analog pin for sound sensor

// BLE setup
BLEService sensorService(SERVICE_UUID);
BLEFloatCharacteristic soundLevelChar(SOUND_UUID, BLERead | BLENotify);
BLEFloatCharacteristic lightLevelChar(LIGHT_UUID, BLERead | BLENotify);
BLEUnsignedCharCharacteristic heartRateChar(HEARTRATE_UUID, BLERead | BLENotify);

// Variables for sensor readings
float soundLevel = 0.0;
float lightLevel = 0.0;
int heartRate = 0;

// Timing variables
unsigned long lastReadingTime = 0;
const unsigned long readingInterval = 1000;  // Read sensors every 1 second

void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 5000);  // Wait for serial connection
  
  Serial.println("Starting Sensory Overload Monitoring System");
  
  // Initialize AS7341 light sensor
  if (!as7341.begin()) {
    Serial.println("Could not find AS7341 light sensor");
    while (1) delay(10);
  }
  
  // Setup EmotiBit
  emotibit.setup();
  
  // Initialize BLE
  if (!BLE.begin()) {
    Serial.println("Starting Bluetooth® Low Energy failed!");
    while (1) delay(10);
  }
  
  // Set up BLE service and characteristics
  BLE.setLocalName("SensoryMonitor");
  BLE.setAdvertisedService(sensorService);
  
  sensorService.addCharacteristic(soundLevelChar);
  sensorService.addCharacteristic(lightLevelChar);
  sensorService.addCharacteristic(heartRateChar);
  
  BLE.addService(sensorService);
  
  // Set initial values
  soundLevelChar.writeValue(0.0);
  lightLevelChar.writeValue(0.0);
  heartRateChar.writeValue(0);
  
  // Start advertising
  BLE.advertise();
  Serial.println("Bluetooth® device active, waiting for connections...");
}

void loop() {
  // Listen for BLE connections
  BLEDevice central = BLE.central();
  
  if (central) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());
    
    // While connected
    while (central.connected()) {
      // Read sensors and update characteristics at specified interval
      if (millis() - lastReadingTime >= readingInterval) {
        readSensors();
        updateBLECharacteristics();
        lastReadingTime = millis();
      }
      
      // Update EmotiBit (for heart rate monitoring)
      emotibit.update();
    }
    
    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
  }
}

void readSensors() {
  // Read sound level
  soundLevel = readSoundLevel();
  Serial.print("Sound Level (dB): ");
  Serial.println(soundLevel);
  
  // Read light level
  lightLevel = readLightLevel();
  Serial.print("Light Level (lux): ");
  Serial.println(lightLevel);
  
  // Read heart rate
  heartRate = emotibit.readHeartRate();
  Serial.print("Heart Rate (BPM): ");
  Serial.println(heartRate);
}

float readSoundLevel() {
  // Read analog value from sound sensor
  int analogValue = analogRead(soundSensorPin);
  
  // Convert analog reading to approximate dB scale (this requires calibration for your specific sensor)
  // This formula is an example and should be adjusted based on your sensor specs and calibration
  float dBValue = map(analogValue, 0, 4095, 30, 100);
  
  return dBValue;
}

float readLightLevel() {
  // Read light values from AS7341 sensor
  uint16_t readings[12];
  
  // Check if sensor is ready
  if (!as7341.readAllChannels(readings)) {
    Serial.println("Error reading light sensor");
    return 0.0;
  }
  
  // Calculate approximate lux value from visible channels
  // This is a simplified formula and actual conversion should be calibrated
  float visibleLight = readings[AS7341_CHANNEL_415nm] + 
                       readings[AS7341_CHANNEL_445nm] + 
                       readings[AS7341_CHANNEL_480nm] + 
                       readings[AS7341_CHANNEL_515nm] + 
                       readings[AS7341_CHANNEL_555nm] + 
                       readings[AS7341_CHANNEL_590nm] + 
                       readings[AS7341_CHANNEL_630nm] + 
                       readings[AS7341_CHANNEL_680nm];
  
  // Convert to approximate lux (requires calibration)
  float luxValue = visibleLight / 8.0;
  
  return luxValue;
}

void updateBLECharacteristics() {
  soundLevelChar.writeValue(soundLevel);
  lightLevelChar.writeValue(lightLevel);
  heartRateChar.writeValue(heartRate);
} 