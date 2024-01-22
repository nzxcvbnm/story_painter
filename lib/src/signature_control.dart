import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../story_painter.dart';
import 'utils.dart';

Map<double, double?> maxWCache = {};

class OffsetPoint extends Offset {
  final int? timestamp;

  const OffsetPoint({
    required double dx,
    required double dy,
    this.timestamp,
  }) : super(dx, dy);

  factory OffsetPoint.from(Offset offset) => OffsetPoint(
        dx: offset.dx,
        dy: offset.dy,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

  double velocityFrom(OffsetPoint other) => timestamp != other.timestamp
      ? this.distanceTo(other) / (timestamp! - other.timestamp!)
      : 0.0;

  @override
  OffsetPoint translate(double translateX, double translateY) {
    return OffsetPoint(
      dx: dx + translateX,
      dy: dy + translateY,
      timestamp: timestamp,
    );
  }

  @override
  OffsetPoint scale(double scaleX, double scaleY) {
    return OffsetPoint(
      dx: dx * scaleX,
      dy: dy * scaleY,
      timestamp: timestamp,
    );
  }

  @override
  bool operator ==(other) {
    return other is OffsetPoint &&
        other.dx == dx &&
        other.dy == dy &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => hashValues(super.hashCode, timestamp);
}

class CubicLine extends Offset {
  final OffsetPoint start;
  final Offset cpStart;
  final Offset cpEnd;
  final OffsetPoint end;

  double? _velocity;
  double? _distance;

  Offset? _upStartVector;

  Offset get upStartVector =>
      _upStartVector ??
      (_upStartVector = start.directionTo(point(0.001)).rotate(-math.pi * 0.5));

  Offset? _upEndVector;

  Offset get upEndVector =>
      _upEndVector ??
      (_upEndVector = end.directionTo(point(0.999)).rotate(math.pi * 0.5));

  Offset get _downStartVector => upStartVector.rotate(math.pi);

  Offset get _downEndVector => upEndVector.rotate(math.pi);

  double startSize;
  double endSize;

  bool get isDot => _velocity == 0.0;

  CubicLine({
    required this.start,
    required this.cpStart,
    required this.cpEnd,
    required this.end,
    Offset? upStartVector,
    Offset? upEndVector,
    this.startSize = 0.0,
    this.endSize = 0.0,
  }) : super(start.dx, start.dy) {
    _upStartVector = upStartVector;
    _upEndVector = upEndVector;
    _velocity = end.velocityFrom(start);
    _distance = start.distanceTo(end);
  }

  @override
  CubicLine scale(double scaleX, double scaleY) => CubicLine(
        start: start.scale(scaleX, scaleY),
        cpStart: cpStart.scale(scaleX, scaleY),
        cpEnd: cpEnd.scale(scaleX, scaleY),
        end: end.scale(scaleX, scaleY),
        upStartVector: _upStartVector,
        upEndVector: _upEndVector,
        startSize: startSize,
        endSize: endSize,
      );

  @override
  CubicLine translate(double translateX, double translateY) => CubicLine(
        start: start.translate(translateX, translateY),
        cpStart: cpStart.translate(translateX, translateY),
        cpEnd: cpEnd.translate(translateX, translateY),
        end: end.translate(translateX, translateY),
        upStartVector: _upStartVector,
        upEndVector: _upEndVector,
        startSize: startSize,
        endSize: endSize,
      );

  /// 0 - fastest, raw accuracy
  /// 1 - slowest, most accurate
  double? length({double accuracy = 0.1}) {
    final steps = (accuracy * 100).toInt();

    if (steps <= 1) {
      return _distance;
    }

    double length = 0.0;

    Offset prevPoint = start;
    for (int i = 1; i < steps; i++) {
      final t = i / steps;

      final next = point(t);

      length += prevPoint.distanceTo(next);
      prevPoint = next;
    }

    return length;
  }

  Offset point(double t) {
    final rt = 1.0 - t;
    return (start * rt * rt * rt) +
        (cpStart * 3.0 * rt * rt * t) +
        (cpEnd * 3.0 * rt * t * t) +
        (end * t * t * t);
  }

  double velocity({double accuracy = 0.0}) => start.timestamp != end.timestamp
      ? length(accuracy: accuracy)! / (end.timestamp! - start.timestamp!)
      : 0.0;

  double combineVelocity(double inVelocity,
      {double velocityRatio = 0.65, double maxFallOff = 1.0}) {
    final value =
        (_velocity! * velocityRatio) + (inVelocity * (1.0 - velocityRatio));

    maxFallOff *= _distance! / 10.0;

    final dif = value - inVelocity;
    if (dif.abs() > maxFallOff) {
      if (dif > 0.0) {
        return inVelocity + maxFallOff;
      } else {
        return inVelocity - maxFallOff;
      }
    }

    return value;
  }

  Path toPath() => Path()
    ..moveTo(dx, dy)
    ..cubicTo(cpStart.dx, cpStart.dy, cpEnd.dx, cpEnd.dy, end.dx, end.dy);

  List<CubicArc> toArc(double size, double deltaSize,
      {double precision = 0.5}) {
    final List<CubicArc> list = <CubicArc>[];

    final num steps = (_distance! * precision).floor().clamp(1, 30);

    Offset start = this.start;
    for (int i = 0; i < steps; i++) {
      final t = (i + 1) / steps;
      final loc = point(t);
      final width = size + deltaSize * t;

      list.add(CubicArc(
        start: start,
        location: loc,
        size: width,
      ));

      start = loc;
    }

    return list;
  }

  Path toShape(double size, double maxSize) {
    final startArm = (size + (maxSize - size) * startSize) * 0.5;
    final endArm = (size + (maxSize - size) * endSize) * 0.5;

    final sDirUp = upStartVector;
    final eDirUp = upEndVector;

    final d1 = sDirUp * startArm;
    final d2 = eDirUp * endArm;
    final d3 = eDirUp.rotate(math.pi) * endArm;
    final d4 = sDirUp.rotate(math.pi) * startArm;

    return Path()
      ..start(start + d1)
      ..cubic(cpStart + d1, cpEnd + d2, end + d2)
      ..line(end + d3)
      ..cubic(cpEnd + d3, cpStart + d4, start + d4)
      ..close();
  }

  Offset cpsUp(double size, double maxSize) =>
      upStartVector * startRadius(size, maxSize);

  Offset cpeUp(double size, double maxSize) =>
      upEndVector * endRadius(size, maxSize);

  Offset cpsDown(double size, double maxSize) =>
      _downStartVector * startRadius(size, maxSize);

  Offset cpeDown(double size, double maxSize) =>
      _downEndVector * endRadius(size, maxSize);

  double startRadius(double size, double maxSize) =>
      _lerpRadius(size, maxSize, startSize);

  double endRadius(double size, double maxSize) =>
      _lerpRadius(size, maxSize, endSize);

  double _lerpRadius(double size, double maxSize, double t) =>
      (size + (maxSize - size) * t) * 0.5;

  static Offset softCP(OffsetPoint current,
      {OffsetPoint? previous,
      OffsetPoint? next,
      bool reverse = false,
      double smoothing = 0.65}) {
    assert(smoothing >= 0.0 && smoothing <= 1.0);

    previous ??= current;
    next ??= current;

    final sharpness = 1.0 - smoothing;

    final dist1 = previous.distanceTo(current);
    final dist2 = current.distanceTo(next);
    final dist = dist1 + dist2;
    final dir1 = current.directionTo(next);
    final dir2 = current.directionTo(previous);
    final dir3 =
        reverse ? next.directionTo(previous) : previous.directionTo(next);

    final num velocity =
        (dist * 0.3 / (next.timestamp! - previous.timestamp!)).clamp(0.5, 3.0);
    final num ratio = (dist * velocity * smoothing)
        .clamp(0.0, (reverse ? dist2 : dist1) * 0.5);

    final dir = ((reverse ? dir2 : dir1) * sharpness) +
        (dir3 * smoothing) * (ratio as double);
    final x = current.dx + dir.dx;
    final y = current.dy + dir.dy;

    return Offset(x, y);
  }
}

class CubicArc extends Offset {
  static const rotation = math.pi * 2.0;

  final Offset location;
  final double size;

  Path get path => Path()
    ..moveTo(dx, dy)
    ..arcToPoint(location, rotation: rotation);

  Rect get rect => Rect.fromPoints(this, location);

  CubicArc({
    required Offset start,
    required this.location,
    this.size = 1.0,
  }) : super(start.dx, start.dy);

  @override
  Offset translate(double translateX, double translateY) => CubicArc(
        start: Offset(dx + translateX, dy + translateY),
        location: location.translate(translateX, translateY),
        size: size,
      );

  @override
  Offset scale(double scaleX, double scaleY) => CubicArc(
        start: Offset(dx * scaleX, dy * scaleY),
        location: location.scale(scaleX, scaleY),
        size: size,
      );
}

class CubicPath {
  SinglePathState? pathState;
  final int id;
  final _points = <OffsetPoint>[];
  final _lines = <CubicLine>[];
  final _arcs = <CubicArc>[];

  List<OffsetPoint> get points => _points;

  List<CubicLine> get lines => _lines;

  List<CubicArc> get arcs => _arcs;

  Offset? get _origin => _points.isNotEmpty ? _points[0] : null;

  OffsetPoint? get _lastPoint =>
      _points.isNotEmpty ? _points[_points.length - 1] : null;

  bool get isFilled => _lines.isNotEmpty;

  Path? _temp;

  Path? get tempPath => _temp;

  double maxVelocity = 1.0;

  double? _currentVelocity = 0.0;
  double _currentSize = 0.0;

  final threshold;
  final smoothRatio;
  final color;
  final width;
  PainterDrawType type;

  bool get isDot => lines.length == 1 && lines[0].isDot;

  CubicPath(
    this.id,
    this.width, {
    this.threshold = 3.0,
    this.smoothRatio = 0.65,
    this.color = Colors.black,
    this.type = PainterDrawType.shape,
  });

  void _addLine(CubicLine line) {
    if (_lines.length == 0) {
      if (_currentVelocity == 0.0) {
        _currentVelocity = line._velocity;
      }

      if (_currentSize == 0.0) {
        _currentSize = _lineSize(_currentVelocity!, maxVelocity);
      }
    } else {
      line._upStartVector = _lines.last.upEndVector;
    }

    _lines.add(line);

    final combinedVelocity =
        line.combineVelocity(_currentVelocity!, maxFallOff: 0.125);
    final double endSize = _lineSize(combinedVelocity, maxVelocity);

    if (combinedVelocity > maxVelocity) {
      maxVelocity = combinedVelocity;
    }

    line.startSize = _currentSize;
    line.endSize = endSize;

    _arcs.addAll(line.toArc(_currentSize, endSize - _currentSize));

    _currentSize = endSize;
    _currentVelocity = combinedVelocity;
  }

  void _addDot(CubicLine line) {
    final size = 0.25 + _lineSize(_currentVelocity!, maxVelocity) * 0.5;
    line.startSize = size;

    _lines.add(line);
    _arcs.addAll(line.toArc(size, 0.0));
  }

  double _lineSize(double velocity, double max) {
    velocity /= max;

    return 1.0 - velocity.clamp(0.0, 1.0);
  }

  void begin(Offset point, {double? velocity = 0.0}) {
    _points.add(OffsetPoint.from(point));
    _currentVelocity = velocity;

    _temp = _dot(point);
  }

  void add(Offset point) {
    assert(_origin != null);

    final nextPoint = point is OffsetPoint ? point : OffsetPoint.from(point);

    if (_lastPoint!.distanceTo(nextPoint) < threshold) {
      _temp = _line(_points.last, nextPoint);

      return;
    }

    _points.add(nextPoint);
    int count = _points.length;

    if (count < 3) {
      if (count > 1) {
        _temp = _line(_points[0], _points[1]);
      }

      return;
    }

    int i = count - 3;

    final prev = i > 0 ? _points[i - 1] : _points[i];
    final start = _points[i];
    final end = _points[i + 1];
    final next = _points[i + 2];

    final cpStart = CubicLine.softCP(
      start,
      previous: prev,
      next: end,
      smoothing: smoothRatio,
    );

    final cpEnd = CubicLine.softCP(
      end,
      previous: start,
      next: next,
      smoothing: smoothRatio,
      reverse: true,
    );

    final line = CubicLine(
      start: start,
      cpStart: cpStart,
      cpEnd: cpEnd,
      end: end,
    );

    _addLine(line);

    _temp = _line(end, next);
  }

  bool end({Offset? point}) {
    if (point != null) {
      add(point);
    }

    _temp = null;

    if (_points.isEmpty) {
      return false;
    }

    if (_points.length < 3) {
      if (_points.length == 1) {
        _addDot(CubicLine(
          start: _points[0],
          cpStart: _points[0],
          cpEnd: _points[0],
          end: _points[0],
        ));
      } else {
        _addLine(CubicLine(
          start: _points[0],
          cpStart: _points[0],
          cpEnd: _points[1],
          end: _points[1],
        ));
      }
    } else {
      final i = _points.length - 3;

      final end = CubicLine(
        start: _points[i + 1],
        cpStart: _points[i + 1],
        cpEnd: _points[i + 2],
        end: _points[i + 2],
      );

      _addLine(end);
    }

    return true;
  }

  Path _dot(Offset point) => Path()
    ..moveTo(point.dx, point.dy)
    ..cubicTo(
      point.dx,
      point.dy,
      point.dx,
      point.dy,
      point.dx,
      point.dy,
    );

  Path _line(Offset start, Offset end, [Offset? startCp, Offset? endCp]) =>
      Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          startCp != null ? startCp.dx : (start.dx + end.dx) * 0.5,
          startCp != null ? startCp.dy : (start.dy + end.dy) * 0.5,
          endCp != null ? endCp.dx : (start.dx + end.dx) * 0.5,
          endCp != null ? endCp.dy : (start.dy + end.dy) * 0.5,
          end.dx,
          end.dy,
        );

  void setScale(double ratio) {
    if (!isFilled) {
      return;
    }

    final arcData = PathUtil.scale(_arcs, ratio);
    _arcs.clear();
    _arcs.addAll(arcData.cast<CubicArc>());

    final lineData = PathUtil.scale(_lines, ratio);
    _lines.clear();
    _lines.addAll(lineData.cast<CubicLine>());
  }

  void clear() {
    _points.clear();
    _lines.clear();
    _arcs.clear();
  }
}

class StoryPainterControl {
  late StoryPainterPaintState pageState;
  GlobalKey painterKey = GlobalKey();
  final _paths = <CubicPath?>[];

  void undo() {
    if (_paths.isNotEmpty) {
      _paths.removeLast();
      pageState.remove();
    }
  }

  void removePath(CubicPath path) {
    int index = _paths.indexOf(path);
    _paths.remove(path);

    pageState.removePath(index);
  }

  void clear() {
    _paths.clear();
    pageState.removeAll();
  }

  void setColor(Color newColor) => color = newColor;

  void setWidth(double newWidth) => width = newWidth;

  List<CubicPath?> get paths => _paths;

  List<List<Offset>> get _offsets {
    final list = <List<Offset>>[];

    _paths.forEach((data) => list.add(data!._points));

    return list;
  }

  List<List<CubicLine>> get _cubicLines {
    final list = <List<CubicLine>>[];

    _paths.forEach((data) => list.add(data!._lines));

    return list;
  }

  List<CubicArc> get _arcs {
    final list = <CubicArc>[];

    _paths.forEach((data) => list.addAll(data!.arcs));

    return list;
  }

  List<CubicLine> get lines {
    final list = <CubicLine>[];

    _paths.forEach((data) => list.addAll(data!.lines));

    return list;
  }

  CubicPath? _activePath;

  bool get hasActivePath => _activePath != null;

  bool get isFilled => _paths.isNotEmpty;

  //SignaturePaintParams params;

  Size _areaSize = Size.zero;

  final Function? onDrawStart;
  final Function? onDrawEnd;
  final double threshold;
  final double smoothRatio;
  final double velocityRange;
  PainterDrawType type;
  Color color;
  double width;

  StoryPainterControl({
    this.threshold = 3.0,
    this.smoothRatio = 0.65,
    this.velocityRange = 2.0,
    this.width = 1.0,
    this.color = Colors.black,
    this.onDrawStart,
    this.onDrawEnd,
    this.type = PainterDrawType.shape,
  });

  void startPath(Offset point) {
    if (hasActivePath) {
      alterPath(point);
      return null;
    }
    onDrawStart?.call();

    _activePath = CubicPath(
      DateTime.now().millisecondsSinceEpoch,
      width,
      threshold: threshold,
      smoothRatio: smoothRatio,
      color: color,
      type: type,
    )..maxVelocity = velocityRange;

    _activePath!.begin(point,
        velocity: _paths.isNotEmpty ? _paths.last!._currentVelocity : 0.0);

    _paths.add(_activePath);
    pageState.add();
  }

  void alterPath(Offset point) {
    assert(hasActivePath);

    _activePath!.add(point);
    pageState.update();
  }

  void closePath({Offset? point}) {
    assert(hasActivePath);
    onDrawEnd?.call();

    if (!_activePath!.end(point: point)) {
      _paths.removeLast();
    }

    if (_activePath!.isDot) {
      _activePath!.pathState?.refreshState();
    }

    _activePath = null;
  }

  //TODO: Only landscape to landscape mode works correctly now. Add support for orientation switching.
  bool notifyDimension(Size size) {
    if (_areaSize == size) {
      return false;
    }

    if (_areaSize.isEmpty ||
        _areaSize.width == size.width ||
        _areaSize.height == size.height) {
      _areaSize = size;
      return false;
    }

    if (hasActivePath) {
      closePath();
    }

    if (!isFilled) {
      _areaSize = size;
      return false;
    }

    final ratioX = size.width / _areaSize.width;
    final ratioY = size.height / _areaSize.height;
    final scale = ratioY;

    _areaSize = size;

    _paths.forEach((path) {
      path!.setScale(scale);
    });

    //TODO: Notify is called during rebuild, so notify must be postponed one frame - will be solved by widget/state

    return true;
  }

  Future<ui.Image> toImage({
    double pixelRatio = 2.0,
  }) async {
    RenderRepaintBoundary boundary =
        painterKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    return image;
  }
}
