#include <WiFi.h>
#include <HTTPClient.h>

// =====================================================
// 1. WIFI & SERVER CONFIGURATION
// =====================================================

const char* WIFI_SSID = "Redmi 12 5G";

// *** ENTER YOUR WIFI PASSWORD HERE ***
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD"; // <-- EDIT THIS LINE

// *** ENTER YOUR LAPTOP IP ADDRESS HERE ***
// Example: "http://192.168.1.15:8000/sensor-data"
const char* SERVER_URL = "http://YOUR_LAPTOP_IP:8000/sensor-data"; // <-- EDIT THIS LINE


// =====================================================
// 2. ESP32 SENSOR PINS
// =====================================================

const int TDS_PIN = 32; // TDS Sensor on GPIO32
const int MQ_PIN  = 33; // MQ Gas Sensor on GPIO33
const int PH_PIN  = 34; // pH Sensor on GPIO34


// =====================================================
// 3. ADC PARAMETERS
// =====================================================

const float ESP32_ADC_REF = 3.3; // ESP32 3.3V reference
const int ADC_MAX         = 4095; // 12-bit ADC max value


// =====================================================
// 4. TIMING CONTROL (1 SECOND UPDATE INTERVAL)
// =====================================================

unsigned long lastExecutionTime = 0;
const unsigned long UPDATE_INTERVAL = 1000; // 1000 ms = 1 second


// =====================================================
// FUNCTION: ADC TO VOLTAGE CONVERSION
// =====================================================

float adcToVoltage(int adcValue)
{
  return ((float)adcValue / ADC_MAX) * ESP32_ADC_REF;
}


// =====================================================
// FUNCTION: WI-FI INITIALIZATION
// =====================================================

void initWiFi()
{
  Serial.println();
  Serial.print("Connecting to Wi-Fi SSID: ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20)
  {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  Serial.println();

  if (WiFi.status() == WL_CONNECTED)
  {
    Serial.println("✓ Wi-Fi Connected Successfully!");
    Serial.print("ESP32 Local IP Address: ");
    Serial.println(WiFi.localIP());
  }
  else
  {
    Serial.println("⚠️ Wi-Fi not connected yet. Monitoring will continue offline.");
  }
}


// =====================================================
// FUNCTION: SEND HTTP POST DATA TO FASTAPI SERVER
// =====================================================

void sendHTTPData(
  int tdsRaw,
  float tdsVoltage,
  int mqRaw,
  float mqVoltage,
  int phRaw,
  float phVoltage
)
{
  HTTPClient http;
  http.setTimeout(2000); // 2 second timeout to prevent loop blocking

  if (!http.begin(SERVER_URL))
  {
    Serial.println("[HTTP] Connection failed: Invalid Server URL format.");
    return;
  }

  http.addHeader("Content-Type", "application/json");

  // Build JSON Payload
  String json = "{";
  json += "\"tds_raw\":" + String(tdsRaw) + ",";
  json += "\"tds_voltage\":" + String(tdsVoltage, 3) + ",";
  json += "\"mq_raw\":" + String(mqRaw) + ",";
  json += "\"mq_voltage\":" + String(mqVoltage, 3) + ",";
  json += "\"ph_raw\":" + String(phRaw) + ",";
  json += "\"ph_voltage\":" + String(phVoltage, 3);
  json += "}";

  int httpCode = http.POST(json);

  if (httpCode > 0)
  {
    Serial.print("[HTTP] Server Response Code: ");
    Serial.println(httpCode);
  }
  else
  {
    Serial.print("[HTTP] Send Error: ");
    Serial.print(httpCode);
    Serial.print(" (");
    Serial.print(http.errorToString(httpCode));
    Serial.println(")");
  }

  http.end();
}


// =====================================================
// SETUP FUNCTION
// =====================================================

void setup()
{
  Serial.begin(115200);
  delay(1500);

  Serial.println();
  Serial.println("==========================================");
  Serial.println(" PANCREASENSE ESP32 REAL-TIME SENSOR UNIT ");
  Serial.println("==========================================");

  // Configure 12-bit ADC & 11dB attenuation (up to 3.3V input)
  analogReadResolution(12);
  analogSetPinAttenuation(TDS_PIN, ADC_11db);
  analogSetPinAttenuation(MQ_PIN, ADC_11db);
  analogSetPinAttenuation(PH_PIN, ADC_11db);

  // Initialize Wi-Fi
  initWiFi();
}


// =====================================================
// MAIN LOOP FUNCTION (NON-BLOCKING 1-SECOND INTERVAL)
// =====================================================

void loop()
{
  unsigned long currentMillis = millis();

  if (currentMillis - lastExecutionTime >= UPDATE_INTERVAL)
  {
    lastExecutionTime = currentMillis;

    // 1. Read Actual Live ADC Values
    int tdsRaw = analogRead(TDS_PIN);
    float tdsVoltage = adcToVoltage(tdsRaw);

    int mqRaw = analogRead(MQ_PIN);
    float mqVoltage = adcToVoltage(mqRaw);

    int phRaw = analogRead(PH_PIN);
    float phVoltage = adcToVoltage(phRaw);

    // 2. Print Exact Requested Serial Monitor Format
    Serial.print("GPIO32 TDS = ");
    Serial.print(tdsRaw);
    Serial.print(" | ");
    Serial.print(tdsVoltage, 3);
    Serial.println(" V");

    Serial.print("GPIO33 MQ  = ");
    Serial.print(mqRaw);
    Serial.print(" | ");
    Serial.print(mqVoltage, 3);
    Serial.println(" V");

    Serial.print("GPIO34 pH  = ");
    Serial.print(phRaw);
    Serial.print(" | ");
    Serial.print(phVoltage, 3);
    Serial.println(" V");

    Serial.println("------------------------------");

    // 3. Send HTTP POST Data if Wi-Fi is Connected
    if (WiFi.status() == WL_CONNECTED)
    {
      sendHTTPData(tdsRaw, tdsVoltage, mqRaw, mqVoltage, phRaw, phVoltage);
    }
    else
    {
      Serial.println("[Wi-Fi Disconnected - Retrying Wi-Fi...]");
      WiFi.begin(WIFI_SSID, WIFI_PASS);
    }
  }
}
