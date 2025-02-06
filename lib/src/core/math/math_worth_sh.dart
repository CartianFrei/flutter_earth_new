import 'dart:math' as math;

import 'package:flutter_earth/src/core/resources/euler_angles.dart';
import 'package:vector_math/vector_math_64.dart';

class MathWorthShit {
  /// Fixed Quaternion.setFromTwoVectors from 'vector_math_64/quaternion.dart'.
  static Quaternion quaternionFromTwoVectors(Vector3 a, Vector3 b) {
    final Vector3 v1 = a.normalized();
    final Vector3 v2 = b.normalized();

    final double c = math.max(-1, math.min(1, v1.dot(v2)));
    double angle = math.acos(c);
    Vector3 axis = v1.cross(v2);
    if (axis.length == 0) axis = Vector3(1.0, 0.0, 0.0);

    return Quaternion.axisAngle(axis, angle);
  }

  /// Fixed Quaternion.axis from 'vector_math_64/quaternion.dart'.
  static Vector3 quaternionAxis(Quaternion q) {
    final qStorage = q.storage;
    final double den = 1.0 - (qStorage[3] * qStorage[3]);
    if (den == 0) return Vector3(1.0, 0.0, 0.0);

    final double scale = 1.0 / math.sqrt(den);
    return Vector3(
        qStorage[0] * scale, qStorage[1] * scale, qStorage[2] * scale);
  }

  /// Euler Angles
  static EulerAngles quaternionToEulerAngles(Quaternion q) {
    final qStorage = q.storage;
    final x = qStorage[0];
    final y = qStorage[1];
    final z = qStorage[2];
    final w = qStorage[3];

    final roll = math.atan2(2 * (w * z + x * y), 1 - 2 * (z * z + x * x));
    final pitch = math.asin(math.max(-1, math.min(1, 2 * (w * x - y * z))));
    final yaw = math.atan2(2 * (w * y + z * x), 1 - 2 * (x * x + y * y));

    return EulerAngles(yaw, pitch, roll);
  }

  static Quaternion eulerAnglesToQuaternion(EulerAngles euler) {
    return Quaternion.euler(euler.yaw, euler.pitch, euler.roll);
  }
}
