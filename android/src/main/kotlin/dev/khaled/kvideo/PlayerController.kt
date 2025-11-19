package dev.khaled.kvideo

import Media
import PlayerConfiguration
import PlayerControllerApi
import android.content.Context
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
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

    init {
        PlayerControllerApi.setUp(binaryMessenger, this, suffix)
    }


    override fun init(configuration: PlayerConfiguration?) {
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

//    override fun initAndroidActivityView() {
//        context.startActivity(
//            Intent(context, PlayerActivity::class.java).apply {
//                flags = Intent.FLAG_ACTIVITY_NEW_TASK
//                putExtra("id", suffix)
//            })
//    }

    override fun initAndroidTextureView(): Map<String, Double> {
        surfaceProducer = textureRegistry.createSurfaceProducer()
        surfaceProducer.setCallback(this)
        val textureId = surfaceProducer.id()
        player.setVideoSurface(surfaceProducer.surface)
        return buildMap {
            put("textureId", textureId.toDouble())
            put("width", player.videoFormat?.width?.toDouble() ?: 0.0)
            put("height", player.videoFormat?.height?.toDouble() ?: 0.0)
        }
    }


    override fun play(media: Media) {
        Log.d("PlayerController_play", media.toString())

        val headers = media.headers ?: emptyMap()
        val mediaItem = MediaItem.Builder().setUri(media.url).apply {

            media.startFromSecond?.let {
                if (it <= 0) return@let

                setMediaMetadata(
                    MediaMetadata.Builder().setExtras(
                        Bundle().apply { putLong("startFromSecond", it) }).build()
                )
            }

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
        player.prepare()
    }


    override fun pause() = player.pause()
    override fun resume() = player.play()
    override fun seekTo(positionMs: Long) = player.seekTo(positionMs)
    override fun seekForward() = player.seekForward()
    override fun seekBack() = player.seekBack()

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
    }
}

