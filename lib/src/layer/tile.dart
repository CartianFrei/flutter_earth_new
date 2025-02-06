import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' hide Image;
import 'package:flutter_earth/src/core/enums/tile_status_enum.dart';

class Tile {
  Tile(this.x, this.y, this.z,
      {this.image, this.future, required this.imageProvider});

  int x;
  int y;

  /// zoom level
  int z;
  TileStatus status = TileStatus.clear;
  Image? image;
  Future<Image>? future;
  ImageProvider imageProvider;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;

  void _tileOnLoad(
      ImageInfo imageInfo, bool synchronousCall, Completer<Image> completer) {
    completer.complete(imageInfo.image);
  }

  Future<void> loadImage() async {
    status = TileStatus.fetching;
    final c = Completer<Image>();
    final oldImageStream = _imageStream;
    _imageStream = imageProvider.resolve(const ImageConfiguration());
    if (_imageStream!.key != oldImageStream?.key) {
      if (_listener != null) oldImageStream?.removeListener(_listener!);

      _listener = ImageStreamListener((info, s) => _tileOnLoad(info, s, c),
          onError: (exception, stackTrace) {
        if (!c.isCompleted) c.completeError(exception, stackTrace);
      });
      _imageStream!.addListener(_listener!);
      try {
        image = await c.future;
        status = TileStatus.ready;
      } catch (e) {
        status = TileStatus.error;
      }
    }
  }
}
