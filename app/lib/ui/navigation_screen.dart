import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../alerts/voice_notifications.dart';
import '../alerts/warning_system.dart';
import '../localization/position_tracker.dart';
import '../localization/qr_anchor_manager.dart';
import '../maps/indoor_map_loader.dart';
import '../maps/map_repository.dart';
import '../navigation/a_star_algorithm.dart';
import '../navigation/path_planner.dart';
import '../navigation/route_engine.dart';
import '../voice/speech_to_text.dart';
import '../voice/text_to_speech.dart';
import '../voice/voice_command_handler.dart';

import '../camera/qr_detector.dart';
import 'camera_view.dart';
import 'voice_button.dart';

class MainNavigationScreen extends StatefulWidget {
  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late TTSWrapper ttsWrapper;
  late STTWrapper sttWrapper;
  late VoiceNotifications voiceAlerts;
  late VoiceCommandHandler commandHandler;
  late WarningSystem warningSystem;

  late MapRepository mapRepo;
  late IndoorMapLoader mapLoader;
  late PositionTracker positionTracker;
  late QRAnchorManager qrManager;
  late PathPlanner pathPlanner;

  bool isListening = false;
  String currentStatusText = "Point camera at Building Entrance QR code...";
  String lastUserCommand = "";
  String? _lastAnnouncedNode;
  String _lastQRSeen = "";

  List<String>? _activePath;
  int _nextPathIndex = 0;

  CameraController? cameraController;
  late QRDetector qrDetector;

  bool _isProcessing = false;
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    ttsWrapper = TTSWrapper();
    await ttsWrapper.init();
    sttWrapper = STTWrapper();
    await sttWrapper.init();
    voiceAlerts = VoiceNotifications(tts: ttsWrapper);
    commandHandler = VoiceCommandHandler();
    warningSystem = WarningSystem(notifications: voiceAlerts);

    mapRepo = MapRepository();
    mapLoader = IndoorMapLoader(repository: mapRepo);
    positionTracker = PositionTracker();
    qrManager = QRAnchorManager(mapRepository: mapRepo, positionTracker: positionTracker);

    final aStar = AStarAlgorithm(mapRepository: mapRepo);
    pathPlanner = PathPlanner(aStar: aStar, routeEngine: RouteEngine());

    qrDetector = QRDetector();

    await _initCamera();

    voiceAlerts.queueNotification(
      "Welcome. Please scan the building entrance Q R code to begin.",
    );
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await cameraController!.initialize();
    final rotation = _rotationFromSensor(cameras[0]);

    cameraController!.startImageStream((image) {
      _frameCount++;
      // Only run QR every 5th frame
      if (_frameCount % 5 != 0) return;
      if (_isProcessing) return;
      _isProcessing = true;

      qrDetector.processFrame(image, rotation, (qr) {
        // Debounce: only handle if QR value changed
        if (qr != _lastQRSeen) {
          _lastQRSeen = qr;
          _handleQRResult(qr);
        }
      }).then((_) {
        _isProcessing = false;
      }).catchError((_) {
        _isProcessing = false;
      });
    });

    setState(() {});
  }

  InputImageRotation _rotationFromSensor(CameraDescription camera) {
    switch (camera.sensorOrientation) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  void _handleQRResult(String qrValue) async {
    if (!mapRepo.hasMap) {
      if (qrValue.contains("BUILDING")) {
        setState(() => currentStatusText = "QR Found! Loading map...");
        voiceAlerts.queueNotification("QR code detected. Loading map.");
        await mapLoader.loadMapFromQR(qrValue);
        if (mapRepo.hasMap) {
          positionTracker.updatePosition("Entrance");
          _lastAnnouncedNode = "Entrance";
          setState(() => currentStatusText = "Map Loaded. You are at: Entrance");
          voiceAlerts.queueNotification(
            "Map loaded. You are at the Entrance. Press the button and say where you want to go.",
          );
        }
      } else {
        setState(() => currentStatusText = "QR seen: $qrValue (need BUILDING QR)");
      }
    } else {
      qrManager.processQRData(qrValue);
      final currentNode = positionTracker.currentNode;
      if (currentNode != null) {
        setState(() => currentStatusText = "Location: ${currentNode.replaceAll('_', ' ')}");
        if (currentNode != _lastAnnouncedNode) {
          _lastAnnouncedNode = currentNode;
          voiceAlerts.queueNotification("You have reached ${currentNode.replaceAll('_', ' ')}.");
          if (_activePath != null && _nextPathIndex < _activePath!.length) {
            if (currentNode == _activePath![_nextPathIndex]) {
              _nextPathIndex++;
              if (_nextPathIndex < _activePath!.length) {
                final nextNode = _activePath![_nextPathIndex];
                final distance = mapRepo.currentGraph?.getDistance(currentNode, nextNode);
                voiceAlerts.queueNotification(
                  pathPlanner.routeEngine.getInstructionForStep(currentNode, nextNode, distance),
                );
              } else {
                voiceAlerts.queueNotification("You have reached your destination.");
                setState(() => currentStatusText = "Destination reached!");
                _activePath = null;
              }
            }
          }
        }
      }
    }
  }

  void _onVoiceButtonPressed() {
    if (isListening) {
      sttWrapper.stopListening();
      setState(() => isListening = false);
    } else {
      setState(() { isListening = true; currentStatusText = "Listening..."; });
      sttWrapper.startListening((words) {
        setState(() { lastUserCommand = words; isListening = false; });
        _processCommand(words);
      });
    }
  }

  void _processCommand(String command) {
    final result = commandHandler.parseCommand(command);
    if (result['intent'] == 'navigate') {
      final dest = result['destination']!;
      if (dest.isEmpty) { voiceAlerts.queueNotification("Destination not understood."); return; }
      if (!positionTracker.hasPosition) { voiceAlerts.queueNotification("Scan a QR code first."); return; }
      final rawPath = pathPlanner.findPath(positionTracker.currentNode!, dest);
      if (rawPath.isEmpty) {
        voiceAlerts.queueNotification("No path found to $dest.");
      } else if (rawPath.length == 1) {
        voiceAlerts.queueNotification("You are already at ${dest.replaceAll('_', ' ')}.");
      } else {
        setState(() { _activePath = rawPath; _nextPathIndex = 1; currentStatusText = "Navigating to $dest"; });
        voiceAlerts.queueNotification(pathPlanner.routeEngine.getRouteSummary(rawPath));
        final d = mapRepo.currentGraph?.getDistance(rawPath[0], rawPath[1]);
        voiceAlerts.queueNotification(pathPlanner.routeEngine.getInstructionForStep(rawPath[0], rawPath[1], d));
      }
    } else if (result['intent'] == 'locate') {
      voiceAlerts.queueNotification(positionTracker.hasPosition
        ? "You are near ${positionTracker.currentNode!.replaceAll('_', ' ')}."
        : "Location unknown. Scan a QR code.");
    } else {
      voiceAlerts.queueNotification("Command not recognized.");
    }
  }

  @override
  void dispose() {
    cameraController?.stopImageStream();
    cameraController?.dispose();
    qrDetector.dispose();
    ttsWrapper.stop();
    sttWrapper.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraView(controller: cameraController)),
          // Top status bar
          Positioned(
            top: 60, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                children: [
                  Text(currentStatusText,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                  if (lastUserCommand.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('You said: "$lastUserCommand"',
                      style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          // QR scan crosshair
          if (!mapRepo.hasMap)
            Center(
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          // Voice button
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Center(
              child: VoiceButton(isListening: isListening, onPressed: _onVoiceButtonPressed),
            ),
          ),
        ],
      ),
    );
  }
}
