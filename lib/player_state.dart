import 'package:flutter/cupertino.dart';
import 'package:kvideo/controller.dart';

import 'gen/pigeon.g.dart';

/// Do not initialize this class directly.<br> Use `controller.state`
class PlayerState implements PlayerEventListener {
  final PlayerController _controller;

  PlayerState(this._controller);

  final ValueNotifier<Media?> nowPlaying = ValueNotifier(null);
  final ValueNotifier<Duration> progress = ValueNotifier(Duration.zero);

  @override
  void onBufferUpdate(int second) {
    // TODO: implement onBufferUpdate
  }

  @override
  void onDurationUpdate(int durationSecond) {
    // TODO: implement onDurationUpdate
  }

  @override
  void onIMAStatusChange(bool showingAd) {
    // TODO: implement onIMAStatusChange
  }

  @override
  void onPlaybackError(String error) {
    // TODO: implement onPlaybackError
  }

  @override
  void onPlaybackSpeedUpdate(double speed) {
    // TODO: implement onPlaybackSpeedUpdate
  }

  @override
  void onPlaybackUpdate(PlaybackStatus status) {
    // TODO: implement onPlaybackUpdate
  }

  @override
  void onProgressUpdate(int second) {
    // TODO: implement onProgressUpdate
  }

  @override
  void onTracksLoaded(List<TrackData> tracks) {
    // TODO: implement onTracksLoaded
  }

  @override
  void onVideoSizeUpdate(int height, int width) {
    _controller.textureParams.value = _controller.textureParams.value.copyWith(
      size: Size(width.toDouble(), height.toDouble()),
    );
  }
}
