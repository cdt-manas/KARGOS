<p align="center">
  <h1 align="center">🧭 KARGOS — AI-Powered Indoor Navigation</h1>
  <p align="center">
    <em>Voice-guided, obstacle-aware indoor navigation for visually impaired users</em>
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11-blue?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/YOLOv8-Nano-green?logo=yolo" alt="YOLOv8">
  <img src="https://img.shields.io/badge/ML%20Kit-Barcode-orange?logo=google" alt="ML Kit">
  <img src="https://img.shields.io/badge/Platform-Android-brightgreen?logo=android" alt="Android">
</p>

---

## 📖 Overview

**KARGOS** is a real-time AI indoor navigation system built with Flutter. It uses QR code-based localization, YOLOv8 object detection for obstacle avoidance, and voice-guided turn-by-turn navigation to help visually impaired users navigate indoor spaces safely and independently.

### ✨ Key Features

| Feature | Description |
|---|---|
| 🗺️ **QR-Based Localization** | Scans QR codes placed at key indoor locations to determine the user's position on the building map |
| 🧠 **YOLOv8 Obstacle Detection** | Detects 80+ object categories (people, chairs, tables, bottles, etc.) in real-time using on-device AI |
| 🗣️ **Voice Navigation** | Provides spoken turn-by-turn directions with step counting ("Turn left, then walk 5 steps") |
| 🚨 **Emergency Mode** | Say *"EMERGENCY"* to sound a siren and directly call Manas (+91 9835709105) |
| ⚡ **Triple-Press Launch** | Triple-press **Volume Up** anyway to launch the app instantly via Accessibility Service |
| 🎤 **Voice Commands** | Users can say destinations like *"Take me to the Library"* or ask to *"Please repeat"* |
| 🏃 **Step Detection** | Counts steps using the device's accelerometer for precise distance tracking |
| 🛡️ **Two-Tier Safety** | Motion-sensing triggers YOLOv8 AI only on movement, optimizing battery and safety |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│                    KARGOS App                    │
├──────────┬──────────┬──────────┬────────────────┤
│  Camera  │  Voice   │   Maps   │  Navigation    │
│  Module  │  Module  │  Module  │    Engine       │
├──────────┼──────────┼──────────┼────────────────┤
│ • QR Det │ • TTS    │ • Graph  │ • A* Pathfind  │
│ • YOLO   │ • STT    │ • Loader │ • Route Engine │
│ • Motion │ • Commands│ • Repo  │ • Path Planner │
│ • Steps  │ • Alerts │ • Nodes  │ • Turn-by-Turn │
└──────────┴──────────┴──────────┴────────────────┘
```

### 📁 Project Structure

```
KARGOS/
├── app/
│   ├── lib/
│   │   ├── camera/           # QR detector, YOLO detector, step detector, frame processor
│   │   ├── alerts/           # Voice notifications, warning system
│   │   ├── localization/     # QR anchor manager, position tracker
│   │   ├── maps/             # Graph model, indoor map loader, map repository
│   │   ├── navigation/       # A* algorithm, path planner, route engine
│   │   ├── voice/            # TTS/STT wrappers, voice command handler
│   │   ├── ui/               # Navigation screen, camera view, voice button
│   │   └── main.dart         # App entry point
│   ├── assets/
│   │   ├── maps/             # Building map JSON files
│   │   ├── labels.txt        # COCO class labels (80 objects)
│   │   └── yolov8n.tflite    # YOLOv8 Nano model for on-device inference
│   └── demo/                 # Demo QR code images (PNG)
├── yolov8n.pt                # YOLOv8 PyTorch weights (for training/export)
├── yolov8n.onnx              # YOLOv8 ONNX model (for cross-platform use)
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.11
- **Android Studio** with Android SDK
- **Android Device** (physical device required for camera access)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/cdt-manas/KARGOS.git
cd KARGOS

# 2. Install Flutter dependencies
cd app
flutter pub get

# 3. Connect your Android device and run
flutter run -d <device-id>
```

> 💡 **Tip:** Use `flutter devices` to find your device ID.

### Permissions Required

The app will request the following permissions on first launch:
- 📷 **Camera** — For QR scanning and obstacle detection
- 🎤 **Microphone** — For voice command input
- 📍 **Location** — To append GPS coordinates to safety protocols (optional)
- 📞 **Phone** — Required to initiate the emergency call to Manas
- 🔊 **Audio** — For spoken navigation instructions

---

## 🎮 Usage

### Quick Start

1. **Launch the app** — You'll see a camera view with the prompt: *"Point camera at Building Entrance QR code..."*
2. **Scan the entrance QR** — This loads the building map
3. **Speak your destination** — Say *"Take me to the Library"* or *"Navigate to Laboratory"*
4. **Follow voice instructions** — The app provides turn-by-turn guidance with step counting
5. **Stay safe** — YOLO detects obstacles and warns you in real-time

### Voice Commands

| Command | Action |
|---|---|
| *"Take me to the Library"* | Starts navigation to the Library |
| *"Navigate to Laboratory"* | Starts navigation to the Laboratory |
| *"Take me to Washroom"*| Starts navigation to the Washroom |
| *"Please repeat"*     | Re-announces route summary and instructions |
| *"EMERGENCY"*         | **SOS**: Triggers alarm and calls Manas |
| *"stop alarm"*        | Stops the siren once safety is reached |

### Supported Locations (Demo)

| Location | QR Code ID |
|---|---|
| 🏛️ Entrance | `QR_ENTRANCE` |
| 📚 Library | `QR_LIB` |
| 🔬 Laboratory | `QR_LAB` |
| 🚻 Washroom | `QR_WR` |
| 🚻 Lavatory | `QR_LAV` |

---

## 🧠 AI & ML Pipeline

### QR Code Detection
- Uses **Google ML Kit Barcode Scanning** for fast, reliable QR detection
- Optimized with **grayscale-only NV21 buffer** processing (Y-plane extraction with padding removal)
- Scans every 15th frame to balance responsiveness with performance

### Object Detection (YOLOv8 Nano)
- Runs **on-device** using TensorFlow Lite with XNNPACK delegate
- Detects **80 COCO object classes** at **0.6 confidence threshold**
- Pre-processing includes **camera rotation handling** and **letterboxing** for accurate classification
- Triggered every 40th frame, or immediately on motion detection

### Two-Tier Safety System
1. **Tier 1 — Motion Detection:** Lightweight frame differencing detects movement, triggering YOLO.
2. **Tier 2 — YOLO Object Detection:** Full AI inference identifies specific obstacles (People, Furniture, etc.) and warns the user.

### 🛡️ SOS & Emergency Protocol
- **Panic Command**: Triggered by voice or through the app interface.
- **Siren**: Plays a high-frequency looped `siren.mp3` to alert people nearby.
- **Direct Call**: Instantly initiates a phone call to the emergency contact (**Manas**) using the device's system dialer.
- **Always-Ready**: The Accessibility Service monitors hardware buttons 24/7 to ensure the app is never more than a few clicks away.

---

## 🛠️ Tech Stack

| Component | Technology |
|---|---|
| Framework | Flutter 3.11 (Dart) |
| Object Detection | YOLOv8 Nano (TFLite) |
| QR Scanning | Google ML Kit Barcode |
| Text-to-Speech | Flutter TTS |
| Speech-to-Text | Speech to Text |
| Pathfinding | A* Algorithm |
| Step Counting | Accelerometer (sensors_plus) |
| Camera | Flutter Camera Plugin |

---

## 📄 License

This project is developed for educational and hackathon purposes.

---

<p align="center">
  <strong>Built with ❤️ for accessibility</strong>
</p>
