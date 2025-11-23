import 'package:pigeon/pigeon.dart';

/// Run the following to generate pigeon
/// dart run pigeon --input pigeons/pigeon.dart
/// TODO Don't depend on these directly, remove constructor

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: "kvideo",
    dartOut: 'lib/gen/pigeon.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/Pigeon.g.kt',
    kotlinOptions: KotlinOptions(),
    swiftOut: 'ios/Classes/Pigeon.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
@HostApi()
abstract class PlayerInstance {
  void create(String id);

  void dispose(String id);
}

enum PlaybackStatus { playing, paused, finished, error, preparing }

enum BoxFitMode { fill, fit }

class VideoTextureData {
  int? textureId;
  int? width;
  int? height;
  BoxFitMode? fit;
}

@HostApi()
abstract class PlayerControllerApi {
  void initialize(PlayerConfiguration? configuration);

  /// Must be called if ViewMode is texture in android. Returns textureId,width,height
  VideoTextureData initAndroidTextureView();

  void play(Media media);

  void stop();

  void pause();

  void resume();

  void seekTo(int positionMs);

  void seekForward();

  void seekBack();

  void dispose();

  void enterPiPMode();

  int getProgressSecond();

  List<TrackData> getTracks();

  PlaybackStatus getPlaybackStatus();

  double getPlaybackSpeed();

  void setPlaybackSpeed(double speed);

  BoxFitMode getFit();

  void setFit(BoxFitMode fit);

  bool isPlayingIMA();

  void setTrackPreference(TrackData? track);
}

@FlutterApi()
abstract class PlayerEventListener {
  /// Only used for AndroidViewMode.texture
  void onVideoSizeUpdate(int width, int height);

  /// Only used for AndroidViewMode.texture
  void onReceiveSubtitle(String? text);

  void onDurationUpdate(int durationSecond);

  void onProgressUpdate(int second);

  void onBufferUpdate(int second);

  void onPlaybackUpdate(PlaybackStatus status);

  void onPlaybackError(String error);

  void onIMAStatusChange(bool showingAd);

  void onTracksLoaded(List<TrackData> tracks);

  void onPlaybackSpeedUpdate(double speed);
}

class Media {
  /// The Dash URL of the media (required)
  final String url;

  /// Widevine License URL if the media is DRM protected
  final String? drmLicenseUrl;

  /// Fairplay certificate. Can be either URL or Base64 encoded certificate
  final String? drmCertificate;

  /// External subtitles url
  final List<String>? subtitles;

  /// Where to start media from (in seconds)
  final int? startFromSecond;

  /// Player headers
  final Map<String, String>? headers;

  /// IMA Ads
  final String? imaTagUrl;

  Media({
    required this.url,
    this.drmLicenseUrl,
    this.drmCertificate,
    this.startFromSecond,
    this.headers,
    this.imaTagUrl,
    this.subtitles,
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

enum TrackType { audio, video, subtitle, unknown }

class TrackData {
  String? id; // Unique track ID
  TrackType? type; // audio, video, subtitle, metadata
  String? language; // en, es, fr, etc.
  String? label; // Human-readable name
  int? bitrate; // Audio/video bitrate
  int? width; // Video width
  int? height; // Video height
}
