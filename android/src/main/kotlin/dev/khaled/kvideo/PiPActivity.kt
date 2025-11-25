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
//            ContextCompat.registerReceiver(
//                this,
//                actionsReceiver,
//                IntentFilter(ACTION_BROADCAST_CONTROL),
//                ContextCompat.RECEIVER_NOT_EXPORTED
//            )

//            val action = RemoteAction(
//                Icon.createWithResource(
//                    this, if (controller.player.isPlaying) android.R.drawable.ic_media_pause
//                    else android.R.drawable.ic_media_play
//                ),
//                "Play/Pause",
//                "Play or Pause the currently playing content",
//                PendingIntent.getBroadcast(
//                    this,
//                    0,
//                    Intent(ACTION_BROADCAST_CONTROL),
//                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
//                )
//            )

//            params.setActions(listOf(action))
            enterPictureInPictureMode(params.build())

        }
    }


    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration
    ) {
        if (!isInPictureInPictureMode) finishAndRemoveTask()
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    override fun finishAndRemoveTask() {
        super.finishAndRemoveTask()
        PiPManager.notifyPipExited()
//        unregisterReceiver(actionsReceiver)
    }

//    companion object {
//        const val ACTION_BROADCAST_CONTROL = "ACTION_BROADCAST_CONTROL"
//    }
}

object PiPManager {
    private val listeners = mutableListOf<() -> Unit>()

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    fun notifyPipExited() {
        listeners.forEach { it.invoke() }
    }
}
