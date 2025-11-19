package dev.khaled.kvideo

import PlayerEventListener
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import com.google.ads.interactivemedia.v3.api.AdEvent
import io.flutter.plugin.common.BinaryMessenger


@UnstableApi
class PlayerEventHandler(
    binaryMessenger: BinaryMessenger, suffix: String, playerController: PlayerController
) : Player.Listener, AdEvent.AdEventListener {
    private val listener: PlayerEventListener = PlayerEventListener(binaryMessenger, suffix)
    private val player = playerController.player

    init {
        /// Send Progress Updates Every Seconds
        val handler = android.os.Handler(player.applicationLooper)
        handler.post(object : Runnable {
            override fun run() {
                if (player.isReleased) return
                handler.postDelayed(this, 1000)

                if (!player.isPlaying) return
//                listener.onProgress(
//                    player.currentPosition / 1000,
//                    player.bufferedPosition / 1000,
//                ) {}
//
//                listener.onDurationChange(player.duration / 1000) {}
            }
        })
    }

    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
        player.currentMediaItem?.mediaMetadata?.extras?.getLong("startFromSecond", 0)?.let {
            player.seekTo(it * 1000)
        }
    }

    override fun onIsLoadingChanged(isLoading: Boolean) {
        super.onIsLoadingChanged(isLoading)
//        listener.onLoadingUpdate(isLoading) {}
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        super.onIsPlayingChanged(isPlaying)
//        listener.onPlaybackUpdate(isPlaying) {}
    }


    override fun onPlaybackStateChanged(state: Int) {
        super.onPlaybackStateChanged(state)
        if (state == Player.STATE_READY) {
//            listener.onPlaybackUpdate(player.isPlaying) {}
        }
//        if (state == Player.STATE_ENDED) listener.onPlaybackFinish {}
    }


    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        super.onPositionDiscontinuity(oldPosition, newPosition, reason)
//        listener.onProgress(newPosition.positionMs / 1000, player.bufferedPosition / 1000) {}
    }


    override fun onPlayerError(error: PlaybackException) {
        super.onPlayerError(error)
        listener.onPlaybackError(error.localizedMessage ?: error.toString()) {}
    }

    override fun onAdEvent(event: AdEvent) {
        when (event.type) {
            AdEvent.AdEventType.ALL_ADS_COMPLETED,
            AdEvent.AdEventType.COMPLETED,
            AdEvent.AdEventType.SKIPPED,
            AdEvent.AdEventType.CONTENT_RESUME_REQUESTED -> listener.onIMAStatusChange(
                false
            ) {}

            AdEvent.AdEventType.STARTED,
            AdEvent.AdEventType.CONTENT_PAUSE_REQUESTED -> listener.onIMAStatusChange(
                true
            ) {}

            AdEvent.AdEventType.AD_PROGRESS -> listener.onIMAStatusChange(true) {}

            else -> null
        }
    }
}