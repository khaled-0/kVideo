import 'package:flutter/widgets.dart';
import 'package:kvideo/player_controller.dart';
import 'package:kvideo/player_view.dart';

import 'gen/pigeon.g.dart';

/// Do not initialize this class directly.<br> Use `controller.state`
class PlayerState implements PlayerEventListener {
  final PlayerController _controller;

  PlayerState(this._controller);

  final ValueNotifier<Duration> progress = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> buffer = ValueNotifier(Duration.zero);

  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<PlaybackStatus> status = ValueNotifier(
    PlaybackStatus.finished,
  );

  final ValueNotifier<double> speed = ValueNotifier(1.0);
  final ValueNotifier<List<TrackData>> tracks = ValueNotifier([]);

  final ValueNotifier<bool> pipMode = ValueNotifier(false);

  final ValueNotifier<bool> ima = ValueNotifier(false);

  @override
  void onBufferUpdate(int second) {
    buffer.value = Duration(seconds: second);
  }

  @override
  void onDurationUpdate(int second) {
    duration.value = Duration(seconds: second);
  }

  @override
  void onIMAStatusChange(bool showingAd) {
    ima.value = showingAd;
  }

  @override
  void onPlaybackError(String error) {
    this.error.value = error;
  }

  @override
  void onPlaybackSpeedUpdate(double speed) {
    this.speed.value = speed;
  }

  @override
  void onPlaybackUpdate(PlaybackStatus status) {
    this.status.value = status;
    // Clear error on successful playback
    if (error.value != null && status != PlaybackStatus.error) {
      error.value = null;
    }
  }

  @override
  void onProgressUpdate(int second) {
    progress.value = Duration(seconds: second);
  }

  @override
  void onTracksLoaded(List<TrackData> tracks) {
    /// TODO Parsed Subtitles
    this.tracks.value = [...tracks];
  }

  @override
  void onVideoSizeUpdate(int width, int height) {
    if (_controller.androidViewMode != AndroidViewMode.texture) return;
    _controller.textureParams.value = _controller.textureParams.value.copyWith(
      size: Size(width.toDouble(), height.toDouble()),
    );
  }

  @override
  void onPiPModeChange(bool inPip) {
    pipMode.value = inPip;
  }
}
