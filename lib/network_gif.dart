import 'dart:async';
import 'dart:developer';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'gif_info.dart';

class NetworkGif {
  const NetworkGif(this.url, {this.client});
  final String url;
  final Dio? client;

  Future<GifInfo> load() async {
    final Uint8List bytes = await _fetchBytes();
    if (bytes.isEmpty) {
      log('Failed to load $url');
      return const GifInfo(frames: [], duration: Duration.zero);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec =
        await PaintingBinding.instance.instantiateImageCodecWithSize(buffer);
    final List<ui.Image> images = [];
    Duration duration = Duration.zero;
    for (int i = 0; i < codec.frameCount; i++) {
      final info = await codec.getNextFrame();
      images.add(info.image);
      duration += info.duration;
    }
    return GifInfo(frames: images, duration: duration);
  }

  Future<Uint8List> _fetchBytes() async {
    final client = this.client ?? Dio();
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(url);
      if (fileInfo != null) {
        return fileInfo.file.readAsBytes();
      } else {
        final response = await client.get<Uint8List>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        return response.data!;
      }
    } finally {
      if (this.client == null) {
        client.close();
      }
    }
  }
}
