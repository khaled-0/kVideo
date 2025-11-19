package dev.khaled.kvideo

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView

/// id : String Player Controller Suffix
@OptIn(UnstableApi::class)
class PlayerActivity : ComponentActivity() {
    private val controller: PlayerController by lazy {
        KVideoPlugin.controllers[intent.getStringExtra("id")]!!
    }

    private val player: ExoPlayer by lazy { controller.player }
    private val playerView: PlayerView by lazy { controller.playerView }


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(playerView)

        with(playerView) {
            keepScreenOn = true
            useController = true
            setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
        }
    }


    override fun onPause() {
        super.onPause()
        player.pause()
    }


    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        return playerView.dispatchKeyEvent(event) || super.dispatchKeyEvent(event)
    }
}