import 'package:flutter/widgets.dart';
import 'package:kvideo/player_controller.dart';

import 'gen/pigeon.g.dart';

/// Do not initialize this class directly.<br> Use `controller.state`
class PlayerState implements PlayerEventListener {
  final PlayerController _controller;

  PlayerState(this._controller);

  final ValueNotifier<Media?> nowPlaying = ValueNotifier(null);
  final ValueNotifier<Duration> progress = ValueNotifier(Duration.zero);
  final ValueNotifier<String?> textureSubtitles = ValueNotifier(null);
  final ValueNotifier<String?> error = ValueNotifier(null);

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
    this.error.value = error;
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
  void onReceiveSubtitle(String? text) {
    textureSubtitles.value = text;
  }

  @override
  void onVideoSizeUpdate(int width, int height) {
    _controller.textureParams.value = _controller.textureParams.value.copyWith(
      size: Size(width.toDouble(), height.toDouble()),
    );
  }
}
