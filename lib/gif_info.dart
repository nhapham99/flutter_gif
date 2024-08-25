import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
class GifInfo {
  const GifInfo({
    required this.frames,
    required this.duration,
  });

  final List<Image> frames;
  final Duration duration;
}
