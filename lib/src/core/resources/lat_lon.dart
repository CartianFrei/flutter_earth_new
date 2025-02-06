import 'package:vector_math/vector_math_64.dart';

class LatLon {
  LatLon(this.latitude, this.longitude);

  double latitude;
  double longitude;

  LatLon inRadians() => LatLon(radians(latitude), radians(longitude));

  LatLon inDegrees() => LatLon(degrees(latitude), degrees(longitude));

  @override
  String toString() =>
      'LatLon(${degrees(latitude).toStringAsFixed(2)}, ${degrees(longitude).toStringAsFixed(2)})';
}
