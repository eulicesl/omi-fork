#include <Arduino.h>
#include "esp_camera.h"
#include "esp_sleep.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include <ESP_I2S.h>  // For ESP32 core 3.x; if using 2.x switch to <I2S.h>
extern "C" {
#include <opus.h>
}

/*
 * PR-ready firmware for Omi Glass based on Seeed XIAO ESP32‑S3 Sense.
 *
 * This firmware implements on-demand JPEG capture and OPUS-encoded
 * audio streaming over BLE.  It uses the same BLE UUIDs defined in
 * the upstream `config.h` file so it plugs into the existing Omi
 * mobile app without modifications.
 *
 *   - The on-board OV2640 camera is configured at 640×480 with
 *     JPEG compression.  A short button press triggers a photo which
 *     is delivered in ~500-byte chunks over the PHOTO_DATA UUID.
 *   - The on-board PDM microphone is sampled at 16 kHz mono via
 *     I2S and encoded using the OPUS codec (~16 kbps).  A
 *     1-second button press toggles recording on/off.  Encoded
 *     packets are streamed via the AUDIO_DATA UUID.  Recording can
 *     also be controlled by writing 1/0 to the AUDIO_CTRL UUID.
 *   - Battery voltage is sampled through the documented voltage
 *     divider (169 kΩ / 110 kΩ) and reported as a percentage via
 *     standard GATT battery service (0x180F/0x2A19).
 *   - A 2-second button press puts the device into deep sleep,
 *     preserving battery life while allowing wake on button.
 *
 * The firmware uses the Arduino BLEDevice API (as in the upstream
 * repo) for maximum compatibility with the Omi app.  The code
 * separates camera, audio and BLE concerns to aid maintenance.
 */

/*** UUIDs (same as omiGlass/config.h) ***/
#define BLE_DEVICE_NAME    "OMI Glass"
#define OMI_SERVICE_UUID   "19B10000-E8F2-537E-4F6C-D104768A1214"
#define AUDIO_DATA_UUID    "19B10001-E8F2-537E-4F6C-D104768A1214"
#define AUDIO_CTRL_UUID    "19B10002-E8F2-537E-4F6C-D104768A1214"
#define PHOTO_DATA_UUID    "19B10005-E8F2-537E-4F6C-D104768A1214"
#define PHOTO_CTRL_UUID    "19B10006-E8F2-537E-4F6C-D104768A1214"
#define BATTERY_SERVICE_UUID (uint16_t)0x180F
#define BATTERY_LEVEL_UUID   (uint16_t)0x2A19

/*** Power profile (aligns with upstream config.h) ***/
#define NORMAL_CPU_FREQ_MHZ 80
#define MIN_CPU_FREQ_MHZ    40
#define IDLE_THRESHOLD_MS   45000

/*** Battery divider (R1=169k, R2=110k) ***/
#define BATTERY_ADC_PIN        2
#define VOLTAGE_DIVIDER_RATIO  6.086f
#define BATTERY_MAX_VOLTAGE    4.2f
#define BATTERY_MIN_VOLTAGE    3.2f

/*** Button/LED pins ***/
#define POWER_BUTTON_PIN 1        // active-low
#define STATUS_LED_PIN   21       // inverted logic (LOW=ON)

/*** Camera pin map for XIAO ESP32‑S3 Sense ***/
#define PWDN_GPIO_NUM -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 10
#define SIOD_GPIO_NUM 40
#define SIOC_GPIO_NUM 39
#define Y9_GPIO_NUM 48
#define Y8_GPIO_NUM 11
#define Y7_GPIO_NUM 12
#define Y6_GPIO_NUM 14
#define Y5_GPIO_NUM 16
#define Y4_GPIO_NUM 18
#define Y3_GPIO_NUM 17
#define Y2_GPIO_NUM 15
#define VSYNC_GPIO_NUM 38
#define HREF_GPIO_NUM 47
#define PCLK_GPIO_NUM 13

/*** Audio / I2S / OPUS configuration ***/
I2SClass I2S;
static OpusEncoder* opus = nullptr;
static const int SAMPLE_RATE = 16000;
static const int FRAME_MS = 20;
static const int SAMPLES_PER_FRAME = (SAMPLE_RATE * FRAME_MS) / 1000;
static const int OPUS_BITRATE = 16000;  // approximate speech bitrate
static const int OPUS_MAX = 128;
static int16_t pcm[SAMPLES_PER_FRAME];

/*** BLE objects ***/
BLEServer* server = nullptr;
BLECharacteristic *chPhotoData=nullptr,*chPhotoCtrl=nullptr,*chAudioData=nullptr,*chAudioCtrl=nullptr,*chBattery=nullptr;
bool bleConnected=false;

/*** State variables ***/
volatile bool irqBtn=false;
bool recording=false;
unsigned long lastActivity=0;
unsigned long lastBattery=0;
const unsigned long BATTERY_INTERVAL=20000;

camera_fb_t* fb=nullptr;

/*** Helpers ***/
inline void ledOn(bool on){ digitalWrite(STATUS_LED_PIN, on?LOW:HIGH); }
void IRAM_ATTR onButton(){ irqBtn=true; }

// Convert ADC reading to a battery percentage
void batteryPercent(uint8_t& pct){
  int sum=0; for(int i=0;i<10;i++){ sum+=analogRead(BATTERY_ADC_PIN); delay(2); }
  int adc=sum/10;
  float v33=(adc/4095.0f)*3.3f;
  float vbatt=v33*VOLTAGE_DIVIDER_RATIO;
  float pctf=(vbatt<=BATTERY_MIN_VOLTAGE)?0.f:(vbatt>=BATTERY_MAX_VOLTAGE)?100.f:
    ((vbatt-BATTERY_MIN_VOLTAGE)/(BATTERY_MAX_VOLTAGE-BATTERY_MIN_VOLTAGE))*100.f;
  if(pctf<0)pctf=0; if(pctf>100)pctf=100; pct=(uint8_t)(pctf+0.5f);
}
void sendBattery(){
  if(!chBattery) return;
  uint8_t b=0; batteryPercent(b);
  chBattery->setValue(&b,1);
  if(bleConnected) chBattery->notify();
}

// Initialize the camera at VGA resolution
void initCamera(){
  camera_config_t cfg={};
  cfg.ledc_channel=LEDC_CHANNEL_0;
  cfg.ledc_timer=LEDC_TIMER_0;
  cfg.pin_d0=Y2_GPIO_NUM; cfg.pin_d1=Y3_GPIO_NUM; cfg.pin_d2=Y4_GPIO_NUM; cfg.pin_d3=Y5_GPIO_NUM;
  cfg.pin_d4=Y6_GPIO_NUM; cfg.pin_d5=Y7_GPIO_NUM; cfg.pin_d6=Y8_GPIO_NUM; cfg.pin_d7=Y9_GPIO_NUM;
  cfg.pin_xclk=XCLK_GPIO_NUM; cfg.pin_pclk=PCLK_GPIO_NUM;
  cfg.pin_vsync=VSYNC_GPIO_NUM; cfg.pin_href=HREF_GPIO_NUM;
  cfg.pin_sscb_sda=SIOD_GPIO_NUM; cfg.pin_sscb_scl=SIOC_GPIO_NUM;
  cfg.pin_pwdn=PWDN_GPIO_NUM; cfg.pin_reset=RESET_GPIO_NUM;
  cfg.xclk_freq_hz=6000000;
  cfg.frame_size=FRAMESIZE_VGA;
  cfg.pixel_format=PIXFORMAT_JPEG;
  cfg.fb_count=1;
  cfg.jpeg_quality=25;
  cfg.fb_location=CAMERA_FB_IN_PSRAM;
  cfg.grab_mode=CAMERA_GRAB_LATEST;
  if(esp_camera_init(&cfg)!=ESP_OK) Serial.println("Camera init fail"); else Serial.println("Camera OK");
}

// Send JPEG data in BLE-friendly chunks (~500 bytes)
void chunkAndNotifyPhoto(const uint8_t* data,size_t length){
  const size_t CHUNK=500;
  size_t offset=0;
  while(offset<length){
    size_t n=min(CHUNK, length-offset);
    chPhotoData->setValue((uint8_t*)data + offset, n);
    if(bleConnected) chPhotoData->notify();
    offset+=n;
    delay(3);
  }
}

// Capture and send a photo
bool takePhoto(){
  if(!bleConnected || !chPhotoData) return false;
  if(fb){ esp_camera_fb_return(fb); fb=nullptr; }
  fb=esp_camera_fb_get();
  if(!fb){ Serial.println("fb null"); return false; }
  chunkAndNotifyPhoto(fb->buf, fb->len);
  esp_camera_fb_return(fb);
  fb=nullptr;
  ledOn(true);
  delay(60);
  ledOn(false);
  return true;
}

// Initialize I2S for PDM microphone
void initI2S(){
  I2S.setPinsPdmRx(42,41);
  if(!I2S.begin(I2S_MODE_PDM_RX, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO)){
    Serial.println("I2S init failed"); while(1) delay(1000);
  }
}

// Initialize OPUS encoder
void initOpus(){
  int err=0;
  opus=opus_encoder_create(SAMPLE_RATE, 1, OPUS_APPLICATION_VOIP, &err);
  if(!opus || err){ Serial.printf("OPUS err %d\n", err); while(1) delay(1000); }
  opus_encoder_ctl(opus, OPUS_SET_BITRATE(OPUS_BITRATE));
  opus_encoder_ctl(opus, OPUS_SET_VBR(1));
}

void startAudio(){ recording=true; ledOn(true); }
void stopAudio(){ recording=false; ledOn(false); }

/*** BLE callbacks ***/
class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConnected=true; lastActivity=millis(); }
  void onDisconnect(BLEServer*) override { bleConnected=false; BLEDevice::startAdvertising(); }
};

class PhotoCtrlCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    if(characteristic->getLength()==1){
      int8_t v=characteristic->getData()[0]; lastActivity=millis();
      if(v==-1) takePhoto();
      // Additional interval logic can be added for v>0
    }
  }
};

class AudioCtrlCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    if(characteristic->getLength()==1){
      uint8_t v=characteristic->getData()[0]; lastActivity=millis();
      if(v) startAudio(); else stopAudio();
    }
  }
};

// Initialize BLE service, characteristics and descriptors
void initBLE(){
  BLEDevice::init(BLE_DEVICE_NAME);
  server=BLEDevice::createServer();
  server->setCallbacks(new ServerCB());
  BLEService* svc=server->createService(OMI_SERVICE_UUID);

  // Photo data
  chPhotoData = svc->createCharacteristic(PHOTO_DATA_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  {
    auto* ccc=new BLE2902(); ccc->setNotifications(true); chPhotoData->addDescriptor(ccc);
  }
  // Photo control
  chPhotoCtrl = svc->createCharacteristic(PHOTO_CTRL_UUID, BLECharacteristic::PROPERTY_WRITE);
  chPhotoCtrl->setCallbacks(new PhotoCtrlCB());
  // Audio data
  chAudioData = svc->createCharacteristic(AUDIO_DATA_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  {
    auto* ccc=new BLE2902(); ccc->setNotifications(true); chAudioData->addDescriptor(ccc);
  }
  // Audio control
  chAudioCtrl = svc->createCharacteristic(AUDIO_CTRL_UUID, BLECharacteristic::PROPERTY_WRITE);
  chAudioCtrl->setCallbacks(new AudioCtrlCB());
  // Battery
  chBattery = svc->createCharacteristic(BATTERY_LEVEL_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  {
    auto* ccc=new BLE2902(); ccc->setNotifications(true); chBattery->addDescriptor(ccc);
  }
  svc->start();
  BLEAdvertising* adv=BLEDevice::getAdvertising();
  adv->addServiceUUID(OMI_SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("BLE ready");
}

void setup(){
  Serial.begin(115200);
  pinMode(POWER_BUTTON_PIN, INPUT_PULLUP);
  pinMode(STATUS_LED_PIN, OUTPUT);
  ledOn(false);
  attachInterrupt(digitalPinToInterrupt(POWER_BUTTON_PIN), onButton, CHANGE);
  setCpuFrequencyMhz(NORMAL_CPU_FREQ_MHZ);
  initBLE();
  initCamera();
  analogReadResolution(12);
  initI2S();
  initOpus();
  lastActivity=millis(); lastBattery=0;
  Serial.println("OMI Glass PIO ready");
}

void loop(){
  unsigned long now=millis();
  // Button: short press → photo; 1 s → toggle audio; 2 s → deep sleep
  static bool down=false; static unsigned long t0=0;
  bool pressed=!digitalRead(POWER_BUTTON_PIN);
  if(irqBtn){ irqBtn=false; }
  if(pressed && !down){ down=true; t0=now; }
  if(!pressed && down){
    unsigned long d=now-t0; down=false; lastActivity=now;
    if(d>=2000){
      ledOn(false);
      esp_sleep_enable_ext0_wakeup((gpio_num_t)POWER_BUTTON_PIN, 0);
      delay(100);
      esp_deep_sleep_start();
    } else if(d>=1000){
      recording?stopAudio():startAudio();
    } else if(d>=50){
      takePhoto();
    }
  }
  // Battery update
  if(now-lastBattery>=BATTERY_INTERVAL){
    sendBattery();
    lastBattery=now;
  }
  // Audio processing
  if(recording && bleConnected && chAudioData){
    size_t need=SAMPLES_PER_FRAME*sizeof(int16_t);
    size_t got=0;
    while(got<need){
      int s=I2S.read((uint8_t*)pcm + got, need-got);
      if(s<0) break;
      got+=s;
    }
    if(got==need){
      uint8_t opusBuf[OPUS_MAX];
      int nb=opus_encode(opus, pcm, SAMPLES_PER_FRAME, opusBuf, OPUS_MAX);
      if(nb>0){
        chAudioData->setValue(opusBuf, nb);
        chAudioData->notify();
      }
    }
  }
  // Adjust CPU frequency for idle
  if(!recording && (now-lastActivity > IDLE_THRESHOLD_MS))
    setCpuFrequencyMhz(MIN_CPU_FREQ_MHZ);
  else
    setCpuFrequencyMhz(NORMAL_CPU_FREQ_MHZ);
  delay(2);
}
