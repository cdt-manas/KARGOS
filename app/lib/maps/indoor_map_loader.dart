import 'dart:convert';
import 'package:flutter/services.dart';
import 'graph_model.dart';
import 'map_repository.dart';

class IndoorMapLoader {
  final MapRepository repository;

  IndoorMapLoader({required this.repository});

  /// Simulates fetching map JSON based on an entrance QR scan.
  /// In a real scenario, this might download from a URL inside the QR.
  Future<void> loadMapFromQR(String qrData) async {
    try {
      // For hackathon: Load a local JSON if the QR indicates a sample building.
      // Example QR Data might be: "BUILDING_MAC_01" -> load sample_building.json
      final jsonString = await rootBundle.loadString('assets/maps/sample_building.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      final graph = GraphModel.fromJson(jsonMap);
      
      repository.setCurrentGraph(graph);
      // ignore: avoid_print
      print("Successfully loaded map with ${graph.nodes.length} nodes");
    } catch (e) {
      // ignore: avoid_print
      print("Error loading map: $e");
    }
  }
}
