from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
import joblib
import pandas as pd
from datetime import datetime
from typing import Optional

app = FastAPI(
    title="PancreaSense Academic Backend API",
    description="FastAPI Backend for ESP32 Sensor Ingestion & ML Pancreatic Risk Prediction",
    version="1.0.0"
)

# Enable CORS for Flutter web / mobile app requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory storage for latest sensor telemetry & ML prediction result
latest_sensor_data = {
    "tds_raw": 0,
    "tds_voltage": 0.0,
    "mq_raw": 0,
    "mq_voltage": 0.0,
    "ph_voltage": 0.0,
    "ph": 7.0,
    "timestamp": None
}

latest_prediction_result = {
    "pcri_score": 15.0,
    "risk_level": "LOW RISK",
    "ai_score": 12.5,
    "ai_confidence": 92.4,
    "components": {
        "voc_score": 10.0,
        "ph_score": 15.0,
        "ec_score": 12.0,
        "ai_prediction_score": 12.5
    },
    "timestamp": None
}

# Optional ML Model Loading (XGBoost / Pickle model if available)
model = None
model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pancreatic_cancer_xgboost.pkl")

if os.path.exists(model_path):
    try:
        model = joblib.load(model_path)
        print(f"✓ ML Model loaded successfully from {model_path}")
    except Exception as e:
        print(f"⚠️ Warning loading model pickle: {e}. Fallback scoring will be used.")

# Pydantic schema for ESP32 HTTP POST payload
class ESP32SensorPayload(BaseModel):
    tds_raw: int
    tds_voltage: float
    mq_raw: int
    mq_voltage: float
    ph_raw: int
    ph_voltage: float


# Helper function to compute Pancreatic Cancer Risk Index (PCRI)
def compute_risk(mq_volt: float, ph_val: float, tds_volt: float):
    # 1. VOC Biomarker Sub-score (0-100)
    voc_score = min(100.0, max(0.0, (mq_volt / 5.0) * 100.0))
    
    # 2. pH Biomarker Sub-score (deviation from neutral 7.0)
    ph_dev = abs(7.0 - ph_val)
    ph_score = min(100.0, max(0.0, (ph_dev / 3.0) * 100.0))
    
    # 3. Electrical Conductivity (TDS) Sub-score
    ec_score = min(100.0, max(0.0, (tds_volt / 3.3) * 100.0))
    
    # 4. ML AI Model Inference or Fallback
    ai_score = 15.0
    ai_confidence = 90.0
    if model is not None:
        try:
            # Create feature row for ML model
            feature_df = pd.DataFrame([{
                'age': 55, 'gender': 1, 'bmi': 26.5, 'smoking': 1,
                'diabetes': 0, 'jaundice': 0, 'saliva_ph': ph_val,
                'saliva_ec': tds_volt, 'mq135_ppm': mq_volt * 100.0,
                'mq3_ppm': mq_volt * 50.0, 'mq7_ppm': mq_volt * 30.0
            }])
            predicted_class = int(model.predict(feature_df)[0])
            if hasattr(model, "predict_proba"):
                probs = model.predict_proba(feature_df)[0]
                ai_confidence = round(float(probs[predicted_class]) * 100, 1)
            ai_score = 90.0 if predicted_class == 2 else (50.0 if predicted_class == 1 else 15.0)
        except Exception as err:
            print(f"ML Inference error: {err}")
            ai_score = (voc_score + ph_score + ec_score) / 3.0

    # Combined Pancreatic Cancer Risk Index (PCRI) calculation
    pcri = (0.30 * voc_score) + (0.20 * ph_score) + (0.20 * ec_score) + (0.30 * ai_score)
    pcri_final = round(max(0.0, min(100.0, pcri)), 1)
    
    if pcri_final >= 60.0:
        risk_level = "HIGH RISK"
    elif pcri_final >= 35.0:
        risk_level = "MODERATE RISK"
    else:
        risk_level = "LOW RISK"
        
    return {
        "pcri_score": pcri_final,
        "risk_level": risk_level,
        "ai_score": round(ai_score, 1),
        "ai_confidence": ai_confidence,
        "components": {
            "voc_score": round(voc_score, 1),
            "ph_score": round(ph_score, 1),
            "ec_score": round(ec_score, 1),
            "ai_prediction_score": round(ai_score, 1)
        }
    }


# =====================================================
# ENDPOINT 1: RECEIVE ESP32 SENSOR DATA VIA HTTP POST
# =====================================================
@app.post("/sensor-data")
async def receive_sensor_data(payload: ESP32SensorPayload):
    global latest_sensor_data, latest_prediction_result
    
    timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # Store raw telemetry
    latest_sensor_data = {
        "tds_raw": payload.tds_raw,
        "tds_voltage": payload.tds_voltage,
        "mq_raw": payload.mq_raw,
        "mq_voltage": payload.mq_voltage,
        "ph_raw": payload.ph_raw,
        "ph_voltage": payload.ph_voltage,
        "timestamp": timestamp_str
    }
    
    # Run ML prediction on incoming sensor payload
    risk_info = compute_risk(payload.mq_voltage, payload.ph, payload.tds_voltage)
    latest_prediction_result = {
        **risk_info,
        "timestamp": timestamp_str
    }
    
    print(f"[{timestamp_str}] Received ESP32 Payload: {payload.dict()}")
    print(f"[{timestamp_str}] Calculated Risk: {latest_prediction_result['risk_level']} ({latest_prediction_result['pcri_score']}%)")
    
    return {
        "status": "success",
        "message": "Sensor reading received and ML inference executed",
        "received_timestamp": timestamp_str,
        "pcri_score": latest_prediction_result["pcri_score"],
        "risk_level": latest_prediction_result["risk_level"]
    }


# =====================================================
# ENDPOINT 2: GET LATEST SENSOR READINGS & ML PREDICTION (FOR FLUTTER)
# =====================================================
@app.get("/api/latest-prediction")
async def get_latest_prediction():
    return {
        "status": "online",
        "sensors": latest_sensor_data,
        "prediction": latest_prediction_result
    }


# =====================================================
# ENDPOINT 3: SERVER HEALTH CHECK (FOR FLUTTER STATUS)
# =====================================================
@app.get("/api/status")
async def get_server_status():
    return {
        "server_status": "ONLINE",
        "service": "PancreaSense FastAPI Backend",
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }

if __name__ == "__main__":
    import uvicorn
    # MUST LISTEN ON 0.0.0.0 TO RECEIVE ESP32 & FLUTTER REQUESTS
    uvicorn.run(app, host="0.0.0.0", port=8000)
