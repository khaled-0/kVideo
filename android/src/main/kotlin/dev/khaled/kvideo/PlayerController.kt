package dev.khaled.kvideo

import BoxFitMode
import Media
import PlaybackStatus
import PlayerConfiguration
import PlayerControllerApi
import TrackData
import TrackType
import VideoTextureData
import android.content.Context
import android.content.Intent
import android.view.SurfaceView
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DummyExoMediaDrm
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.UnsupportedDrmException
import androidx.media3.exoplayer.ima.ImaAdsLoader
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
import androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
import androidx.media3.ui.PlayerView
import com.google.ads.interactivemedia.v3.api.ImaSdkFactory
import com.google.ads.interactivemedia.v3.api.ImaSdkSettings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry


@OptIn(UnstableApi::class)
class PlayerController(
    val context: Context,
    val suffix: String,
    val binaryMessenger: BinaryMessenger,
    val textureRegistry: TextureRegistry,
) : PlayerControllerApi, TextureRegistry.SurfaceProducer.Callback {
    val playerView = PlayerView(context)
    lateinit var player: ExoPlayer
        private set

    private lateinit var surfaceProducer: TextureRegistry.SurfaceProducer
    private val eventHandler by lazy { PlayerEventHandler(binaryMessenger, suffix, this) }


    private var imaSdkSettings: Lazy<ImaSdkSettings>? = lazy {
        ImaSdkFactory.getInstance().createImaSdkSettings()
    }

    val adsLoader by lazy {
        ImaAdsLoader.Builder(context).setImaSdkSettings(imaSdkSettings!!.value)
            .setAdEventListener(eventHandler).build()
    }

    val trackSelector = DefaultTrackSelector(context)

    init {
        PlayerControllerApi.setUp(binaryMessenger, this, suffix)
    }


    override fun initialize(configuration: PlayerConfiguration?) {
        if (configuration?.initializeIMA != false) {
            try {
                ImaSdkFactory.getInstance().initialize(context, imaSdkSettings!!.value)
            } catch (_: Exception) {
                imaSdkSettings = null
            }
        }

        player = ExoPlayer.Builder(context).apply {
            configuration?.bufferingConfig?.let {
                setLoadControl(
                    DefaultLoadControl.Builder().setBufferDurationsMs(
                        it.minBufferMs?.toInt() ?: DefaultLoadControl.DEFAULT_MIN_BUFFER_MS,
                        it.maxBufferMs?.toInt() ?: DefaultLoadControl.DEFAULT_MAX_BUFFER_MS,
                        DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                        DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
                    ).build()
                )
            }

            configuration?.seekConfig?.let {
                setSeekBackIncrementMs(it.seekBackMs ?: 10_000L)
                setSeekForwardIncrementMs(it.seekForwardMs ?: 10_000L)
            }

            setTrackSelector(trackSelector)

            /// Handle Audio Focus
            setHandleAudioBecomingNoisy(true)
            setWakeMode(C.WAKE_MODE_LOCAL)
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).let {
                    setAudioAttributes(it.build(), true)
                }

        }.build()


        with(player) {
            playerView.player = this
            playWhenReady = true
            if (imaSdkSettings?.isInitialized() ?: false) adsLoader.setPlayer(this)
            addListener(eventHandler)
        }
    }


    override fun initAndroidTextureView(): VideoTextureData {
        surfaceProducer = textureRegistry.createSurfaceProducer()
        surfaceProducer.setCallback(this)
        val textureId = surfaceProducer.id()
        player.setVideoSurface(surfaceProducer.surface)
        return VideoTextureData(textureId = textureId, fit = getFit())
    }


    override fun play(media: Media) {
        Log.d("PlayerController_play", media.toString())

        val headers = media.headers ?: emptyMap()
        val mediaItem = MediaItem.Builder().setUri(media.url).apply {
            media.imaTagUrl?.let {
                setAdsConfiguration(
                    MediaItem.AdsConfiguration.Builder(it.toUri()).setAdsId(media.url).build()
                )
            }
        }.build()


        val dataSourceFactory = DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
        val drmCallback = HttpMediaDrmCallback(media.drmLicenseUrl, dataSourceFactory).apply {
            media.headers?.entries?.forEach { setKeyRequestProperty(it.key, it.value) }
        }

        val mediaSourceFactory = DefaultMediaSourceFactory(context).apply {
            setDataSourceFactory(dataSourceFactory)

            if (media.drmLicenseUrl != null) {
                setDrmSessionManagerProvider {
                    DefaultDrmSessionManager.Builder().apply {
                        // Force L3 on TextureView
                        if (this@PlayerController::surfaceProducer.isInitialized) {
                            setUuidAndExoMediaDrmProvider(C.WIDEVINE_UUID) {
                                try {
                                    val mediaDrm = FrameworkMediaDrm.newInstance(it)
                                    mediaDrm.setPropertyString("securityLevel", "L3")
                                    return@setUuidAndExoMediaDrmProvider mediaDrm
                                } catch (_: UnsupportedDrmException) {
                                    return@setUuidAndExoMediaDrmProvider DummyExoMediaDrm()
                                }
                            }
                        }
                    }.build(drmCallback)
                }
            }
        }


        val mediaSource = mediaSourceFactory.apply {
            if (!(imaSdkSettings?.isInitialized() ?: false)) return@apply
            setLocalAdInsertionComponents({ adsLoader }, playerView)
        }.createMediaSource(mediaItem)

        player.setMediaSource(mediaSource)
        media.startFromSecond?.let {
            if (it <= 0) return@let
            player.seekTo(it * 1000)
        }

        player.prepare()
    }

    override fun stop() = player.stop()
    override fun pause() = player.pause()
    override fun resume() = player.play()
    override fun seekTo(positionMs: Long) = player.seekTo(positionMs)
    override fun seekForward() = player.seekForward()
    override fun seekBack() = player.seekBack()
    override fun setPlaybackSpeed(speed: Double) = player.setPlaybackSpeed(speed.toFloat())


    private val pipListener = {
        if (this::surfaceProducer.isInitialized) {
            player.setVideoSurface(surfaceProducer.surface)
        } else {
            playerView.player = player
            player.setVideoSurfaceView(playerView.videoSurfaceView as SurfaceView)
        }
    }

    override fun enterPiPMode() {
        val intent = Intent(context, PiPActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        intent.putExtra("id", suffix)
        context.startActivity(intent)
        PiPManager.addListener(pipListener)
    }

    override fun getProgressSecond(): Long = player.currentPosition

    override fun getTracks(): List<TrackData> = player.currentTracks.groups.flatMap { group ->
        val trackGroup = group.mediaTrackGroup

        (0 until trackGroup.length).mapNotNull { i ->
            if (!group.isTrackSupported(i)) return@mapNotNull null
            val format = trackGroup.getFormat(i)
            val type = when (format.sampleMimeType) {
                null -> null
                else -> when {
                    MimeTypes.isVideo(format.sampleMimeType) -> TrackType.VIDEO
                    MimeTypes.isAudio(format.sampleMimeType) -> TrackType.AUDIO
                    else -> null
                }
            }

            if (type == null) return@mapNotNull null

            return@mapNotNull TrackData(
                id = format.id,
                type = type,
                language = format.language,
                label = format.label,
                bitrate = format.bitrate.takeIf { it != Format.NO_VALUE }?.toLong(),
                width = format.width.takeIf { it != Format.NO_VALUE }?.toLong(),
                height = format.height.takeIf { it != Format.NO_VALUE }?.toLong()
            )
        }
    }


    override fun getPlaybackStatus(): PlaybackStatus {
        return when (player.playbackState) {
            Player.STATE_BUFFERING -> PlaybackStatus.PREPARING
            Player.STATE_READY -> if (player.playWhenReady) PlaybackStatus.PLAYING else PlaybackStatus.PAUSED
            Player.STATE_IDLE -> if (player.playerError != null) PlaybackStatus.ERROR else PlaybackStatus.FINISHED
            else -> PlaybackStatus.FINISHED // Player.STATE_ENDED
        }
    }

    override fun getPlaybackSpeed(): Double = player.playbackParameters.speed.toDouble()

    override fun getFit(): BoxFitMode = when (playerView.resizeMode) {
        RESIZE_MODE_ZOOM -> BoxFitMode.FILL
        else -> BoxFitMode.FIT
    }

    override fun setFit(fit: BoxFitMode) {
        playerView.resizeMode = when (fit) {
            BoxFitMode.FIT -> RESIZE_MODE_FIT
            BoxFitMode.FILL -> RESIZE_MODE_ZOOM
        }
    }

    override fun isPlayingIMA(): Boolean = player.isPlayingAd

    fun TrackType.toExoType(): Int = when (this) {
        TrackType.AUDIO -> C.TRACK_TYPE_AUDIO
        TrackType.VIDEO -> C.TRACK_TYPE_VIDEO
        TrackType.SUBTITLE -> C.TRACK_TYPE_TEXT
        TrackType.UNKNOWN -> C.TRACK_TYPE_UNKNOWN
    }

    override fun setTrackPreference(track: TrackData?) {
        if (track == null) {
            // Auto Quality
            return with(trackSelector.buildUponParameters()) {
                clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                clearVideoSizeConstraints()
                trackSelector.parameters = build()
            }
        }

        if (track.type == TrackType.SUBTITLE) return

        var override: TrackSelectionOverride? = null
        player.currentTracks.groups.forEach { group ->
            // Match by TYPE first (Audio/Video/Text)
            if (group.type == track.type?.toExoType()) {
                for (trackIndex in 0 until group.length) {
                    val format = group.getTrackFormat(trackIndex)

                    // Compare fields if they exist
                    val matches = listOf(
                        track.language?.let { it == format.language },
                        track.bitrate?.let { it == format.bitrate.toLong() },
                        track.width?.let { it == format.width.toLong() },
                        track.height?.let { it == format.height.toLong() },
                        track.label?.let { it == format.label },
                    ).all { it != false }

                    if (!matches) continue
                    override = TrackSelectionOverride(group.mediaTrackGroup, listOf(trackIndex))
                    break
                }
            }
        }

        if (override == null) return
        with(trackSelector.buildUponParameters()) {
            clearOverridesOfType(override.type)
            addOverride(override)
            trackSelector.parameters = build()
        }
    }

    override fun onSurfaceAvailable() {
        super.onSurfaceAvailable()
        if (!this::surfaceProducer.isInitialized) return
        player.setVideoSurface(surfaceProducer.surface)
    }

    override fun onSurfaceCleanup() {
        super.onSurfaceCleanup()
        if (!this::surfaceProducer.isInitialized) return
        player.setVideoSurface(null)
    }

    override fun dispose() {
        if (imaSdkSettings?.isInitialized() ?: false) {
            adsLoader.setPlayer(null)
            adsLoader.release()
        }
        playerView.player = null
        player.release()
        if (this::surfaceProducer.isInitialized) surfaceProducer.surface.release()
        PiPManager.removeListener(pipListener)
    }
}

