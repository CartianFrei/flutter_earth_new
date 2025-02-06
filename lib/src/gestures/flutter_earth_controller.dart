import 'package:flutter_earth/flutter_earth.dart';
import 'package:vector_math/vector_math_64.dart';

class FlutterEarthController {
  FlutterEarthController(this._state);

  final FlutterEarthState _state;

  Quaternion get quaternion => _state.quaternion;

  EulerAngles get eulerAngles => _state.eulerAngles;

  LatLon get position => _state.position;

  double get zoom => _state.zoom;

  bool get isAnimating => _state.animController.isAnimating;

  void clearCache() => _state.clearCache();

  void animateCamera(
      {LatLon? newLatLon,
      double? riseZoom,
      double? fallZoom,
      double panSpeed = 10.0,
      double riseSpeed = 1.0,
      double fallSpeed = 1.0}) {
    _state.animateCamera(
        newLatLon: newLatLon,
        riseZoom: riseZoom,
        fallZoom: fallZoom,
        panSpeed: panSpeed,
        riseSpeed: riseSpeed,
        fallSpeed: fallSpeed);
  }
}
