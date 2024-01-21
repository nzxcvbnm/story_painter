import 'package:flutter/material.dart';
import 'package:story_painter/src/utils.dart';

import '../story_painter.dart';

class StoryPainterPaint extends StatefulWidget {
  final StoryPainterControl control;
  final bool Function(Size size)? onSize;

  const StoryPainterPaint({Key? key, required this.control, this.onSize})
      : super(key: key);

  @override
  StoryPainterPaintState createState() => StoryPainterPaintState();
}

class StoryPainterPaintState extends State<StoryPainterPaint> {
  List<SinglePath> pathWidgets = <SinglePath>[];
  @override
  void initState() {
    super.initState();
    widget.control.paths.forEach((_path) {
      pathWidgets.add(SinglePath(
        path: _path,
        onSize: widget.onSize,
        type: _path!.type,
        painterControl: widget.control,
      ));
    });
    widget.control.pageState = this;
  }

  void add() {
    pathWidgets.add(
      SinglePath(
        key: ObjectKey(widget.control.paths.last!.id),
        path: widget.control.paths.last,
        onSize: widget.onSize,
        type: widget.control.type,
        painterControl: widget.control,
      ),
    );
    refreshState();
  }

  void update() {
    pathWidgets.last.path?.pathState?.refreshState();
  }

  void remove() {
    pathWidgets.removeLast();
    refreshState();
  }

  void removePath(int pathIndex) {
    pathWidgets.removeAt(pathIndex);
    refreshState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: pathWidgets,
    );
  }

  void refreshState() {
    if (this.mounted) {
      setState(() {});
    }
  }
}

class SinglePath extends StatefulWidget {
  final CubicPath? path;
  final PainterDrawType? type;
  final StoryPainterControl painterControl;
  final bool Function(Size size)? onSize;

  const SinglePath(
      {Key? key,
      this.type,
      this.onSize,
      this.path,
      required this.painterControl})
      : super(key: key);

  @override
  SinglePathState createState() => SinglePathState();
}

class SinglePathState extends State<SinglePath> {
  @override
  void initState() {
    super.initState();
    widget.path!.pathState = this;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        child: GestureDetector(onPanStart: (d) {
          final press = d.localPosition;
          final paths = widget.painterControl.paths;

          if (widget.painterControl.color == Colors.transparent) {
            loop:
            for (var path in paths.reversed) {
              if (path != null)
                for (var point in path.points) {
                  if (press.distanceTo(point) <= 20) {
                    widget.painterControl.removePath(path);
                    break loop;
                  }
                }
            }
          }
        }),
        isComplex: true,
        willChange: false,
        painter: PathSignaturePainter(
          path: widget.path!,
          onSize: widget.onSize,
        ),
      ),
    );
  }

  void refreshState() {
    if (this.mounted) {
      setState(() {});
    }
  }
}
