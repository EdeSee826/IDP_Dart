/*
  XIAO PICC IMU Sensor Firmware

  Upload this sketch to the single XIAO board used for monitoring.

    SENSOR_ID = 2  -> XIAO_MG24_Sensor_02, packet header im02

  Backend contract:
    BLE service:        1841
    IMU notify char:    FFF1
    Command write char: FFF2
    Battery notify:     FFF3

  Each IMU sample is 36 bytes:
    4 bytes  header      "im02"
    4 bytes  float       device time in seconds
    4 bytes  uint32_t    global sequence
    24 bytes 6 floats    ax, ay, az, gx, gy, gz

  Notifications send 5 samples together = 180 bytes.
*/

#include <ArduinoBLE.h>
#include <Wire.h>

// If your XIAO/IMU library uses a different include, change this block only.
// Seeed XIAO Sense boards commonly use LSM6DS3.
#include "LSM6DS3.h"

// -------------------- SENSOR ID --------------------
// The app backend now connects to one wearable sensor only.
#define SENSOR_ID 2

#if SENSOR_ID == 2
const char DEVICE_NAME[] = "XIAO_MG24_Sensor_02";
const char IMU_HEADER[] = "im02";
const char STATUS_HEADER[] = "st02";
const char NEUTRAL_HEADER[] = "nt02";
const char VALIDATION_HEADER[] = "va02";
#else
#error "SENSOR_ID must be 2"
#endif

// -------------------- BLE UUIDs --------------------
BLEService imuService("1841");
BLECharacteristic imuDataChar("FFF1", BLENotify, 180);
BLECharacteristic commandChar("FFF2", BLEWrite | BLEWriteWithoutResponse, 32);
BLECharacteristic batteryChar("FFF3", BLENotify | BLERead, 8);

// -------------------- IMU --------------------
// I2C_MODE and 0x6A are common for LSM6DS3 on Seeed XIAO Sense boards.
// If your board uses another IMU/address, adjust here.
LSM6DS3 imu(I2C_MODE, 0x6A);

const uint16_t SAMPLE_RATE_HZ = 50;
const uint32_t SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE_HZ;
const uint8_t SAMPLE_SIZE_BYTES = 36;
const uint8_t SAMPLES_PER_NOTIFICATION = 5;
const uint16_t NOTIFICATION_BYTES = SAMPLE_SIZE_BYTES * SAMPLES_PER_NOTIFICATION;

bool armed = false;
bool streaming = false;
uint32_t globalSeq = 0;
uint32_t nextSampleMicros = 0;
uint8_t packetBuffer[NOTIFICATION_BYTES];
uint8_t bufferedSamples = 0;

float neutralVector[3] = {0.0f, 0.0f, 0.0f};
bool hasNeutral = false;

// -------------------- Helpers --------------------
void writeHeader(uint8_t *dst, const char *header) {
  memcpy(dst, header, 4);
}

void writeFloat(uint8_t *dst, float value) {
  memcpy(dst, &value, sizeof(float));
}

void writeUInt32(uint8_t *dst, uint32_t value) {
  memcpy(dst, &value, sizeof(uint32_t));
}

float readBatteryVoltage() {
  // Simple placeholder. If your battery divider is wired to an analog pin,
  // replace this with the real ADC conversion.
  return 0.0f;
}

void notifyBattery() {
  uint8_t data[8];
  uint32_t rawAdc = 0;
  float voltage = readBatteryVoltage();
  memcpy(data, &rawAdc, 4);
  memcpy(data + 4, &voltage, 4);
  batteryChar.writeValue(data, sizeof(data));
}

bool readImu(float &ax, float &ay, float &az, float &gx, float &gy, float &gz) {
  ax = imu.readFloatAccelX();
  ay = imu.readFloatAccelY();
  az = imu.readFloatAccelZ();
  gx = imu.readFloatGyroX();
  gy = imu.readFloatGyroY();
  gz = imu.readFloatGyroZ();
  return true;
}

void buildImuSample(uint8_t *dst, float ax, float ay, float az, float gx, float gy, float gz) {
  writeHeader(dst, IMU_HEADER);
  writeFloat(dst + 4, millis() / 1000.0f);
  writeUInt32(dst + 8, globalSeq++);
  writeFloat(dst + 12, ax);
  writeFloat(dst + 16, ay);
  writeFloat(dst + 20, az);
  writeFloat(dst + 24, gx);
  writeFloat(dst + 28, gy);
  writeFloat(dst + 32, gz);
}

void sendSpecialPacket(const char *header, float v0, float v1, float v2, float v3, float v4, float v5) {
  uint8_t data[SAMPLE_SIZE_BYTES];
  writeHeader(data, header);
  writeFloat(data + 4, millis() / 1000.0f);
  writeUInt32(data + 8, globalSeq);
  writeFloat(data + 12, v0);
  writeFloat(data + 16, v1);
  writeFloat(data + 20, v2);
  writeFloat(data + 24, v3);
  writeFloat(data + 28, v4);
  writeFloat(data + 32, v5);
  imuDataChar.writeValue(data, sizeof(data));
}

void collectNeutral() {
  const int n = 250;  // 5 seconds at 50 Hz
  float sx = 0, sy = 0, sz = 0;

  for (int i = 0; i < n; i++) {
    float ax, ay, az, gx, gy, gz;
    readImu(ax, ay, az, gx, gy, gz);
    sx += ax;
    sy += ay;
    sz += az;
    delay(20);
  }

  neutralVector[0] = sx / n;
  neutralVector[1] = sy / n;
  neutralVector[2] = sz / n;
  hasNeutral = true;
  sendSpecialPacket(NEUTRAL_HEADER, neutralVector[0], neutralVector[1], neutralVector[2], 0, 0, 0);
}

void checkNeutral() {
  float ax, ay, az, gx, gy, gz;
  readImu(ax, ay, az, gx, gy, gz);

  // Backend performs final marker-down validation too.
  // v3 carries a rough angle estimate for compatibility with existing backend code.
  float dot = ax * neutralVector[0] + ay * neutralVector[1] + az * neutralVector[2];
  float magNow = sqrt(ax * ax + ay * ay + az * az);
  float magBase = sqrt(
    neutralVector[0] * neutralVector[0] +
    neutralVector[1] * neutralVector[1] +
    neutralVector[2] * neutralVector[2]
  );
  float angleDeg = 0.0f;
  if (hasNeutral && magNow > 0.001f && magBase > 0.001f) {
    float c = dot / (magNow * magBase);
    c = constrain(c, -1.0f, 1.0f);
    angleDeg = acos(c) * 180.0f / PI;
  }

  sendSpecialPacket(VALIDATION_HEADER, ax, ay, az, angleDeg, 0, 0);
}

void flushBufferedSamples() {
  if (bufferedSamples >= SAMPLES_PER_NOTIFICATION) {
    imuDataChar.writeValue(packetBuffer, NOTIFICATION_BYTES);
    bufferedSamples = 0;
  }
}

void sampleAndBuffer() {
  float ax, ay, az, gx, gy, gz;
  if (!readImu(ax, ay, az, gx, gy, gz)) {
    return;
  }

  uint8_t *dst = packetBuffer + (bufferedSamples * SAMPLE_SIZE_BYTES);
  buildImuSample(dst, ax, ay, az, gx, gy, gz);
  bufferedSamples++;
  flushBufferedSamples();
}

void handleCommand(String cmd) {
  cmd.trim();

  if (cmd == "ARM_START") {
    armed = true;
    streaming = false;
    bufferedSamples = 0;
    globalSeq = 0;
    sendSpecialPacket(STATUS_HEADER, 1, 0, 0, 0, 0, 0);
  } else if (cmd == "FIRE_START") {
    if (armed) {
      streaming = true;
      nextSampleMicros = micros();
      sendSpecialPacket(STATUS_HEADER, 2, 0, 0, 0, 0, 0);
    }
  } else if (cmd == "STOP") {
    streaming = false;
    armed = false;
    bufferedSamples = 0;
    sendSpecialPacket(STATUS_HEADER, 0, 0, 0, 0, 0, 0);
  } else if (cmd == "ENROLL_NEUTRAL" || cmd == "GET_NEUTRAL") {
    collectNeutral();
  } else if (cmd == "CHECK_NEUTRAL") {
    checkNeutral();
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);

  Wire.begin();
  if (imu.begin() != 0) {
    Serial.println("IMU initialization failed.");
  } else {
    Serial.println("IMU initialized.");
  }

  if (!BLE.begin()) {
    Serial.println("BLE initialization failed.");
    while (1) {
      delay(1000);
    }
  }

  BLE.setLocalName(DEVICE_NAME);
  BLE.setDeviceName(DEVICE_NAME);
  BLE.setAdvertisedService(imuService);

  imuService.addCharacteristic(imuDataChar);
  imuService.addCharacteristic(commandChar);
  imuService.addCharacteristic(batteryChar);
  BLE.addService(imuService);

  uint8_t initialBattery[8] = {0};
  batteryChar.writeValue(initialBattery, sizeof(initialBattery));

  BLE.advertise();
  Serial.print("Advertising as ");
  Serial.println(DEVICE_NAME);
}

void loop() {
  BLEDevice central = BLE.central();

  if (central) {
    Serial.print("Connected to ");
    Serial.println(central.address());

    uint32_t lastBatteryMs = 0;

    while (central.connected()) {
      BLE.poll();

      if (commandChar.written()) {
        char commandBuffer[33] = {0};
        int len = commandChar.valueLength();
        len = min(len, 32);
        commandChar.readValue((uint8_t *)commandBuffer, len);
        handleCommand(String(commandBuffer));
      }

      if (streaming) {
        uint32_t now = micros();
        if ((int32_t)(now - nextSampleMicros) >= 0) {
          nextSampleMicros += SAMPLE_INTERVAL_US;
          sampleAndBuffer();
        }
      }

      if (millis() - lastBatteryMs > 60000UL) {
        lastBatteryMs = millis();
        notifyBattery();
      }
    }

    streaming = false;
    armed = false;
    bufferedSamples = 0;
    Serial.println("Disconnected.");
  }
}
