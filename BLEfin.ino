#include <Adafruit_NeoPixel.h>
#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

/* ===== Pines según tu cableado FÍSICO ===== */
#define PIN_TIRA_DER    13    // tira derecha (10 LED)
#define PIN_TIRA_IZQ    12    // tira izquierda (10 LED)
#define PIN_TIRA_ABAJO  14    // tira trasera  (9 LED)

/* Botones (a GND) */
#define BOTON_DER        4
#define BOTON_IZQ       15

/* Cantidad de LEDs por tira */
#define NUM_DER     10
#define NUM_IZQ     10
#define NUM_ABAJO    9

/* Brillos y tiempos */
#define BRILLO_DEF        180   // brillo base direccionales (si appBrightness no cambia)
#define STEP_MS             60   // velocidad del barrido
#define HOLD_MS            120   // pausa al final del barrido
#define DEBOUNCE           200   // anti-rebote botones (ms)

/* Respirar (tira abajo cuando NO hay direccional) — rango seguro */
#define BREATH_MIN          55
#define BREATH_MAX         135
#define BREATH_PERIOD    1200UL

/* Brillo fijo cuando hay direccional o emergencia */
#define BRILLO_TRASERA     140

/* Refresco limitado de la tira inferior (eficiente y sin parpadeos) */
#define BOTTOM_REFRESH_MS   25

/* Emergencia (parpadeo sincronizado en ambas direccionales) */
#define EMERG_PERIOD_MS    500
#define EMERG_DUTY         0.5f

/* ===== BLE (GATT) ===== */
const char* BLE_DEVICE_NAME = "ChaquetaBLE";
#define UUID_SERVICE       "b0f90001-8c6a-4b3a-b1e1-a3f5f2d2c001"
#define UUID_LEFT          "b0f90010-8c6a-4b3a-b1e1-a3f5f2d2c010"  // u8 RW/Notify
#define UUID_RIGHT         "b0f90011-8c6a-4b3a-b1e1-a3f5f2d2c011"  // u8 RW/Notify
#define UUID_EMERGENCY     "b0f90012-8c6a-4b3a-b1e1-a3f5f2d2c012"  // u8 RW/Notify
#define UUID_BRIGHTNESS    "b0f90013-8c6a-4b3a-b1e1-a3f5f2d2c013"  // u8 RW/Notify
#define UUID_BATTMV        "b0f90020-8c6a-4b3a-b1e1-a3f5f2d2c020"  // u32 R/Notify (mV)
#define UUID_BATTPC        "b0f90021-8c6a-4b3a-b1e1-a3f5f2d2c021"  // u8  R/Notify (%)

/* BLE objs */
BLEServer*        g_server = nullptr;
BLEService*       g_service = nullptr;
BLECharacteristic *chLeft, *chRight, *chEmergency, *chBrightness, *chBattmV, *chBattPc;

/* ===== NeoPixels ===== */
Adafruit_NeoPixel stripDer(NUM_DER,   PIN_TIRA_DER,   NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel stripIzq(NUM_IZQ,   PIN_TIRA_IZQ,   NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel stripAbj(NUM_ABAJO, PIN_TIRA_ABAJO, NEO_GRB + NEO_KHZ800);

/* Colores */
uint32_t AMARILLO;                 // direccionales
uint32_t BLANCO;                   // trasera (base blanca)

/* Estados por botones */
bool runningDer = false, runningIzq = false;
int  frameDer = 0, frameIzq = 0;
unsigned long tDer = 0, tIzq = 0;
unsigned long lastToggleDer = 0, lastToggleIzq = 0;

/* Apagado visual seguro (ambos botones) */
bool allOff = false;
uint32_t bothPressedAt = 0;
const uint32_t LONG_PRESS_MS = 800;

/* Control de refresco de la tira inferior */
uint32_t lastBottomRefresh = 0;

/* Sentidos (ajusta si cambias montaje físico) */
const bool INVERT_DER = false;
const bool INVERT_IZQ = false;

/* ===== Estados App (BLE) ===== */
bool    appLeft = false;
bool    appRight = false;
bool    appEmergency = false;
uint8_t appBrightness = BRILLO_DEF; // 0..200 solo direccionales

/* ===== Batería simulada realista (SoC) ===== */
const float BATT_CAP_mAh = 2550.0f;
const float I_IDLE_mA    = 120.0f; // respirar abajo
const float I_ONE_mA     = 250.0f; // una direccional
const float I_BOTH_mA    = 500.0f; // ambas / emergencia
float     batt_soc       = 1.0f;   // 0..1
uint32_t  lastBattTick   = 0;
const uint32_t BATT_TICK_MS   = 5000; // tick y notify cada 5 s
uint32_t  lastBattNotify = 0;

/* ===== Helpers ===== */
static inline void setPixelDir(Adafruit_NeoPixel& s, int n, bool inv, uint32_t c) {
  int idx = inv ? (s.numPixels() - 1 - n) : n;
  s.setPixelColor(idx, c);
}
uint8_t breathBrightness(unsigned long now) {
  float phase = (now % BREATH_PERIOD) / (float)BREATH_PERIOD;
  float eased = 0.5f * (1.0f - cosf(phase * 2.0f * M_PI));
  int b = BREATH_MIN + (int)((BREATH_MAX - BREATH_MIN) * eased);
  if (b < 0) b = 0; if (b > 255) b = 255;
  return (uint8_t)b;
}
float estimateCurrent_mA(bool leftOn, bool rightOn, bool emergencyActive) {
  if (emergencyActive) return I_BOTH_mA;
  if (leftOn && rightOn) return I_BOTH_mA;
  if (leftOn || rightOn) return I_ONE_mA;
  return I_IDLE_mA;
}
uint32_t socTo_mV(float soc) {
  if (soc < 0) soc = 0; if (soc > 1) soc = 1;
  struct P { float soc; uint16_t mv; };
  const P tbl[] = {
    {1.00f, 8400}, {0.85f, 8000}, {0.70f, 7600}, {0.55f, 7400},
    {0.35f, 7200}, {0.20f, 7000}, {0.10f, 6600}, {0.00f, 6000}
  };
  for (int i = 0; i < 7; i++) {
    if (soc <= tbl[i].soc && soc >= tbl[i+1].soc) {
      float x = (soc - tbl[i+1].soc) / (tbl[i].soc - tbl[i+1].soc);
      return (uint32_t)(tbl[i+1].mv + x * (tbl[i].mv - tbl[i+1].mv) + 0.5f);
    }
  }
  return (uint32_t)(6000 + soc * (8400 - 6000));
}
uint8_t mV_to_percent(uint32_t mv) {
  if (mv >= 8400) return 100;
  if (mv <= 6000) return 0;
  struct P2 { uint16_t mv; uint8_t pct; };
  const P2 t[] = {
    {8400,100},{8000,85},{7600,70},{7400,55},
    {7200,35},{7000,20},{6600,10},{6000,0}
  };
  for (int i=0;i<7;i++){
    if (mv <= t[i].mv && mv >= t[i+1].mv){
      float x = (float)(mv - t[i+1].mv)/(float)(t[i].mv - t[i+1].mv);
      float pc = t[i+1].pct + x * (t[i].pct - t[i+1].pct);
      if (pc<0) pc=0; if(pc>100) pc=100;
      return (uint8_t)(pc+0.5f);
    }
  }
  return 0;
}
uint32_t getSimulatedBattery_mV(bool leftOn, bool rightOn, bool emergencyActive) {
  uint32_t now = millis();
  if (now - lastBattTick >= BATT_TICK_MS) {
    float I_mA = estimateCurrent_mA(leftOn, rightOn, emergencyActive);
    float dt_h = (now - lastBattTick) / 3600000.0f; // ms → horas
    lastBattTick = now;
    float dSoC = (I_mA * dt_h) / BATT_CAP_mAh;
    batt_soc -= dSoC;
    if (batt_soc < 0.0f) batt_soc = 0.0f;
  }
  return socTo_mV(batt_soc);
}

/* ===== Tira inferior ===== */
void renderBottom(unsigned long now, bool anyDirOrEmerg) {
  if (anyDirOrEmerg) {
    stripAbj.setBrightness(BRILLO_TRASERA);
    for (int i = 0; i < NUM_ABAJO; i++) stripAbj.setPixelColor(i, BLANCO);
  } else {
    uint8_t b = breathBrightness(now);
    stripAbj.setBrightness(b);
    for (int i = 0; i < NUM_ABAJO; i++) stripAbj.setPixelColor(i, BLANCO);
  }
  stripAbj.show();
}

/* ===== BLE Callbacks (escrituras desde app) ===== */
class CharWriteCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String v = c->getValue();
   if (c == chLeft && v.length())        appLeft = (v[0] != 0);
  else if (c == chRight && v.length())  appRight = (v[0] != 0);
  else if (c == chEmergency && v.length()) appEmergency = (v[0] != 0);
  else if (c == chBrightness && v.length()) {
      uint8_t b = (uint8_t)v[0];
      if (b > 200) b = 200;
      appBrightness = b;
      stripDer.setBrightness(appBrightness);
      stripIzq.setBrightness(appBrightness);
    }
    // eco de estado
    chLeft->setValue((uint8_t*)&appLeft, 1);         chLeft->notify();
    chRight->setValue((uint8_t*)&appRight, 1);       chRight->notify();
    chEmergency->setValue((uint8_t*)&appEmergency,1);chEmergency->notify();
    chBrightness->setValue(&appBrightness, 1);       chBrightness->notify();
  }
};

void setupBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  g_server = BLEDevice::createServer();
  g_service = g_server->createService(UUID_SERVICE);

  chLeft       = g_service->createCharacteristic(UUID_LEFT,       BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  chRight      = g_service->createCharacteristic(UUID_RIGHT,      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  chEmergency  = g_service->createCharacteristic(UUID_EMERGENCY,  BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  chBrightness = g_service->createCharacteristic(UUID_BRIGHTNESS, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  chBattmV     = g_service->createCharacteristic(UUID_BATTMV,     BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chBattPc     = g_service->createCharacteristic(UUID_BATTPC,     BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);

  chLeft->addDescriptor(new BLE2902());
  chRight->addDescriptor(new BLE2902());
  chEmergency->addDescriptor(new BLE2902());
  chBrightness->addDescriptor(new BLE2902());
  chBattmV->addDescriptor(new BLE2902());
  chBattPc->addDescriptor(new BLE2902());

  static CharWriteCB cb;
  chLeft->setCallbacks(&cb);
  chRight->setCallbacks(&cb);
  chEmergency->setCallbacks(&cb);
  chBrightness->setCallbacks(&cb);

  // valores iniciales
  chLeft->setValue((uint8_t*)&appLeft,1);
  chRight->setValue((uint8_t*)&appRight,1);
  chEmergency->setValue((uint8_t*)&appEmergency,1);
  chBrightness->setValue(&appBrightness,1);

  // batería inicial
  uint32_t mv = socTo_mV(batt_soc);
  uint8_t  pc = mV_to_percent(mv);
  chBattmV->setValue((uint8_t*)&mv, 4);
  chBattPc->setValue(&pc, 1);

  g_service->start();
  g_server->getAdvertising()->addServiceUUID(UUID_SERVICE);
  g_server->getAdvertising()->start();
}

/* ===== Setup ===== */
void setup() {
  pinMode(BOTON_DER, INPUT_PULLUP);
  pinMode(BOTON_IZQ, INPUT_PULLUP);

  stripDer.begin();  stripIzq.begin();  stripAbj.begin();
  stripDer.setBrightness(BRILLO_DEF);
  stripIzq.setBrightness(BRILLO_DEF);
  stripAbj.clear(); stripAbj.show();

  AMARILLO = stripDer.Color(255, 160, 0);
  BLANCO   = stripDer.Color(190, 190, 190);

  setupBLE();

  renderBottom(millis(), false);

  lastBattTick   = millis();
  lastBattNotify = lastBattTick;
}

/* ===== Loop ===== */
void loop() {
  unsigned long now = millis();

  /* Lectura botones */
  bool leftDown  = (digitalRead(BOTON_IZQ) == LOW);
  bool rightDown = (digitalRead(BOTON_DER) == LOW);

  // Apagado visual seguro (ambos)
  if (leftDown && rightDown) {
    if (bothPressedAt == 0) bothPressedAt = now;
    if (!allOff && (now - bothPressedAt) > LONG_PRESS_MS) {
      runningDer = runningIzq = false;
      stripDer.clear();  stripDer.show();
      stripIzq.clear();  stripIzq.show();
      stripAbj.clear();  stripAbj.show();
      allOff = true;
    }
  } else {
    bothPressedAt = 0;
    if (allOff) allOff = false;
  }

  // Si no estamos en “todo apagado”, toggles
  if (!allOff) {
    if (rightDown && (now - lastToggleDer) > DEBOUNCE) {
      runningDer = !runningDer; lastToggleDer = now; frameDer = 0;
      if (!runningDer) { stripDer.clear(); stripDer.show(); }
    }
    if (leftDown && (now - lastToggleIzq) > DEBOUNCE) {
      runningIzq = !runningIzq; lastToggleIzq = now; frameIzq = 0;
      if (!runningIzq) { stripIzq.clear(); stripIzq.show(); }
    }
  }

  /* Estados efectivos combinados con prioridad a EMERGENCIA */
  bool effEmergency = (!allOff) && appEmergency;
  bool effLeft  = (!allOff) && (runningIzq || appLeft)  && !effEmergency;
  bool effRight = (!allOff) && (runningDer || appRight) && !effEmergency;

  /* Brightness desde app (solo direccionales) */
  stripDer.setBrightness(appBrightness);
  stripIzq.setBrightness(appBrightness);

  /* Direccionales / Emergencia */
  if (effEmergency) {
    unsigned long ph = now % EMERG_PERIOD_MS;
    bool on = (ph < (unsigned long)(EMERG_PERIOD_MS * EMERG_DUTY));
    if (on) {
      for (int i=0;i<NUM_DER;i++) stripDer.setPixelColor(i, AMARILLO);
      for (int i=0;i<NUM_IZQ;i++) stripIzq.setPixelColor(i, AMARILLO);
    } else {
      stripDer.clear();
      stripIzq.clear();
    }
    stripDer.show();
    stripIzq.show();
  } else {
    if (effRight && (now - tDer) >= STEP_MS) {
      tDer = now;
      stripDer.clear();
      for (int i = 0; i <= frameDer && i < NUM_DER; i++)
        setPixelDir(stripDer, i, INVERT_DER, AMARILLO);
      stripDer.show();
      frameDer++;
      if (frameDer > NUM_DER) { delay(HOLD_MS); stripDer.clear(); stripDer.show(); frameDer = 0; }
    } else if (!effRight) { stripDer.clear(); stripDer.show(); }

    if (effLeft && (now - tIzq) >= STEP_MS) {
      tIzq = now;
      stripIzq.clear();
      for (int i = 0; i <= frameIzq && i < NUM_IZQ; i++)
        setPixelDir(stripIzq, i, INVERT_IZQ, AMARILLO);
      stripIzq.show();
      frameIzq++;
      if (frameIzq > NUM_IZQ) { delay(HOLD_MS); stripIzq.clear(); stripIzq.show(); frameIzq = 0; }
    } else if (!effLeft) { stripIzq.clear(); stripIzq.show(); }
  }

  /* Tira inferior */
  if (!allOff && (now - lastBottomRefresh >= BOTTOM_REFRESH_MS)) {
    bool anyDirOrEmerg = effEmergency || effLeft || effRight;
    renderBottom(now, anyDirOrEmerg);
    lastBottomRefresh = now;
  }

  /* Batería simulada + Notify (mV y %) cada 5 s */
  if (now - lastBattNotify >= BATT_TICK_MS) {
    lastBattNotify = now;
    uint32_t mv = getSimulatedBattery_mV(effLeft, effRight, effEmergency);
    uint8_t  pc = mV_to_percent(mv);
    chBattmV->setValue((uint8_t*)&mv, 4);
    chBattPc->setValue(&pc, 1);
    chBattmV->notify();
    chBattPc->notify();
  }
}
