package dev.khaled.kvideo

import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Player.STATE_READY
import androidx.media3.common.Timeline
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
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
        val handler = android.os.Handler(player.applicationLooper)
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
        listener.onPlaybackError(error.localizedMessage ?: error.toString()) {}
    }

    override fun onAdEvent(event: AdEvent) {
        val isAdPlaying = when (event.type) {
            AdEvent.AdEventType.ALL_ADS_COMPLETED, AdEvent.AdEventType.COMPLETED, AdEvent.AdEventType.SKIPPED, AdEvent.AdEventType.CONTENT_RESUME_REQUESTED -> false
            AdEvent.AdEventType.STARTED, AdEvent.AdEventType.CONTENT_PAUSE_REQUESTED -> true
            AdEvent.AdEventType.AD_PROGRESS -> true
            else -> null
        }

        listener.onIMAStatusChange(isAdPlaying ?: playerController.isPlayingIMA()) {}
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        super.onVideoSizeChanged(videoSize)
        listener.onVideoSizeUpdate(videoSize.width.toLong(), videoSize.height.toLong()) {}
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



