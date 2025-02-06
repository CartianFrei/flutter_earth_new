library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_earth/src/core/enums/tile_status_enum.dart';
import 'package:flutter_earth/src/core/math/lat_lon_converter.dart';
import 'package:flutter_earth/src/core/math/math_worth_sh.dart';
import 'package:flutter_earth/src/core/resources/euler_angles.dart';
import 'package:flutter_earth/src/core/resources/lat_lon.dart';
import 'package:flutter_earth/src/core/resources/mesh.dart';
import 'package:flutter_earth/src/core/resources/polygon.dart';
import 'package:flutter_earth/src/gestures/flutter_earth_controller.dart';
import 'package:flutter_earth/src/layer/sphere_painter.dart';
import 'package:flutter_earth/src/layer/tile.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

export 'package:flutter_earth/src/core/enums/tile_status_enum.dart';
export 'package:flutter_earth/src/core/math/lat_lon_converter.dart';
export 'package:flutter_earth/src/core/math/math_worth_sh.dart';
export 'package:flutter_earth/src/core/resources/euler_angles.dart';
export 'package:flutter_earth/src/core/resources/lat_lon.dart';
export 'package:flutter_earth/src/core/resources/mesh.dart';
export 'package:flutter_earth/src/core/resources/polygon.dart';
export 'package:flutter_earth/src/gestures/flutter_earth_controller.dart';
export 'package:flutter_earth/src/layer/sphere_painter.dart';
export 'package:flutter_earth/src/layer/tile.dart';

/// load an image from asset
Future<Image> loadImageFromAsset(String fileName) {
  final c = Completer<Image>();
  rootBundle.load(fileName).then((data) {
    instantiateImageCodec(data.buffer.asUint8List()).then((codec) {
      codec.getNextFrame().then((frameInfo) {
        c.complete(frameInfo.image);
      });
    });
  }).catchError((error) {
    c.completeError(error);
  });
  return c.future;
}

typedef TileCallback = void Function(Tile tile);
typedef MapCreatedCallback = void Function(FlutterEarthController controller);
typedef CameraPositionCallback = void Function(LatLon latLon, double zoom);

class FlutterEarth extends StatefulWidget {
  const FlutterEarth(
      {super.key,
      required this.layers,
      this.radius,
      this.maxVertexCount = 5000,
      this.showPole = true,
      this.onMapCreated,
      this.onCameraMove,
      this.onTileStart,
      this.onTileEnd,
      this.imageProvider});

  final List<String> layers;
  final double? radius;
  final int maxVertexCount;
  final bool? showPole;
  final TileCallback? onTileStart;
  final TileCallback? onTileEnd;
  final MapCreatedCallback? onMapCreated;
  final CameraPositionCallback? onCameraMove;
  final ImageProvider Function(String url)? imageProvider;

  @override
  FlutterEarthState createState() => FlutterEarthState();
}

class FlutterEarthState extends State<FlutterEarth>
    with TickerProviderStateMixin {
  late final FlutterEarthController _controller;
  double width = 0;
  double height = 0;
  double zoom = 0;
  double? _lastZoom = 0;
  Offset _lastFocalPoint = Offset(0, 0);
  Quaternion? _lastQuaternion;
  Vector3 _lastRotationAxis = Vector3(0, 0, 0);
  double _lastGestureScale = 1;
  double _lastGestureRotation = 0;
  int _lastGestureTime = 0;

  final double _radius = 256 / (2 * math.pi);

  double get radius => _radius * math.pow(2, zoom);

  int get zoomLevel => zoom.round().clamp(minZoom, maxZoom);

  LatLon get position => LatLonConverter.quaternionToLatLon(quaternion);

  EulerAngles get eulerAngles =>
      MathWorthShit.quaternionToEulerAngles(quaternion);

  Vector3 canvasPointToVector3(Offset point) {
    final x = point.dx - width / 2;
    final y = point.dy - height / 2;
    var z = radius * radius - x * x - y * y;
    if (z < 0) z = 0;
    z = -math.sqrt(z);
    return Vector3(x, y, z);
  }

  Quaternion quaternion = Quaternion.identity();
  late AnimationController animController;
  Animation<double>? panAnimation;
  Animation<double>? riseAnimation;
  Animation<double>? zoomAnimation;
  double _panCurveEnd = 0;

  final double tileWidth = 256;
  final double tileHeight = 256;
  final int minZoom = 2;
  final int maxZoom = 21;
  List<HashMap<int, Tile>> tiles = [];
  Image? northPoleImage;
  Image? southPoleImage;

  void clearCache() async {
    final int currentZoom = zoomLevel;
    for (int z = 4; z < tiles.length; z++) {
      if (z != currentZoom) {
        final values = tiles[z].values;
        for (Tile t in values) {
          t.status = TileStatus.clear;
          t.image = null;
          t.future = null;
        }
      }
    }
  }

  Future<Tile> loadTileImage(Tile tile) async {
    if (tile.status == TileStatus.error) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    tile.status = TileStatus.pending;
    if (widget.onTileStart != null) widget.onTileStart!(tile);
    if (tile.status == TileStatus.ready) return tile;
    await tile.loadImage();
    if (widget.onTileEnd != null) widget.onTileEnd!(tile);
    if (mounted) setState(() {});
    return tile;
  }

  Tile? getTile(int x, int y, int z, String url) {
    final key = (x << 32) + y;
    var tile = tiles[z][key];
    if (tile == null) {
      final tileUrl = url
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
      tile = Tile(x, y, z,
          imageProvider: widget.imageProvider != null
              ? widget.imageProvider!(tileUrl)
              : NetworkImage(tileUrl));
      tiles[z][key] = tile;
    }
    if (tile.status == TileStatus.clear || tile.status == TileStatus.error) {
      loadTileImage(tile);
    }

    if (tile.status != TileStatus.ready) {
      for (int i = z; i >= 0; i--) {
        final x1 = (x * math.pow(2, i - z)).toInt();
        final y1 = (y * math.pow(2, i - z)).toInt();
        final key1 = (x1 << 32) + y1;
        final tile1 = tiles[i][key1];
        if (tile1?.status == TileStatus.ready) return tile1;
      }
    }
    return tile;
  }

  List<Offset> clipTiles(Rect clipRect, double radius) {
    final list = <Offset>[];
    final scale = math.pow(2.0, zoomLevel).toDouble();
    final observed = HashMap<int, int>();
    final lastKeys = List.filled(clipRect.width ~/ 10 + 1, 0);
    for (var y = clipRect.top; y < clipRect.bottom; y += 10.0) {
      var i = 0;
      for (var x = clipRect.left; x < clipRect.right; x += 10.0) {
        final v = canvasPointToVector3(Offset(x, y));
        final latLon = LatLonConverter.canvasVector3ToLatLon(v, quaternion);
        final point =
            LatLonConverter.latLonToPoint(latLon.latitude, latLon.longitude) *
                scale;
        if (point.dx >= scale || point.dy >= scale) continue;
        final key = (point.dx.toInt() << 32) + point.dy.toInt();
        if ((i == 0 || lastKeys[i - 1] != key) &&
            (lastKeys[i] != key) &&
            !observed.containsKey(key)) {
          observed[key] = 0;
          list.add(
              Offset(point.dx.truncateToDouble(), point.dy.truncateToDouble()));
        }
        lastKeys[i] = key;
        i++;
      }
    }
    return list;
  }

  void initMeshTexture(Mesh mesh, String url) {
    final tile =
        getTile(mesh.x ~/ tileWidth, mesh.y ~/ tileHeight, zoomLevel, url);
    if (tile?.status == TileStatus.ready) {
      //Is zoomed tile?
      if (tile?.z != zoomLevel && tile != null) {
        final Float32List textureCoordinates = mesh.textureCoordinates;
        final int textureCoordinatesCount = textureCoordinates.length;
        final double scale = math.pow(2, tile.z - zoomLevel).toDouble();
        for (int i = 0; i < textureCoordinatesCount; i += 2) {
          textureCoordinates[i] =
              (mesh.x + textureCoordinates[i]) * scale - tile.x * tileWidth;
          textureCoordinates[i + 1] =
              (mesh.y + textureCoordinates[i + 1]) * scale -
                  tile.y * tileHeight;
        }
      }
      mesh.texture = tile?.image;
    }
  }

  Mesh initMeshFaces(Mesh mesh, int subdivisionsX, int subdivisionsY) {
    final int faceCount = subdivisionsX * subdivisionsY * 2;
    final List<Polygon?> facesList = <Polygon?>[]..length = (faceCount);
    final Float32List positionsZ = mesh.positionsZ;
    int indexOffset = mesh.indexCount;
    double z = 0.0;
    for (var j = 0; j < subdivisionsY; j++) {
      int k1 = j * (subdivisionsX + 1);
      int k2 = k1 + subdivisionsX + 1;
      for (var i = 0; i < subdivisionsX; i++) {
        int k3 = k1 + 1;
        int k4 = k2 + 1;
        double sumOfZ = positionsZ[k1] + positionsZ[k2] + positionsZ[k3];
        facesList[indexOffset] = Polygon(k1, k2, k3, sumOfZ);
        z += sumOfZ;
        sumOfZ = positionsZ[k3] + positionsZ[k2] + positionsZ[k4];
        facesList[indexOffset + 1] = Polygon(k3, k2, k4, sumOfZ);
        z += sumOfZ;
        indexOffset += 2;
        k1++;
        k2++;
      }
    }
    mesh.indexCount += faceCount;

    var faces = facesList.whereType<Polygon>().toList();

    faces.sort((Polygon a, Polygon b) {
      // return b.sumOfZ.compareTo(a.sumOfZ);
      final double az = a.sumOfZ;
      final double bz = b.sumOfZ;
      if (bz > az) return 1;
      if (bz < az) return -1;
      return 0;
    });

    // convert Polygon list to Uint16List
    final int indexCount = faces.length;
    final Uint16List indices = mesh.indices;
    for (int i = 0; i < indexCount; i++) {
      final int index0 = i * 3;
      final int index1 = index0 + 1;
      final int index2 = index0 + 2;
      final Polygon polygon = faces[i];
      indices[index0] = polygon.vertex0;
      indices[index1] = polygon.vertex1;
      indices[index2] = polygon.vertex2;
    }

    mesh.z = z;
    return mesh;
  }

  Mesh buildPoleMesh(double startLatitude, double endLatitude, int subdivisions,
      Image? image) {
    //Rotate the tile from initial LatLon(-90, -90) to LatLon(0, 0) first.
    final q = Quaternion(-0.5, -0.5, 0.5, 0.5) * quaternion;
    //Use matrix rotation is more efficient.
    final matrix = q.asRotationMatrix()..invert();

    final int imageWidth = image?.width ?? 1;
    final int imageHeight = image?.height ?? 1;
    final int subdivisionsX = subdivisions * (imageWidth ~/ imageHeight);
    final int vertexCount = (subdivisions + 1) * (subdivisionsX + 1);
    final int faceCount = subdivisions * subdivisionsX * 2;
    final Mesh mesh = Mesh(vertexCount, faceCount);
    final Float32List textureCoordinates = mesh.textureCoordinates;
    final Float32List positions = mesh.positions;
    final Float32List positionsZ = mesh.positionsZ;
    int vertexIndex = 0;
    int vertexZIndex = 0;
    int textureCoordinatesIndex = 0;

    final double stepOfLat = (endLatitude - startLatitude) / subdivisions;
    final double stepOfLon = 2 * math.pi / subdivisionsX;
    for (int j = 0; j <= subdivisions; j++) {
      final double y0 = startLatitude + stepOfLat * j;
      for (int i = 0; i <= subdivisionsX; i++) {
        final double x0 = -math.pi + i * stepOfLon;
        final v = LatLonConverter.latLonToVector3(LatLon(y0, x0))
          ..scale(radius);
        v.applyMatrix3(matrix);
        // q.rotate(v);
        final Float64List storage4 = v.storage;
        positions[vertexIndex] = storage4[0]; //v.x;
        positions[vertexIndex + 1] = storage4[1]; //v.y;
        positionsZ[vertexZIndex] = storage4[2]; //v.z;
        vertexIndex += 2;
        vertexZIndex++;

        textureCoordinates[textureCoordinatesIndex] =
            imageWidth * i / subdivisionsX;
        textureCoordinates[textureCoordinatesIndex + 1] =
            imageHeight * j / subdivisions;
        textureCoordinatesIndex += 2;
      }
    }
    mesh.vertexCount += vertexCount;
    mesh.x = -1;
    mesh.y = -1;
    mesh.texture = image;
    return initMeshFaces(mesh, subdivisionsX, subdivisions);
  }

  Mesh buildTileMesh(
      double offsetX,
      double offsetY,
      double tileWidth,
      double tileHeight,
      int subdivisions,
      double mapWidth,
      double mapHeight,
      double radius) {
    //Rotate the tile from initial LatLon(-90, -90) to LatLon(0, 0) first.
    final q = Quaternion(-0.5, -0.5, 0.5, 0.5) * quaternion;
    //Use matrix rotation is more efficient.
    final matrix = q.asRotationMatrix()..invert();

    final int vertexCount = (subdivisions + 1) * (subdivisions + 1);
    final int faceCount = subdivisions * subdivisions * 2;
    final Mesh mesh = Mesh(vertexCount, faceCount);
    final Float32List textureCoordinates = mesh.textureCoordinates;
    final Float32List positions = mesh.positions;
    final Float32List positionsZ = mesh.positionsZ;
    int vertexIndex = 0;
    int vertexZIndex = 0;
    int textureCoordinatesIndex = 0;

    for (var j = 0; j <= subdivisions; j++) {
      final y0 = (offsetY + tileHeight * j / subdivisions) / mapHeight;
      for (var i = 0; i <= subdivisions; i++) {
        final x0 = (offsetX + tileWidth * i / subdivisions) / mapWidth;
        final latLon = LatLonConverter.pointToLatLon(x0, y0);
        final v = LatLonConverter.latLonToVector3(latLon)..scale(radius);
        v.applyMatrix3(matrix);
        // q.rotate(v);
        final Float64List storage4 = v.storage;
        positions[vertexIndex] = storage4[0]; //v.x;
        positions[vertexIndex + 1] = storage4[1]; //v.y;
        positionsZ[vertexZIndex] = storage4[2]; //v.z;
        vertexIndex += 2;
        vertexZIndex++;

        textureCoordinates[textureCoordinatesIndex] =
            tileWidth * i / subdivisions;
        textureCoordinates[textureCoordinatesIndex + 1] =
            tileHeight * j / subdivisions;
        textureCoordinatesIndex += 2;
      }
    }
    mesh.vertexCount += vertexCount;
    mesh.x = offsetX;
    mesh.y = offsetY;
    return initMeshFaces(mesh, subdivisions, subdivisions);
  }

  void drawTiles(Canvas canvas, Size size, String url) {
    final tiles = clipTiles(Rect.fromLTWH(0, 0, width, height), radius);
    final meshList = <Mesh>[];
    final maxWidth = tileWidth * (1 << zoomLevel);
    final maxHeight = tileHeight * (1 << zoomLevel);

    final tileCount = math.pow(math.pow(2, zoomLevel), 2);
    final int subdivisions =
        math.max(2, math.sqrt(widget.maxVertexCount / tileCount).toInt());
    for (var t in tiles) {
      final mesh = buildTileMesh(
        t.dx * tileWidth,
        t.dy * tileHeight,
        tileWidth,
        tileHeight,
        subdivisions,
        maxWidth,
        maxHeight,
        radius,
      );
      initMeshTexture(mesh, url);
      meshList.add(mesh);
    }
    if (widget.showPole ?? false) {
      meshList.add(buildPoleMesh(math.pi / 2, radians(84), 5, northPoleImage));
      meshList
          .add(buildPoleMesh(-radians(84), -math.pi / 2, 5, southPoleImage));
    }

    meshList.sort((Mesh a, Mesh b) {
      return b.z.compareTo(a.z);
    });

    for (var mesh in meshList) {
      final vertices = Vertices.raw(
        VertexMode.triangles,
        mesh.positions,
        textureCoordinates: mesh.textureCoordinates,
        indices: mesh.indices,
      );

      final paint = Paint();
      if (mesh.texture != null) {
        Float64List matrix4 = Matrix4.identity().storage;
        final shader = ImageShader(
            mesh.texture!, TileMode.mirror, TileMode.mirror, matrix4);
        paint.shader = shader;
      }
      canvas.drawVertices(vertices, BlendMode.src, paint);
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    animController.stop();
    _lastZoom = null;
    _lastFocalPoint = details.localFocalPoint;
    _lastQuaternion = quaternion;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale != 1.0 || details.rotation != 0.0) {
      _lastGestureScale = details.scale;
      _lastGestureRotation = details.rotation;
      _lastGestureTime = DateTime.now().millisecondsSinceEpoch;
    }

    if (_lastZoom == null) {
      // fixed scaling error caused by ScaleUpdate delay
      _lastZoom = zoom - math.log(details.scale) / math.ln2;
    } else {
      zoom = _lastZoom! + math.log(details.scale) / math.ln2;
    }

    final Vector3 oldCoordinates = canvasPointToVector3(_lastFocalPoint);
    final Vector3 newCoordinates =
        canvasPointToVector3(details.localFocalPoint);
    //var q = Quaternion.fromTwoVectors(newCoordinates, oldCoordinates); // It seems some issues with this 'fromTwoVectors' function.
    Quaternion q =
        MathWorthShit.quaternionFromTwoVectors(newCoordinates, oldCoordinates);
    // final axis = q.axis; // It seems some issues with this 'axis' function.
    final axis = MathWorthShit.quaternionAxis(q);
    if (axis.x != 0 && axis.y != 0 && axis.z != 0) _lastRotationAxis = axis;

    q *= Quaternion.axisAngle(Vector3(0, 0, 1.0), -details.rotation);
    if (_lastQuaternion != null) {
      quaternion =
          _lastQuaternion! * q; //quaternion A * B is not equal to B * A
    }

    if (widget.onCameraMove != null) {
      widget.onCameraMove!(position, zoom);
    }
    if (mounted) setState(() {});
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastQuaternion = quaternion;
    const double duration = 1000;
    const double maxDistance = 4000;
    final double distance =
        math.min(maxDistance, details.velocity.pixelsPerSecond.distance) /
            maxDistance;
    if (distance == 0) return;

    if (DateTime.now().millisecondsSinceEpoch - _lastGestureTime < 300) {
      if (_lastGestureScale != 1.0 &&
          (_lastGestureScale - 1.0).abs() > _lastGestureRotation.abs()) {
        double radians = 3.0 * distance;
        if (_lastGestureScale < 1.0) radians = -radians;
        animController.duration = Duration(milliseconds: duration.toInt());
        zoomAnimation = Tween<double>(begin: zoom, end: zoom + radians).animate(
            CurveTween(curve: Curves.decelerate).animate(animController));
        panAnimation = null;
        riseAnimation = null;
        animController.reset();
        animController.forward();
        return;
      } else if (_lastGestureRotation != 0) {
        double radians = 2.0 * math.pi * distance;
        if (_lastGestureRotation > 0) radians = -radians;
        _lastRotationAxis = Vector3(0, 0, 1.0);
        animController.duration = Duration(milliseconds: duration.toInt());
        panAnimation = Tween<double>(begin: 0, end: radians).animate(
            CurveTween(curve: Curves.decelerate).animate(animController));
        riseAnimation = null;
        zoomAnimation = null;
        animController.reset();
        animController.forward();
        return;
      }
    }

    double radians = 1000 * distance / radius;
    final Offset center = Offset(width / 2, height / 2);
    final Vector3 oldCoordinates = canvasPointToVector3(center);
    final Vector3 newCoordinates = canvasPointToVector3(
        center + details.velocity.pixelsPerSecond / distance);
    Quaternion q =
        MathWorthShit.quaternionFromTwoVectors(newCoordinates, oldCoordinates);
    final Vector3 axis = MathWorthShit.quaternionAxis(q);
    if (axis.x != 0 && axis.y != 0 && axis.z != 0) _lastRotationAxis = axis;

    animController.duration = Duration(milliseconds: duration.toInt());
    panAnimation = Tween<double>(begin: 0, end: radians)
        .animate(CurveTween(curve: Curves.decelerate).animate(animController));
    riseAnimation = null;
    zoomAnimation = null;
    animController.reset();
    animController.forward();
  }

  void _handleDoubleTap() {
    _lastZoom = zoom;
    animController.duration = const Duration(milliseconds: 600);
    zoomAnimation = Tween<double>(begin: zoom, end: zoom + 1.0)
        .animate(CurveTween(curve: Curves.decelerate).animate(animController));
    panAnimation = null;
    riseAnimation = null;
    animController.reset();
    animController.forward();
  }

  void animateCamera(
      {LatLon? newLatLon,
      double? riseZoom,
      double? fallZoom,
      double panSpeed = 1000.0,
      double riseSpeed = 1.0,
      double fallSpeed = 1.0}) {
    double panTime = 0;
    double riseTime = 0;
    double fallTime = 0;
    if (riseZoom != null) {
      riseTime =
          Duration.millisecondsPerSecond * (riseZoom - zoom).abs() / riseSpeed;
    }
    riseZoom ??= zoom;
    if (fallZoom != null) {
      fallTime = Duration.millisecondsPerSecond *
          (fallZoom - riseZoom).abs() /
          fallSpeed;
    }
    fallZoom ??= riseZoom;

    double panRadians = 0;
    if (newLatLon != null) {
      final oldEuler = MathWorthShit.quaternionToEulerAngles(quaternion);
      final newEuler = LatLonConverter.latLonToEulerAngles(newLatLon);
      //Prevent the rotation over 180 degrees.
      if ((oldEuler.yaw - newEuler.yaw).abs() > math.pi) {
        newEuler.yaw -= math.pi * 2.0;
      }
      // q2 = q0 * q1 then q1 = q0.inverted * q2, and q0 = q2 * q1.inverted
      final q0 = MathWorthShit.eulerAnglesToQuaternion(oldEuler);
      final q2 = MathWorthShit.eulerAnglesToQuaternion(newEuler);
      final q1 = q0.inverted() * q2;
      _lastRotationAxis = MathWorthShit.quaternionAxis(q1); //q1.axis;
      _lastQuaternion = q0;
      panRadians = q1.radians;
      panTime = Duration.millisecondsPerSecond *
          (panRadians * _radius * math.pow(2, riseZoom)).abs() /
          panSpeed;
    }

    int duration = (riseTime + panTime + fallTime).ceil();
    animController.duration = Duration(milliseconds: duration);
    final double riseCurveEnd = riseTime / duration;
    riseAnimation = Tween<double>(begin: zoom, end: riseZoom).animate(
      CurveTween(curve: Interval(0, riseCurveEnd, curve: Curves.ease))
          .animate(animController),
    );
    final double panCurveEnd = riseCurveEnd + panTime / duration;
    _panCurveEnd = panCurveEnd;
    panAnimation = Tween<double>(begin: 0, end: panRadians).animate(
      CurveTween(curve: Interval(riseCurveEnd, panCurveEnd, curve: Curves.ease))
          .animate(animController),
    );
    const double fallCurveEnd = 1.0;
    zoomAnimation = Tween<double>(begin: riseZoom, end: fallZoom).animate(
      CurveTween(curve: Interval(panCurveEnd, fallCurveEnd, curve: Curves.ease))
          .animate(animController),
    );
    animController.reset();
    animController.forward();
  }

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        1024 * 1024 * 1024 * 1024;
    var tilesHash = <HashMap<int, Tile>?>[]..length = (maxZoom + 1);
    for (var i = 0; i <= maxZoom; i++) {
      tilesHash[i] = HashMap<int, Tile>();
    }
    tiles = tilesHash.whereType<HashMap<int, Tile>>().toList();
    if (widget.radius != null) {
      zoom = math.log(widget.radius! / _radius) / math.ln2;
    }
    _lastRotationAxis = Vector3(0, 0, 1.0);

    animController = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {
            if (!animController.isCompleted) {
              if (panAnimation != null && _lastQuaternion != null) {
                final q = Quaternion.axisAngle(
                    _lastRotationAxis, panAnimation!.value);
                quaternion = _lastQuaternion! * q;
              }
              if (riseAnimation != null) {
                if (animController.value < _panCurveEnd) {
                  zoom = riseAnimation!.value;
                }
              }
              if (zoomAnimation != null) {
                if (animController.value >= _panCurveEnd) {
                  zoom = zoomAnimation!.value;
                }
              }
              if (widget.onCameraMove != null) {
                widget.onCameraMove!(position, zoom);
              }
            } else {
              _panCurveEnd = 0;
            }
          });
        }
      });

    _controller = FlutterEarthController(this);
    if (widget.onMapCreated != null) {
      widget.onMapCreated!(_controller);
    }

    loadImageFromAsset(
            'packages/flutter_earth/assets/google_map_north_pole.png')
        .then((Image value) => northPoleImage = value);
    loadImageFromAsset(
            'packages/flutter_earth/assets/google_map_south_pole.png')
        .then((Image value) => southPoleImage = value);
  }

  @override
  void dispose() {
    animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        width = constraints.maxWidth;
        height = constraints.maxHeight;
        return GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: _handleScaleEnd,
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            children: List<Widget>.generate(
              widget.layers.length,
              (int index) => CustomPaint(
                painter: SpherePainter(this, widget.layers[index]),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            ),
          ),
        );
      },
    );
  }
}
