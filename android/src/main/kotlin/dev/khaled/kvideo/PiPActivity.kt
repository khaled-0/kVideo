package dev.khaled.kvideo

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView


/// id : String Player Controller Suffix
@OptIn(UnstableApi::class)
class PiPActivity : ComponentActivity() {
    private val controller: PlayerController by lazy {
        KVideoPlugin.controllers[intent.getStringExtra("id")]!!
    }

//    private val actionsReceiver = object : BroadcastReceiver() {
//        override fun onReceive(context: Context?, intent: Intent?) {
//            if (intent?.action == ACTION_BROADCAST_CONTROL) {
//                if (controller.player.isPlaying) controller.player.pause()
//                else controller.player.play()
//            }
//        }
//    }


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return finishAndRemoveTask()

        val playerView = PlayerView(this)
        setContentView(playerView)

        with(playerView) {
            useController = false
            setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            player = controller.player
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION") enterPictureInPictureMode()
        } else {
            val params = PictureInPictureParams.Builder()
            enterPictureInPictureMode(params.build())
        }
    }


    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration
    ) {
        if (isInPictureInPictureMode) PiPManager.notifyPipEnter()
        if (!isInPictureInPictureMode) finishAndRemoveTask()
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    override fun finishAndRemoveTask() {
        super.finishAndRemoveTask()
        PiPManager.notifyPipExited()
    }
}

object PiPManager {
    private val listeners = mutableListOf<(inPip: Boolean) -> Unit>()

    fun addListener(listener: (inPip: Boolean) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (inPip: Boolean) -> Unit) {
        listeners.remove(listener)
    }

    fun notifyPipEnter() {
        listeners.forEach { it.invoke(true) }
    }

    fun notifyPipExited() {
        listeners.forEach { it.invoke(false) }
    }
}
