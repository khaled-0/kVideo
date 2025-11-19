import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'kvideo.dart';

final _instanceManager = PlayerInstance();

typedef VideoTextureParams = ({int? textureId, Size size});

class PlayerController with WidgetsBindingObserver {
  final id = UniqueKey().toString();

  final AndroidViewMode androidViewMode;

  PlayerController({this.androidViewMode = AndroidViewMode.texture});

  /// Only initialized if AndroidViewMode.texture
  final ValueNotifier<VideoTextureParams> textureParams = ValueNotifier((
    size: Size.zero,
    textureId: null,
  ));

  late final _api = PlayerControllerApi(messageChannelSuffix: id);

  Future<void> initialize({
    PlayerConfiguration? configuration,

    /// Pause / Resume on going back and forth to background
    bool handleLifecycle = true,
  }) async {
    await _instanceManager.create(id);
    await _api.init(configuration);
    if (androidViewMode == AndroidViewMode.texture) {
      final value = await _api.initAndroidTextureView();
      textureParams.value = (
        textureId: value["textureId"]!.toInt(),
        size: Size(value["width"]!, value["height"]!),
      );
    }

    if (handleLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  /// Calling this method replaces existing listeners
  void setListener(PlayerEventListener listener) {
    PlayerEventListener.setUp(listener, messageChannelSuffix: id);
  }

  Future<void> play(Media media) => _api.play(media);

  Future<void> seekBack() => _api.seekBack();

  Future<void> seekForward() => _api.seekForward();

  Future<void> seekTo(Duration position) =>
      _api.seekTo(position.inMilliseconds);

  Future<void> pause() => _api.pause();

  Future<void> resume() => _api.resume();

  Future<void> enterPiPMode() => _api.enterPiPMode();

  Future<void> dispose() {
    _instanceManager.dispose(id);
    PlayerEventListener.setUp(null, messageChannelSuffix: id);
    WidgetsBinding.instance.removeObserver(this);
    return _api.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        pause();

      case AppLifecycleState.resumed:
        resume();

      default:
    }
  }
}
