# AI Indoor Navigation Demo Guide

Welcome to the hackathon-ready demo for the Visually Impaired Navigation application!

## Demo Preparation
1. Ensure the Flutter app is running on a physical Android or iOS device. Simulators will NOT have camera access.
2. Ensure you have granted Camera and Microphone permissions.
3. Print or display the QR codes located in the `/demo` folder on another screen.

## Guided User Flow (Hackathon Demo)
**Step 1. Building Entrance**
- Point the camera at `qr_entrance.png`.
- The application will recognize "BUILDING_MAC_01" and load `sample_building.json`.
- *Voice Alert:* "Map loaded. You are at the Entrance..."

**Step 2. Voice Command**
- Tap the large Microphone button at the bottom of the screen.
- Say clearly: **"Take me to Library"**
- The A* algorithm will calculate: `Entrance -> Stairs -> Entrance` (or equivalent predefined shortest path `Entrance -> Corridor_A -> Corridor_B -> Library`).
- *Voice Alert:* "Walk straight towards Corridor A. From Corridor A, head towards Corridor B..."

**Step 3. Continuous Localization**
- Point the camera at `qr_corridor_a.png`.
- The system automatically reads `NODE:Corridor_A`.
- The screen will update: `Location: Corridor_A`.

**Step 4. Obstacle Detection**
- Point the camera at a physical Chair or Person.
- The YOLOv8 model (which activates every 3 frames) will detect it.
- *Voice Alert:* "Chair ahead. Please be careful." (Throttled to not spam the user).

**Step 5. Where Am I?**
- Tap the Mic button again.
- Say: **"Where am I?"**
- *Voice Alert:* "You are near Corridor A."

## Note on AI Models
- The bounding box `yolov8n.tflite` model was stubbed for the hackathon boilerplate to save space. During the physical hackathon, drop the standard `yolov8n.tflite` into `assets/yolov8n.tflite` and add `yolov8n.tflite` to the `pubspec.yaml` assets block.
