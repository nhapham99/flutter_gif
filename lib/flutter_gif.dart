import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'gif_info.dart';
import 'network_gif.dart';

final dio = Dio();

enum Autostart {
  no,
  once,
  loop,
}

@immutable
class Gif extends StatefulWidget {
  const Gif({
    super.key,
    this.gifInfo,
    this.url,
    this.assetName,
    this.controller,
    this.autostart = Autostart.no,
    this.placeholder,
    this.onFetchCompleted,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.useCache = true,
  });

  // Factory constructor to create Gif widget from network source
  factory Gif.network(
    String url, {
    Key? key,
    GifController? controller,
    Autostart autostart = Autostart.no,
    Widget Function(BuildContext context)? placeholder,
    VoidCallback? onFetchCompleted,
    double? width,
    double? height,
    Color? color,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    bool useCache = true,
  }) {
    return Gif(
      key: key,
      url: url,
      controller: controller,
      autostart: autostart,
      placeholder: placeholder,
      onFetchCompleted: onFetchCompleted,
      width: width,
      height: height,
      color: color,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      useCache: useCache,
    );
  }

  final GifInfo? gifInfo;
  final String? url;
  final String? assetName;
  final GifController? controller;
  final Autostart autostart;
  final Widget Function(BuildContext context)? placeholder;
  final VoidCallback? onFetchCompleted;
  final double? width;
  final double? height;
  final Color? color;
  final BlendMode? colorBlendMode;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final Rect? centerSlice;
  final bool matchTextDirection;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final bool useCache;

  // Cache for GIFs
  static final GifCache cache = GifCache();

  @override
  State<Gif> createState() => _GifState();
}

@immutable
class GifCache {
  final Map<String, GifInfo> caches = {};

  void clear() => caches.clear();

  bool evict(Object key) => caches.remove(key) != null;
}

class GifController extends AnimationController {
  GifController({required super.vsync, super.duration});
}

class _GifState extends State<Gif> with SingleTickerProviderStateMixin {
  GifController? _controller;
  GifInfo? _gifInfo;
  int _frameIndex = 0;

  ui.Image? get _currentFrame => _gifInfo?.frames.isNotEmpty ?? false
      ? _gifInfo!.frames[_frameIndex]
      : null;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? GifController(vsync: this);
    _controller!.addListener(_updateFrameIndex);
    _loadGif();
  }

  Future<void> _loadGif() async {
    if (widget.gifInfo != null) {
      setState(() {
        _gifInfo = widget.gifInfo;
        _handleAutostart();
      });
    } else if (widget.url != null) {
      final gifInfo = widget.useCache
          ? Gif.cache.caches[widget.url!] ??
              await NetworkGif(widget.url!).load()
          : await NetworkGif(widget.url!).load();

      setState(() {
        _gifInfo = gifInfo;
        if (widget.useCache) {
          Gif.cache.caches[widget.url!] = gifInfo;
        }
        _handleAutostart();
      });
    }
  }

  @override
  void didUpdateWidget(Gif oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_updateFrameIndex);
      _controller = widget.controller ?? GifController(vsync: this);
      _controller!.addListener(_updateFrameIndex);
    }

    if (widget.autostart != oldWidget.autostart) {
      _handleAutostart();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_updateFrameIndex);
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  void _handleAutostart() {
    if (!mounted || widget.autostart == Autostart.no) {
      return;
    }

    _controller?.reset();
    widget.autostart == Autostart.loop
        ? _controller?.repeat()
        : _controller?.forward();
  }

  void _updateFrameIndex() {
    if (mounted && (_gifInfo?.frames.isNotEmpty ?? false)) {
      setState(() {
        _frameIndex =
            (_controller!.value * (_gifInfo!.frames.length - 1)).floor();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final RawImage image = RawImage(
      image: _currentFrame,
      width: widget.width,
      height: widget.height,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      fit: widget.fit,
      alignment: widget.alignment,
      repeat: widget.repeat,
      centerSlice: widget.centerSlice,
      matchTextDirection: widget.matchTextDirection,
    );

    return widget.placeholder != null && _currentFrame == null
        ? widget.placeholder!(context)
        : widget.excludeFromSemantics
            ? image
            : Semantics(
                container: widget.semanticLabel != null,
                image: true,
                label: widget.semanticLabel ?? '',
                child: image,
              );
  }
}
