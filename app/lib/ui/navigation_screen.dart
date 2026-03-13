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
import '../camera/yolo_detector.dart';
import 'camera_view.dart';
import 'voice_button.dart';

class MainNavigationScreen extends StatefulWidget {
  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  // Services
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

  // UI State
  bool isListening = false;
  String currentStatusText = "Scanning for Building Entrance QR...";
  String lastUserCommand = "";
  String? _lastAnnouncedNode;

  // Navigation Session
  List<String>? _activePath;
  int _nextPathIndex = 0;

  // Unified Camera
  CameraController? cameraController;
  late QRDetector qrDetector;
  late YoloDetector yoloDetector;

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
    final routeEngine = RouteEngine();
    pathPlanner = PathPlanner(aStar: aStar, routeEngine: routeEngine);

    qrDetector = QRDetector();

    yoloDetector = YoloDetector();
    await yoloDetector.loadModel();

    await _initCamera();

    voiceAlerts.queueNotification(
      "Welcome. Please scan a building Entrance QR code to load the map.",
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
      if (_isProcessing) return;
      _isProcessing = true;

      _processFrame(image, rotation).then((_) {
        _isProcessing = false;
      }).catchError((e) {
        _isProcessing = false;
      });
    });

    setState(() {});
  }

  Future<void> _processFrame(CameraImage image, InputImageRotation rotation) async {
    // QR every 5 frames
    if (_frameCount % 5 == 0) {
      await qrDetector.processFrame(image, rotation, (qr) {
        _handleQRResult(qr);
      });
    }

    // YOLO every 20 frames
    if (_frameCount % 20 == 0) {
      final obstacles = await yoloDetector.detectObstacles(image);
      if (obstacles.isNotEmpty) {
        warningSystem.processDetectedObstacles(obstacles);
      }
    }
  }

  InputImageRotation _rotationFromSensor(CameraDescription camera) {
    switch (camera.sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void _handleQRResult(String qrValue) async {
    if (!mapRepo.hasMap) {
      if (qrValue.contains("BUILDING")) {
        setState(() => currentStatusText = "Loading Map...");
        await mapLoader.loadMapFromQR(qrValue);
        if (mapRepo.hasMap) {
          positionTracker.updatePosition("Entrance");
          _lastAnnouncedNode = "Entrance";
          setState(() => currentStatusText = "Map Loaded. Location: Entrance.");
          voiceAlerts.queueNotification(
            "Map loaded. You are at the Entrance. Press the button to navigate.",
          );
        }
      }
    } else {
      qrManager.processQRData(qrValue);
      final currentNode = positionTracker.currentNode;
      if (currentNode != null) {
        setState(() => currentStatusText = "Location: ${currentNode.replaceAll('_', ' ')}");
        if (currentNode != _lastAnnouncedNode) {
          _lastAnnouncedNode = currentNode;
          voiceAlerts.queueNotification(
            "You have reached ${currentNode.replaceAll('_', ' ')}.",
          );
          if (_activePath != null && _nextPathIndex < _activePath!.length) {
            if (currentNode == _activePath![_nextPathIndex]) {
              _nextPathIndex++;
              if (_nextPathIndex < _activePath!.length) {
                final nextNode = _activePath![_nextPathIndex];
                final distance = mapRepo.currentGraph?.getDistance(currentNode, nextNode);
                final instr = pathPlanner.routeEngine.getInstructionForStep(
                  currentNode, nextNode, distance,
                );
                voiceAlerts.queueNotification(instr);
              } else {
                voiceAlerts.queueNotification("You have reached your destination.");
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
      setState(() {
        isListening = true;
        currentStatusText = "Listening...";
      });
      sttWrapper.startListening((words) {
        setState(() {
          lastUserCommand = words;
          isListening = false;
        });
        _processCommand(words);
      });
    }
  }

  void _processCommand(String command) {
    final result = commandHandler.parseCommand(command);
    if (result['intent'] == 'navigate') {
      final dest = result['destination']!;
      if (dest.isEmpty) {
        voiceAlerts.queueNotification("Sorry, I didn't catch the destination.");
        return;
      }
      if (positionTracker.hasPosition) {
        final rawPath = pathPlanner.findPath(positionTracker.currentNode!, dest);
        if (rawPath.isEmpty) {
          voiceAlerts.queueNotification("I couldn't find a path to $dest.");
        } else if (rawPath.length == 1) {
          voiceAlerts.queueNotification(
            "You are already at the ${dest.replaceAll('_', ' ')}.",
          );
        } else {
          setState(() {
            _activePath = rawPath;
            _nextPathIndex = 1;
            currentStatusText = "Navigating to $dest";
          });
          voiceAlerts.queueNotification(pathPlanner.routeEngine.getRouteSummary(rawPath));
          final firstDistance = mapRepo.currentGraph?.getDistance(rawPath[0], rawPath[1]);
          voiceAlerts.queueNotification(
            pathPlanner.routeEngine.getInstructionForStep(rawPath[0], rawPath[1], firstDistance),
          );
        }
      } else {
        voiceAlerts.queueNotification("Current location unknown. Scan a QR anchor.");
      }
    } else if (result['intent'] == 'locate') {
      if (positionTracker.hasPosition) {
        voiceAlerts.queueNotification(
          "You are near ${positionTracker.currentNode!.replaceAll('_', ' ')}.",
        );
      } else {
        voiceAlerts.queueNotification("I am not sure where you are. Scan a nearby QR code.");
      }
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
          Positioned.fill(
            child: CameraView(controller: cameraController),
          ),
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    currentStatusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (lastUserCommand.isNotEmpty)
                    Text(
                      "You said: $lastUserCommand",
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: VoiceButton(
                isListening: isListening,
                onPressed: _onVoiceButtonPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
