package dev.khaled.kvideo

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.SurfaceView
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.lifecycle.Lifecycle
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView


/// id : String Player Controller Suffix
@OptIn(UnstableApi::class)
class PiPActivity : ComponentActivity() {
    private val controller: PlayerController by lazy {
        KVideoPlugin.controllers[intent.getStringExtra("id")]!!
    }


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return finishActivity(-1)

        if (controller.playerView.parent != null) {
            (controller.playerView.parent as ViewGroup).removeView(controller.playerView)
        }

        controller.playerView.player = controller.player
        controller.player.setVideoSurfaceView(controller.playerView.videoSurfaceView as SurfaceView)
        setContentView(controller.playerView)

        with(controller.playerView) {
            useController = false
            setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            enterPictureInPictureMode()
        } else {
            val params = PictureInPictureParams.Builder()
            enterPictureInPictureMode(params.build())
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration
    ) {
        if(!isInPictureInPictureMode) finishAndRemoveTask()
        Log.d("PIPPPPP", lifecycle.currentState.name)
        if (lifecycle.currentState == Lifecycle.State.CREATED) {
            //finishAndRemoveTask()
            //when user click on Close button of PIP this will trigger, do what you want here
        } else if (lifecycle.currentState == Lifecycle.State.STARTED) {
           // finishAndRemoveTask()
        }
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    override fun finishAndRemoveTask() {
        super.finishAndRemoveTask()
        PipManager.notifyPipExited()
    }
}

object PipManager {

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
