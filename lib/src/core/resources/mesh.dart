import 'dart:typed_data';
import 'dart:ui';

class Mesh {
  Mesh(int vertexCount, int faceCount) {
    positions = Float32List(vertexCount * 2);
    positionsZ = Float32List(vertexCount);
    textureCoordinates = Float32List(vertexCount * 2);
    colors = Int32List(vertexCount);
    indices = Uint16List(faceCount * 3);
    this.vertexCount = 0;
    indexCount = 0;
  }

  late Float32List positions;
  late Float32List positionsZ;
  late Float32List textureCoordinates;
  late Int32List colors;
  late Uint16List indices;
  late int vertexCount;
  late int indexCount;
  Image? texture;
  double x = 0;
  double y = 0;
  double z = 0;
}
