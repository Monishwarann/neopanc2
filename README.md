# NeoPanc 🩺 Volatile Organic Compound (VOC) & Salivary Biomarker Risk Screening System

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python Version](https://img.shields.io/badge/Python-3.10%2B-brightgreen.svg)](backend/)
[![Framework](https://img.shields.io/badge/Framework-Flask%20%7C%20Flutter-blueviolet.svg)](flutter_app/)
[![Hardware](https://img.shields.io/badge/Hardware-ESP32%20%7C%20IoT-orange.svg)](firmware/)
[![AI Model](https://img.shields.io/badge/ML%20Model-Random%20Forest%20%2F%20XGBoost-success.svg)](backend/models/)
[![Accuracy](https://img.shields.io/badge/Model%20Accuracy-84.17%25-brightgreen.svg)](docs/final_report.md)

**NeoPanc** is an end-to-end, non-invasive, AI-driven IoT risk screening platform for early pancreatic cancer indicators. By fusing exhaled breath volatile organic compounds (VOCs) and salivary biomarkers (pH and electrical conductivity) with clinical survey parameters, the system computes a continuous **Pancreatic Cancer Risk Index (PCRI)** score (0–100) and provides actionable risk-stratified clinical recommendations.

---

## 📌 Executive Summary & Clinical Context

Pancreatic ductal adenocarcinoma (PDAC) has one of the lowest 5-year survival rates (~11%) among all cancers, largely due to late-stage diagnosis. Early symptoms are non-specific, and initial diagnostics currently rely on costly imaging (CT, MRI, EUS) or invasive biopsies. 

**NeoPanc** addresses this challenge by providing a **low-cost, portable, non-invasive primary risk screening tool** suitable for point-of-care environments and preliminary clinical evaluations.

### Key Biomarker Channels
1. **Total Dissolved Solids (TDS Sensor - GPIO32):** Salivary and fluid ionic concentration measured continuously in raw ADC and Volts.
2. **Volatile Organic Compounds (MQ Gas Sensor - GPIO33):** Exhaled breath VOC and metabolic gas markers measured via analog voltage.
3. **Salivary Acidity (pH Sensor - GPIO34):** Salivary pH and physiological acidity shifts.
4. **Clinical Risk Parameters:** Patient age, BMI, smoking/alcohol habits, diabetes status, family history, weight loss, abdominal discomfort, appetite changes, and jaundice.

---

## 🔌 Hardware Schematics & Pin Mapping

The hardware prototype utilizes an **ESP32 microcontroller** reading live 12-bit ADC values continuously every 1 second.

### ESP32 Pin Connection Table
| Component | Function / Channel | ESP32 Pin | Signal Level | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **TDS Sensor** | Ionic Concentration / TDS | **GPIO 32 (ADC1)** | 0.0V - 3.3V | Continuously sampled every 1s |
| **MQ Gas Sensor** | VOC / Metabolic Gas | **GPIO 33 (ADC1)** | 0.0V - 3.3V | External 5V rail heater |
| **pH Sensor** | Salivary Acidity (pH) | **GPIO 34 (ADC1)** | 0.0V - 3.3V | Calibrated analog driver board |

> [!NOTE]
> Telemetry is posted via HTTP POST to `http://<LAPTOP_IP>:8000/sensor-data` and served live to Flutter mobile app and Web Dashboard.

---

## 📁 Repository Directory Structure

```text
NeoPanc/
├── backend/                        # Python Flask REST API & ML Server
│   ├── app.py                      # Flask Application Entry Point & API Routes
│   ├── database.py                 # SQLite ORM Database Schemas
│   ├── generate_dataset.py         # Synthetic Medical Screening Data Generator
│   ├── train_model.py              # ML Model Training & Serialization Script
│   ├── requirements.txt            # Python Dependencies List
│   ├── render.yaml                 # Deployment configuration for Render
│   ├── models/                     # Saved ML Models (`model.pkl`, `scaler.pkl`)
│   ├── templates/                  # Web Dashboard HTML Templates (`index.html`)
│   └── static/                     # Web Dashboard CSS & JavaScript Assets
├── flutter_app/                    # Mobile Application (Flutter/Dart)
│   ├── lib/                        # Flutter Application Source Code
│   │   ├── main.dart               # App Entry Point
│   │   ├── screens/                # UI Screens (Dashboard, Questionnaire, Results)
│   │   └── services/               # API & Battery Service Connectors
│   ├── android/                    # Native Android Platform Files
│   ├── web/                        # Web Build Platform Configuration
│   └── pubspec.yaml                # Flutter Dependencies File
├── firmware/                       # IoT Device Firmware
│   └── esp32_firmware.ino          # ESP32 C++ Arduino Code (Multi-sensor Telemetry)
├── docs/                           # Project Research & Technical Documentation
│   ├── ieee_paper.md               # Draft IEEE Research Paper Manuscript
│   ├── patent_draft.md             # Invention Patent Application Specification
│   ├── final_report.md             # Complete Project & Thesis Report
│   ├── block_diagram.md            # System Architecture & Sequence Diagrams
│   ├── circuit_diagram.md          # Hardware Schematic & Electrical Connections
│   └── user_manual.md              # User & Clinical System Operational Guide
└── README.md                       # Project Overview & Setup Documentation
```

---

## ⚡ Quick Start & Installation Guide

### 1. Flask Backend Setup

```bash
# Clone the repository
git clone https://github.com/Monishwarann/neopanc1.git
cd neopanc1/backend

# Create a virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# (Optional) Generate training dataset and train model
python generate_dataset.py
python train_model.py

# Run the Flask development server
python app.py
```
The server will start at `http://localhost:5000`.

---

### 2. Flutter Mobile Application Setup

```bash
cd neopanc1/flutter_app

# Get dependencies
flutter pub get

# Run on connected device or emulator
flutter run
```

---

### 3. ESP32 Firmware Setup

1. Open `firmware/esp32_firmware.ino` in **Arduino IDE**.
2. Install `WiFi.h` and `HTTPClient.h` libraries (built-in for ESP32 core).
3. Update WiFi credentials and backend API endpoint URL:
   ```cpp
   const char* ssid = "YOUR_WIFI_SSID";
   const char* password = "YOUR_WIFI_PASSWORD";
   const char* serverEndpoint = "http://YOUR_SERVER_IP:5000/api/telemetry";
   ```
4. Select board **ESP32 Dev Module** and upload the firmware.

---

## 🌐 API Endpoint Reference

| Method | Endpoint | Description | Request Payload Sample |
| :---: | :--- | :--- | :--- |
| `POST` | `/api/telemetry` | Submit raw sensor telemetry from ESP32 | `{"user_id": 1, "mq135": 14.2, "mq3": 8.5, "mq7": 5.1, "saliva_ph": 6.8, "saliva_ec": 1.4}` |
| `POST` | `/api/predict` | Run AI Risk Screening calculation | `{"age": 55, "bmi": 26.5, "smoking": 1, "diabetes": 0, "mq135": 14.2, ...}` |
| `GET` | `/api/generate-pdf/<id>` | Download compiled PDF clinical report | *URL Parameter: `log_id`* |
| `GET` | `/health` | Server health check endpoint | Returns `{"status": "healthy"}` |

---

## 📄 License & Academic Reference

This repository is licensed under the [MIT License](LICENSE).

If you use this work, firmware code, or biomarker dataset in your research or project, please cite:

```bibtex
@article{health_care_ai_2026,
  title={AI-Driven Non-Invasive Multi-Sensor IoT-Based Early Pancreatic Cancer Risk Screening System Using Breath and Saliva Biomarkers},
  author={Monishwaran K. et al.},
  journal={IEEE Research Documentation / NeoPanc Technical Specifications},
  year={2026}
}
```
