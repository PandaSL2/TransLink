import 'package:flutter/foundation.dart';
import 'package:translink_passenger/models/bus_models.dart';

class RideProvider with ChangeNotifier {
  AiDiscoveredRoute? _activeRoute;
  bool _isRideActive = false;
  bool _isSharingActive = false;
  bool _isRemindMeActive = false;

  AiDiscoveredRoute? get activeRoute => _activeRoute;
  bool get isRideActive => _isRideActive;
  bool get isSharingActive => _isSharingActive;
  bool get isRemindMeActive => _isRemindMeActive;

  void startRide(AiDiscoveredRoute route) {
    _activeRoute = route;
    _isRideActive = true;
    notifyListeners();
  }

  void stopRide() {
    _activeRoute = null;
    _isRideActive = false;
    _isSharingActive = false;
    _isRemindMeActive = false;
    notifyListeners();
  }

  void setSharingActive(bool active) {
    _isSharingActive = active;
    notifyListeners();
  }

  void setRemindMe(bool active) {
    _isRemindMeActive = active;
    notifyListeners();
  }

  void toggleRemindMe() {
    _isRemindMeActive = !_isRemindMeActive;
    notifyListeners();
  }

  void updateActiveRoute(AiDiscoveredRoute? route) {
    _activeRoute = route;
    notifyListeners();
  }
}