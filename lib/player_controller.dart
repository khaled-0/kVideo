import 'dart:async';

import 'package:flutter/widgets.dart';

import 'gen/pigeon.g.dart';
import 'kvideo.dart';

final _instanceManager = PlayerInstance();

class VideoTextureParams {
  final int? textureId;
  final Size size;
  final BoxFitMode fit;

  VideoTextureParams({
    required this.textureId,
    required this.size,
    required this.fit,
  });

  factory VideoTextureParams.nil() =>
      VideoTextureParams(textureId: null, size: Size.zero, fit: BoxFitMode.fit);

  VideoTextureParams copyWith({int? textureId, Size? size, BoxFitMode? fit}) {
    return VideoTextureParams(
      textureId: textureId ?? this.textureId,
      size: size ?? this.size,
      fit: fit ?? this.fit,
    );
  }
}

class PlayerController {
  final id = UniqueKey().toString();

  final AndroidViewMode androidViewMode;

  PlayerController({this.androidViewMode = AndroidViewMode.texture});

  /// Used if  androidViewMode AndroidViewMode.texture
  final ValueNotifier<VideoTextureParams> textureParams = ValueNotifier(
    VideoTextureParams.nil(),
  );

  late final _api = PlayerControllerApi(messageChannelSuffix: id);
  late final state = PlayerState(this);

  Future<void> initialize({PlayerConfiguration? configuration}) async {
    await _instanceManager.create(id);
    await _api.initialize(configuration);
    PlayerEventListener.setUp(state, messageChannelSuffix: id);

    if (androidViewMode == AndroidViewMode.texture) {
      final value = await _api.initAndroidTextureView();
      textureParams.value = textureParams.value.copyWith(
        textureId: value.textureId ?? -1,
        fit: value.fit,
        size: Size(
          (value.width ?? 0).toDouble(),
          (value.height ?? 0).toDouble(),
        ),
      );
    }
  }

  Future<void> play(Media? media) {
    state.tracks.value = [];
    if (media == null) return _api.stop();
    return _api.play(media);
  }

  Future<void> seekBack() => _api.seekBack();

  Future<void> seekForward() => _api.seekForward();

  Future<void> seekTo(Duration position) =>
      _api.seekTo(position.inMilliseconds);

  Future<void> pause() => _api.pause();

  Future<void> resume() => _api.resume();

  Future<void> enterPiPMode() => _api.enterPiPMode();

  Future<Duration> getProgress() =>
      _api.getProgressSecond().then((s) => Duration(seconds: s));

  Future<List<TrackData>> getTracks() => _api.getTracks();

  Future<PlaybackStatus> getPlaybackStatus() => _api.getPlaybackStatus();

  Future<double> getPlaybackSpeed() => _api.getPlaybackSpeed();

  Future<BoxFitMode> getFit() => _api.getFit();

  Future<void> setFit(BoxFitMode fit) {
    if (androidViewMode == AndroidViewMode.texture) {
      textureParams.value = textureParams.value.copyWith(fit: fit);
    }

    return _api.setFit(fit);
  }

  Future<void> setTrackPreference(TrackData? track) {
    return _api.setTrackPreference(track);
  }

  Future<void> setPlaybackSpeed(double speed) {
    return _api.setPlaybackSpeed(speed);
  }

  Future<void> dispose() {
    _instanceManager.dispose(id);
    PlayerEventListener.setUp(null, messageChannelSuffix: id);
    return _api.dispose();
  }
}
