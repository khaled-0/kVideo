package dev.khaled.kvideo

import android.os.Handler
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Player.STATE_READY
import androidx.media3.common.Timeline
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.source.BehindLiveWindowException
import com.google.ads.interactivemedia.v3.api.AdEvent
import io.flutter.plugin.common.BinaryMessenger


@UnstableApi
class PlayerEventHandler(
    binaryMessenger: BinaryMessenger, suffix: String, val playerController: PlayerController
) : Player.Listener, AdEvent.AdEventListener {
    val listener: PlayerEventListener = PlayerEventListener(binaryMessenger, suffix)
    private val player = playerController.player

    init {
        /// Send Progress Updates Every Seconds
        val handler = Handler(player.applicationLooper)
        handler.post(object : Runnable {
            override fun run() {
                if (player.isReleased) return
                handler.postDelayed(this, 1000)

                if (!player.isPlaying) return
                listener.onProgressUpdate(player.currentPosition / 1000) {}
                listener.onBufferUpdate(player.bufferedPosition / 1000) {}
            }
        })
    }

    override fun onTimelineChanged(timeline: Timeline, reason: Int) {
        super.onTimelineChanged(timeline, reason)
        listener.onDurationUpdate(
            if (player.duration != C.TIME_UNSET) player.duration.div(1000) else 0
        ) {}
    }

    override fun onIsLoadingChanged(isLoading: Boolean) {
        super.onIsLoadingChanged(isLoading)
        listener.onPlaybackUpdate(playerController.getPlaybackStatus()) {}
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        super.onIsPlayingChanged(isPlaying)
        listener.onPlaybackUpdate(playerController.getPlaybackStatus()) {}
    }


    override fun onPlaybackStateChanged(state: Int) {
        super.onPlaybackStateChanged(state)
        listener.onPlaybackUpdate(playerController.getPlaybackStatus()) {}
        if (state == STATE_READY) {
            listener.onTracksLoaded(playerController.getTracks()) {}
            disableEmbeddedSubtitles()
        }
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        super.onPositionDiscontinuity(oldPosition, newPosition, reason)
        listener.onProgressUpdate(newPosition.positionMs / 1000) {}
    }


    override fun onPlayerError(error: PlaybackException) {
        super.onPlayerError(error)

        if (error is ExoPlaybackException) {
            // Retry Live Automatically
            if (error.cause is BehindLiveWindowException) {
                player.prepare()
                return
            }

            // Recreate surface if needed
            error.message?.let {
                if (it.contains("runtime error") || it.contains("format_supported=YES")) {
                    playerController.reattachPlayerSurface()
                    return
                }
            }
        }

        listener.onPlaybackError(error.toString()) {}
    }


    override fun onAdEvent(event: AdEvent) {
        Log.d("PlayerEventHandler_onAdEvent", event.type.toString())
        listener.onIMAStatusChange(
            IMAEventData(
                event.type.toIMAStatus(),
                event.ad?.skipTimeOffset,
                event.ad?.adId,
            )
        ) {}
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        super.onVideoSizeChanged(videoSize)
        listener.onVideoSizeUpdate(
            VideoTextureData(
                width = (videoSize.width * videoSize.pixelWidthHeightRatio).toLong(),
                height = videoSize.height.toLong()
            )
        ) {}
    }


    override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
        super.onPlaybackParametersChanged(playbackParameters)
        listener.onPlaybackSpeedUpdate(playbackParameters.speed.toDouble()) {}
    }


    private fun disableEmbeddedSubtitles() {
        val trackInfo = playerController.trackSelector.currentMappedTrackInfo ?: return
        val builder = playerController.trackSelector.buildUponParameters()

        for (i in 0 until trackInfo.rendererCount) {
            if (player.getRendererType(i) == C.TRACK_TYPE_TEXT) {
                builder.clearOverridesOfType(C.TRACK_TYPE_TEXT)
                builder.setRendererDisabled(i, true)
            }
        }

        playerController.trackSelector.parameters = builder.build()
    }
}


fun AdEvent.AdEventType.toIMAStatus(): IMAStatus? = when (this) {
    AdEvent.AdEventType.ALL_ADS_COMPLETED -> IMAStatus.ALL_ADS_COMPLETED
    AdEvent.AdEventType.AD_BREAK_FETCH_ERROR -> IMAStatus.AD_BREAK_FETCH_ERROR
    AdEvent.AdEventType.CLICKED -> IMAStatus.CLICKED
    AdEvent.AdEventType.COMPLETED -> IMAStatus.COMPLETE
    AdEvent.AdEventType.CUEPOINTS_CHANGED -> IMAStatus.CUEPOINTS_CHANGED
    AdEvent.AdEventType.CONTENT_PAUSE_REQUESTED -> IMAStatus.CONTENT_PAUSE_REQUESTED
    AdEvent.AdEventType.CONTENT_RESUME_REQUESTED -> IMAStatus.CONTENT_RESUME_REQUESTED
    AdEvent.AdEventType.FIRST_QUARTILE -> IMAStatus.FIRST_QUARTILE
    AdEvent.AdEventType.LOG -> IMAStatus.LOG
    AdEvent.AdEventType.AD_BREAK_READY -> IMAStatus.AD_BREAK_READY
    AdEvent.AdEventType.MIDPOINT -> IMAStatus.MIDPOINT
    AdEvent.AdEventType.PAUSE_AD_READY -> IMAStatus.PAUSE_AD_READY
    AdEvent.AdEventType.PAUSED -> IMAStatus.PAUSE
    AdEvent.AdEventType.RESUMED -> IMAStatus.RESUME
    AdEvent.AdEventType.SKIPPABLE_STATE_CHANGED -> IMAStatus.SKIPPABLE_STATE_CHANGED
    AdEvent.AdEventType.SKIPPED -> IMAStatus.SKIPPED
    AdEvent.AdEventType.STARTED -> IMAStatus.STARTED
    AdEvent.AdEventType.TAPPED -> IMAStatus.TAPPED
    AdEvent.AdEventType.ICON_TAPPED -> IMAStatus.ICON_TAPPED
    AdEvent.AdEventType.ICON_FALLBACK_IMAGE_CLOSED -> IMAStatus.ICON_FALLBACK_IMAGE_CLOSED
    AdEvent.AdEventType.THIRD_QUARTILE -> IMAStatus.THIRD_QUARTILE
    AdEvent.AdEventType.LOADED -> IMAStatus.LOADED
    AdEvent.AdEventType.AD_PROGRESS -> IMAStatus.AD_PROGRESS
    AdEvent.AdEventType.AD_BUFFERING -> IMAStatus.AD_BUFFERING
    AdEvent.AdEventType.AD_BREAK_STARTED -> IMAStatus.AD_BREAK_STARTED
    AdEvent.AdEventType.AD_BREAK_ENDED -> IMAStatus.AD_BREAK_ENDED
    AdEvent.AdEventType.AD_PERIOD_STARTED -> IMAStatus.AD_PERIOD_STARTED
    AdEvent.AdEventType.AD_PERIOD_ENDED -> IMAStatus.AD_PERIOD_ENDED
    else -> null
}