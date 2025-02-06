import 'package:vector_math/vector_math_64.dart';

class EulerAngles {
  double yaw;
  double pitch;
  double roll;

  EulerAngles(this.yaw, this.pitch, this.roll);

  EulerAngles clone() => EulerAngles(yaw, pitch, roll);

  void scale(double arg) {
    yaw *= arg;
    pitch *= arg;
    roll *= arg;
  }

  EulerAngles inRadians() =>
      EulerAngles(radians(yaw), radians(pitch), radians(roll));

  EulerAngles inDegrees() =>
      EulerAngles(degrees(yaw), degrees(pitch), degrees(roll));

  @override
  String toString() =>
      'pitch:${pitch.toStringAsFixed(4)}, yaw:${yaw.toStringAsFixed(4)}, roll:${roll.toStringAsFixed(4)}';
}
