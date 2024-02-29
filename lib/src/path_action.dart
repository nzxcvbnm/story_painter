import 'package:story_painter/story_painter.dart';

class PathAction {
  PathAction({required this.path, required this.action});
  final CubicPath path;
  final Act action;
}

enum Act { add, remove }
