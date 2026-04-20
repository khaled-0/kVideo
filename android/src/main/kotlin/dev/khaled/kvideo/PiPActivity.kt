package dev.khaled.kvideo

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Build.VERSION_CODES
import android.os.Bundle
import android.view.WindowManager
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

    private lateinit var playerView: PlayerView

    // In picture-in-picture mode, clicking the X in the upper right corner will trigger `onStop` first.
    // Clicking the zoom button will not trigger `onStop`.
    var shouldResumeParentActivity = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return finishAndRemoveTask()

        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        playerView = PlayerView(this)
        setContentView(playerView)

        with(playerView) {
            useController = false
            setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            player = controller.player
        }

        if (Build.VERSION.SDK_INT < VERSION_CODES.O) {
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

    override fun onStop() {
        shouldResumeParentActivity = false
        super.onStop()
    }

    override fun finishAndRemoveTask() {
        super.finishAndRemoveTask()
        if (::playerView.isInitialized) playerView.player = null
        PiPManager.notifyPipExited(shouldResumeParentActivity)
    }
}

typealias PiPListener = (mode: PiPMode) -> Unit

object PiPManager {

    private var listener: PiPListener? = null

    fun setListener(listener: PiPListener?) {
        this.listener = listener
    }

    fun notifyPipEnter() {
        listener?.invoke(PiPMode.ACTIVE)
    }

    fun notifyPipExited(shouldResume: Boolean) {
        listener?.invoke(if (shouldResume) PiPMode.INACTIVE else PiPMode.CLOSED)
    }
}