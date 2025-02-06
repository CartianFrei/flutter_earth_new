import 'package:flutter/material.dart' hide Image;
import 'package:flutter_earth/flutter_earth.dart';

class SpherePainter extends CustomPainter {
  const SpherePainter(this.state, this.url);

  final FlutterEarthState state;
  final String url;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    state.drawTiles(canvas, size, url);
  }

  // We should repaint whenever the board changes, such as board.selected.
  @override
  bool shouldRepaint(SpherePainter oldDelegate) {
    return true;
  }
}
