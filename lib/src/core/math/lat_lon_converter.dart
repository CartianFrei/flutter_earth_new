import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_earth/src/core/math/math_worths_sh.dart';
import 'package:flutter_earth/src/core/resources/lat_lon.dart';
import 'package:vector_math/vector_math_64.dart';

class LatLonConverter {
  /// Mercator projection
  static const double maxLatitude = 85.05112877980659 * math.pi / 180;

  static Offset latLonToPoint(double latitude, double longitude) {
    final x = 0.5 + longitude / (2.0 * math.pi);
    double y;
    if (latitude > maxLatitude || latitude < -maxLatitude) {
      y = 0.5 - latitude / math.pi;
    } else {
      final sinlat = math.sin(latitude);
      y = 0.5 - math.log((1 + sinlat) / (1 - sinlat)) / (4.0 * math.pi);
    }
    return Offset(x, y);
  }

  static LatLon pointToLatLon(double x, double y) {
    final longitude = (x - 0.5) * (2.0 * math.pi);
    final latitude =
        2.0 * math.atan(math.exp(math.pi - 2.0 * math.pi * y)) - math.pi / 2.0;
    return LatLon(latitude, longitude);
  }

  /// Cartesian coordinate conversions
  static Vector3 latLonToVector3(LatLon latLon) {
    final cosLat = math.cos(latLon.latitude);
    final x = cosLat * math.cos(latLon.longitude);
    final y = cosLat * math.sin(latLon.longitude);
    final z = math.sin(latLon.latitude);
    return Vector3(x, y, z);
  }

  static LatLon vector3ToLatLon(Vector3 v) {
    final lat = math.asin(v.z);
    var lon = math.atan2(v.y, v.x);
    return LatLon(lat, lon);
  }

  /// Quaternion conversions
  static LatLon quaternionToLatLon(Quaternion q) {
    final euler = MathWorthShit.quaternionToEulerAngles(q);
    return MathWorthShit.eulerAnglesToLatLon(euler);
  }

  static Quaternion latLonToQuaternion(LatLon latLon) {
    final euler = MathWorthShit.latLonToEulerAngles(latLon);
    return MathWorthShit.eulerAnglesToQuaternion(euler);
  }
}
