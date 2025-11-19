import 'gen/pigeon.g.dart';

mixin PlayerEventMixin implements PlayerEventListener {
  @override
  void onProgress(int progressSecond, int bufferSecond) {}

  @override
  void onDurationChange(int durationSecond) {}

  @override
  void onLoadingUpdate(bool isLoading) {}

  @override
  void onPlaybackError(String exception) {}

  @override
  void onPlaybackFinish() {}

  @override
  void onPlaybackUpdate(bool isPlaying) {}

  @override
  void onAdStatusChange(bool showingAd) {}
}
