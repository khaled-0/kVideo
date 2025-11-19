import 'package:pigeon/pigeon.dart';

/// Run the following to generate pigeon
/// dart run pigeon --input pigeons/pigeon.dart

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: "kvideo",
    dartOut: 'lib/gen/pigeon.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/Pigeon.g.kt',
    kotlinOptions: KotlinOptions(),
    // swiftOut: 'ios/Runner/Messages.g.swift',
    // swiftOptions: SwiftOptions(),
  ),
)
@HostApi()
abstract class PlayerInstance {
  void create(String id);

  void dispose(String id);
}

@HostApi()
abstract class PlayerControllerApi {
  void init(PlayerConfiguration? configuration);

  /// Must be called if ViewMode is texture in android. Returns textureId,width,height
  Map<String, double> initAndroidTextureView();

  void play(Media media);

  void pause();

  void resume();

  void seekTo(int positionMs);

  void seekForward();

  void seekBack();

  void dispose();

  void enterPiPMode();
}

enum PlaybackStatus { playing, paused, finished, error, preparing }

@FlutterApi()
abstract class PlayerEventListener {
  void videoSizeUpdate(int height, int width);

  void durationUpdate(int durationSecond);

  void progressUpdate(int second);

  void bufferUpdate(int second);

  void playbackStatusUpdate(PlaybackStatus status);

  void onPlaybackError(String error);

  void onIMAStatusChange(bool showingAd);
}

class Media {
  /// The Dash URL of the media (required)
  final String url;

  /// Widevine License URL if the media is DRM protected
  final String? drmLicenseUrl;

  /// Where to start media from (in seconds)
  final int? startFromSecond;

  /// Player headers
  final Map<String, String>? headers;

  /// IMA Ads
  final String? imaTagUrl;

  Media({
    required this.url,
    this.drmLicenseUrl,
    this.startFromSecond,
    this.headers,
    this.imaTagUrl,
  });
}

class PlayerConfiguration {
  final BufferingConfig? bufferingConfig;
  final SeekConfig? seekConfig;
  final bool? initializeIMA;

  PlayerConfiguration({
    this.bufferingConfig,
    this.seekConfig,
    this.initializeIMA,
  });
}

class BufferingConfig {
  final int? minBufferMs;
  final int? maxBufferMs;

  BufferingConfig({this.minBufferMs, this.maxBufferMs});
}

class SeekConfig {
  final int? seekForwardMs;
  final int? seekBackMs;

  SeekConfig({this.seekForwardMs, this.seekBackMs});
}
