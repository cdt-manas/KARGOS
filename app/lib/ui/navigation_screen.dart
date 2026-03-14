import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
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
import '../camera/step_detector.dart';
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
  late YoloDetector yoloDetector;
  late StepDetector stepDetector;

  int _remainingStepsToNextNode = 0;
  DateTime _lastStepAnnouncement = DateTime.now();
  bool _isProcessing = false;
  bool _isInitialized = false;
  int _frameCount = 0;
  Uint8List? _lastLuminance;
  bool _forceYolo = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // 1. Initialize synchronous services immediately to avoid LateInitializationError
    mapRepo = MapRepository();
    mapLoader = IndoorMapLoader(repository: mapRepo);
    positionTracker = PositionTracker();
    qrManager = QRAnchorManager(mapRepository: mapRepo, positionTracker: positionTracker);
    qrDetector = QRDetector();
    yoloDetector = YoloDetector();
    stepDetector = StepDetector(onStep: _onStepDetected);

    final aStar = AStarAlgorithm(mapRepository: mapRepo);
    pathPlanner = PathPlanner(aStar: aStar, routeEngine: RouteEngine());

    // 2. Complex async initializations
    try {
      ttsWrapper = TTSWrapper();
      await ttsWrapper.init();
      sttWrapper = STTWrapper();
      await sttWrapper.init();
      voiceAlerts = VoiceNotifications(tts: ttsWrapper);
      commandHandler = VoiceCommandHandler();
      warningSystem = WarningSystem(notifications: voiceAlerts);

      await yoloDetector.loadModel();
      await _initCamera();
      stepDetector.start();

      setState(() {
        _isInitialized = true;
      });

      voiceAlerts.queueNotification(
        "Welcome. Please scan the building entrance Q R code to begin.",
      );
    } catch (e) {
      print("Initialization error: $e");
      setState(() {
        currentStatusText = "Error initializing services: $e";
      });
    }
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

    DateTime lastFrameWithQR = DateTime.now();

    cameraController!.startImageStream((image) {
      _frameCount++;
      
      // Throttle heavily to avoid lag at medium resolution
      if (_frameCount % 10 == 0) _detectMotion(image);

      if (_isProcessing) return;

      if (_frameCount % 40 == 0 || _forceYolo) {
        _isProcessing = true;
        _forceYolo = false;
        yoloDetector.detectObstacles(image, rotation).then((obstacles) {
          if (obstacles.isNotEmpty) warningSystem.processDetectedObstacles(obstacles);
        }).catchError((e) {
          print("YOLO Error: $e");
        }).whenComplete(() => _isProcessing = false);
      } else if (_frameCount % 15 == 0) {
        _isProcessing = true;
        qrDetector.processFrame(image, rotation, (qr) {
          if (qr.isNotEmpty) {
            print("QR Scanned: $qr"); // Add debug log
            lastFrameWithQR = DateTime.now();
            if (qr != _lastQRSeen) {
              _lastQRSeen = qr;
              _handleQRResult(qr);
            }
          } else {
            if (DateTime.now().difference(lastFrameWithQR).inSeconds > 5) {
               _lastQRSeen = "";
            }
          }
        }).catchError((e) {
          print("QR Error: $e");
        }).whenComplete(() => _isProcessing = false);
      }
    });

    setState(() {});
  }

  void _onStepDetected() {
    if (_activePath != null && _remainingStepsToNextNode > 0) {
      setState(() {
        _remainingStepsToNextNode--;
        currentStatusText = "Walk to ${_activePath![_nextPathIndex].replaceAll('_', ' ')}: $_remainingStepsToNextNode steps more";
      });

      // Announce every step if it's <= 10, otherwise every few steps
      if (_remainingStepsToNextNode <= 10 || _remainingStepsToNextNode % 5 == 0) {
        final now = DateTime.now();
        if (now.difference(_lastStepAnnouncement).inMilliseconds > 1500) {
           voiceAlerts.queueNotification(pathPlanner.routeEngine.getStepCountdownInstruction(_remainingStepsToNextNode));
           _lastStepAnnouncement = now;
        }
      }
    }
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
                final direction = mapRepo.currentGraph?.getDirection(currentNode, nextNode) ?? "straight";
                _remainingStepsToNextNode = distance?.toInt() ?? 0;
                voiceAlerts.queueNotification(
                  pathPlanner.routeEngine.getInstructionForStep(currentNode, nextNode, distance, direction),
                );
              } else {
                _remainingStepsToNextNode = 0;
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
        setState(() {
          _activePath = rawPath;
          _nextPathIndex = 1;
          final d = mapRepo.currentGraph?.getDistance(rawPath[0], rawPath[1]);
          final dir = mapRepo.currentGraph?.getDirection(rawPath[0], rawPath[1]) ?? "straight";
          _remainingStepsToNextNode = d?.toInt() ?? 0;
          currentStatusText = "Navigating to $dest";
          voiceAlerts.queueNotification(pathPlanner.routeEngine.getRouteSummary(rawPath));
          voiceAlerts.queueNotification(pathPlanner.routeEngine.getInstructionForStep(rawPath[0], rawPath[1], d, dir));
        });
      }
    } else if (result['intent'] == 'locate') {
      voiceAlerts.queueNotification(positionTracker.hasPosition
        ? "You are near ${positionTracker.currentNode!.replaceAll('_', ' ')}."
        : "Location unknown. Scan a QR code.");
    } else if (result['intent'] == 'repeat') {
      _repeatNavigationInstructions();
    } else {
      voiceAlerts.queueNotification("Command not recognized.");
    }
  }

  void _repeatNavigationInstructions() {
    if (_activePath == null) {
      voiceAlerts.queueNotification("No active navigation to repeat.");
      return;
    }
    
    // 1. Repeat full route summary
    voiceAlerts.queueNotification(pathPlanner.routeEngine.getRouteSummary(_activePath!));
    
    // 2. Repeat current step instructions
    if (_nextPathIndex < _activePath!.length) {
      final current = _activePath![_nextPathIndex - 1];
      final next = _activePath![_nextPathIndex];
      final distance = mapRepo.currentGraph?.getDistance(current, next);
      final direction = mapRepo.currentGraph?.getDirection(current, next) ?? "straight";
      
      voiceAlerts.queueNotification("From your current location: ${pathPlanner.routeEngine.getInstructionForStep(current, next, distance, direction)}");
    }
  }

  void _detectMotion(CameraImage image) {
    if (image.planes.isEmpty) return;
    final yBuffer = image.planes[0].bytes;
    
    if (_lastLuminance == null || _lastLuminance!.length != yBuffer.length) {
      _lastLuminance = Uint8List(yBuffer.length);
      _lastLuminance!.setAll(0, yBuffer);
      return;
    }

    int diffCount = 0;
    const int step = 200; // Efficient sampling
    for (int i = 0; i < yBuffer.length; i += step) {
      if ((yBuffer[i] - _lastLuminance![i]).abs() > 45) {
        diffCount++;
      }
    }

    if (diffCount > 15) {
      _forceYolo = true;
    }

    // Efficiently update last frame without new allocation
    _lastLuminance!.setAll(0, yBuffer);
  }

  @override
  void dispose() {
    cameraController?.stopImageStream();
    cameraController?.dispose();
    qrDetector.dispose();
    stepDetector.stop();
    ttsWrapper.stop();
    sttWrapper.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text("Starting KARGOS...", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

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
