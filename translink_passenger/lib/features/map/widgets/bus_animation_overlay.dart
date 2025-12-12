import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../models/bus_models.dart';
import 'bus_marker_generator.dart';

class BusAnimationController {
  final TickerProvider vsync;
  final Function(Map<String, BitmapDescriptor>) onUpdate;
  
  final Map<String, BitmapDescriptor> _cachedIcons = {};
  final Map<String, AnimationController> _posControllers = {};
  final Map<String, AnimationController> _rotControllers = {};
  final Map<String, AnimationController> _vibeControllers = {};
  
  final Map<String, LatLng> _currentPos = {};
  final Map<String, double> _currentRot = {};
  final Map<String, double> _vibeOffset = {};

  BusAnimationController({required this.vsync, required this.onUpdate});

  void dispose() {
    for (var ctrl in _posControllers.values) ctrl.dispose();
    for (var ctrl in _rotControllers.values) ctrl.dispose();
    for (var ctrl in _vibeControllers.values) ctrl.dispose();
    _posControllers.clear();
    _rotControllers.clear();
    _vibeControllers.clear();
  }

  Future<void> updateBuses(List<LiveBusData> buses) async {
    final now = DateTime.now();
    
    for (var bus in buses) {
      final id = bus.busNumber;
      final targetPos = LatLng(bus.lat, bus.lng);
      final targetRot = bus.heading;
      final bool isDelayed = bus.status == 'delayed';
      
      // 1. Generate/Refresh Premium Icon
      if (!_cachedIcons.containsKey(id)) {
        _cachedIcons[id] = await BusMarkerGenerator.generateMarker(
          busNumber: id,
          routeName: bus.routeName,
          color: isDelayed ? const Color(0xFFFFB300) : const Color(0xFF10B981),
          isLive: true,
        );
      }

      // Initial State Setup
      if (!_currentPos.containsKey(id)) {
        _currentPos[id] = targetPos;
        _currentRot[id] = targetRot;
        _startVibration(id);
        continue;
      }

      // 2. Position LERP (easeInOutCubic) with Snap Threshold
      final LatLng latestCurrent = _currentPos[id]!;
      final double distToNewTarget = _calculateDistance(latestCurrent, targetPos);

      // Jitter Protection: Ignore movements less than 5 meters
      if (distToNewTarget < 5.0) {
        continue; 
      }

      if (distToNewTarget > 300.0) { 
         // Snap immediately for large jumps (teleporting/long delays)
         _posControllers[id]?.stop();
         _currentPos[id] = targetPos;
      } else {
         // Smooth slide for normal movement
         _posControllers[id]?.dispose();
         
         final ctrl = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 1500));
         _posControllers[id] = ctrl;
         
         final startPos = latestCurrent; // Start from WHERE WE ARE NOW (animated)
         final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
         
         ctrl.addListener(() {
           if (!ctrl.isAnimating) return;
           final t = curve.value;
           final lat = startPos.latitude + (targetPos.latitude - startPos.latitude) * t;
           final lng = startPos.longitude + (targetPos.longitude - startPos.longitude) * t;
           _currentPos[id] = LatLng(lat, lng);
           onUpdate(_cachedIcons);
         });
         ctrl.forward();
      }

      // 3. Rotation LERP (Shortest Path)
      if (_currentRot[id] != targetRot) {
        _rotControllers[id]?.dispose();
        final ctrl = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 800));
        _rotControllers[id] = ctrl;

        
        double startRot = _currentRot[id]!;
        double endRot = targetRot;
        
        // Shortest path logic: ensure we don't spin 300 degrees if 10 degrees is enough
        double diff = endRot - startRot;
        while (diff < -180) diff += 360;
        while (diff > 180) diff -= 360;
        endRot = startRot + diff;

        final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
        ctrl.addListener(() {
          _currentRot[id] = startRot + (endRot - startRot) * curve.value;
          onUpdate(_cachedIcons);
        });
        ctrl.forward();
      }
    }
    onUpdate(_cachedIcons);
  }

  // 4. Micro-animation: Idling Vibration
  void _startVibration(String id) {
    if (_vibeControllers.containsKey(id)) return;
    
    final ctrl = AnimationController(
      vsync: vsync, 
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    
    _vibeControllers[id] = ctrl;
    ctrl.addListener(() {
      // Very subtle vertical/scale vibration simulation
      _vibeOffset[id] = (ctrl.value * 0.000005); // Tiny lat offset for vibration
      onUpdate(_cachedIcons);
    });
  }

  LatLng getPosition(String busNumber) {
    return _currentPos[busNumber] ?? const LatLng(0, 0);
  }

  double getRotation(String busNumber) => _currentRot[busNumber] ?? 0.0;

  double _calculateDistance(LatLng p1, LatLng p2) {
    return math.sqrt(math.pow(p1.latitude - p2.latitude, 2) + math.pow(p1.longitude - p2.longitude, 2)) * 111320.0;
  }

  BitmapDescriptor? getIcon(String busNumber) => _cachedIcons[busNumber];


  BitmapDescriptor get defaultIcon => BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
}
