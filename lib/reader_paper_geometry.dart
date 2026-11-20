import 'dart:typed_data';
import 'dart:ui';

/// Flat stand-in for the curled paper mesh. The page image still covers the
/// leaf, without the private curl solver.
class ReaderPaperMesh {
  const ReaderPaperMesh({
    required this.positions,
    required this.indices,
    required this.normals,
    required this.uv,
    required this.outline,
  });

  final Float32List positions;
  final Uint16List indices;
  final List<double> normals;
  final Float32List uv;
  final Path outline;
}

class ReaderPaperGeometry {
  ReaderPaperGeometry({
    required this.size,
    required this.gap,
    required this.progress,
    required this.touchY,
  }) : lift = 0,
       front = _page(size),
       frontInk = _page(size),
       back = _empty(),
       backInk = _empty();

  final Size size;
  final double gap;
  final double progress;
  final double touchY;
  final double lift;
  final ReaderPaperMesh front;
  final ReaderPaperMesh frontInk;
  final ReaderPaperMesh back;
  final ReaderPaperMesh backInk;
  Path get sheet => front.outline;
}

ReaderPaperMesh _page(Size size) {
  final positions = Float32List.fromList([
    0,
    0,
    size.width,
    0,
    size.width,
    size.height,
    0,
    size.height,
  ]);
  return ReaderPaperMesh(
    positions: positions,
    indices: Uint16List.fromList([0, 1, 2, 0, 2, 3]),
    normals: const [1, 1, 1, 1],
    uv: Float32List.fromList(positions),
    outline: Path()..addRect(Offset.zero & size),
  );
}

ReaderPaperMesh _empty() => ReaderPaperMesh(
  positions: Float32List.fromList([0, 0, 0, 0, 0, 0]),
  indices: Uint16List.fromList([0, 1, 2]),
  normals: const [1, 1, 1],
  uv: Float32List.fromList([0, 0, 0, 0, 0, 0]),
  outline: Path(),
);
