import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart';

final Client _sharedHttpClient = Client();

Client get _httpClient => _sharedHttpClient;

/// Enum to define how to auto start the gif.
enum Autostart {
  no, // Don't start.
  once, // Run once every time a new gif is loaded.
  loop, // Loop playback.
}

/// A widget that renders a Gif controllable with [AnimationController].
@immutable
class Gif extends StatefulWidget {
  static GifCache cache = GifCache();

  final ImageProvider image;
  final GifController? controller;
  final int? fps;
  final Duration? duration;
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

  const Gif({
    super.key,
    required this.image,
    this.controller,
    this.fps,
    this.duration,
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
  })  : assert(
          fps == null || duration == null,
          'Only one of the two can be set: [fps] or [duration]',
        ),
        assert(fps == null || fps > 0, 'fps must be greater than 0');

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
  GifController({required super.vsync});
}

@immutable
class GifInfo {
  final List<ImageInfo> frames;
  final Duration duration;

  const GifInfo({
    required this.frames,
    required this.duration,
  });
}

class _GifState extends State<Gif> with SingleTickerProviderStateMixin {
  late final GifController _controller;
  List<ImageInfo> _frames = [];
  int _frameIndex = 0;

  ImageInfo? get _currentFrame =>
      _frames.isNotEmpty ? _frames[_frameIndex] : null;

  @override
  Widget build(BuildContext context) {
    final RawImage image = RawImage(
      image: _currentFrame?.image,
      width: widget.width,
      height: widget.height,
      scale: _currentFrame?.scale ?? 1.0,
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

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? GifController(vsync: this);
    _controller.addListener(_updateFrameIndex);
    _loadFrames().then((_) => _handleAutostart());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFrames().then((_) => _handleAutostart());
  }

  @override
  void didUpdateWidget(Gif oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_updateFrameIndex);
      _controller = widget.controller ?? GifController(vsync: this);
      _controller.addListener(_updateFrameIndex);
    }

    if (widget.image != oldWidget.image ||
        widget.fps != oldWidget.fps ||
        widget.duration != oldWidget.duration) {
      _loadFrames().then((_) => _handleAutostart());
    }

    if (widget.autostart != oldWidget.autostart) {
      _handleAutostart();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateFrameIndex);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleAutostart() {
    if (!mounted || widget.autostart == Autostart.no) return;

    _controller.reset();
    widget.autostart == Autostart.loop
        ? _controller.repeat()
        : _controller.forward();
  }

  String _getImageKey(ImageProvider provider) {
    if (provider is NetworkImage) return provider.url;
    if (provider is AssetImage) return provider.assetName;
    if (provider is FileImage) return provider.file.path;
    if (provider is MemoryImage) return provider.bytes.toString();
    return "";
  }

  void _updateFrameIndex() {
    if (mounted && _frames.isNotEmpty) {
      setState(() {
        _frameIndex = ((_frames.length - 1) * _controller.value).floor();
      });
    }
  }

  Future<void> _loadFrames() async {
    if (!mounted) return;

    final GifInfo gifInfo = widget.useCache
        ? Gif.cache.caches[_getImageKey(widget.image)] ??
            await _fetchFrames(widget.image)
        : await _fetchFrames(widget.image);

    if (!mounted) return;

    if (widget.useCache) {
      Gif.cache.caches.putIfAbsent(_getImageKey(widget.image), () => gifInfo);
    }

    setState(() {
      _frames = gifInfo.frames;
      _controller.duration = widget.fps != null
          ? Duration(
              milliseconds: (_frames.length / widget.fps! * 1000).round())
          : widget.duration ?? gifInfo.duration;

      widget.onFetchCompleted?.call();
    });
  }

  static Future<GifInfo> _fetchFrames(ImageProvider provider) async {
    final Uint8List bytes = await _fetchBytes(provider);
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    final Codec codec =
        await PaintingBinding.instance.instantiateImageCodecWithSize(buffer);

    List<ImageInfo> infos = [];
    Duration duration = const Duration();

    for (int i = 0; i < codec.frameCount; i++) {
      final FrameInfo frameInfo = await codec.getNextFrame();
      infos.add(ImageInfo(image: frameInfo.image));
      duration += frameInfo.duration;
    }

    return GifInfo(frames: infos, duration: duration);
  }

  static Future<Uint8List> _fetchBytes(ImageProvider provider) async {
    if (provider is NetworkImage) {
      final Uri resolved = Uri.base.resolve(provider.url);
      final Response response =
          await _httpClient.get(resolved, headers: provider.headers);
      return response.bodyBytes;
    } else if (provider is AssetImage) {
      final key = await provider.obtainKey(const ImageConfiguration());
      return (await key.bundle.load(key.name)).buffer.asUint8List();
    } else if (provider is FileImage) {
      return await provider.file.readAsBytes();
    } else if (provider is MemoryImage) {
      return provider.bytes;
    }
    throw UnsupportedError('Unsupported image provider type');
  }
}
