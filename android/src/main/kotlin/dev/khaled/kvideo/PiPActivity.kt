package dev.khaled.kvideo

import android.app.ActivityManager
import android.app.BackgroundServiceStartNotAllowedException
import android.app.PictureInPictureParams
import android.app.Service
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Binder
import android.os.Build
import android.os.Build.VERSION_CODES
import android.os.Bundle
import android.os.IBinder
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.media3.common.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView


/// id : String Player Controller Suffix
@OptIn(UnstableApi::class)
class PiPActivity : ComponentActivity(), ServiceConnection {
    companion object {
        const val ACTION_STOP_PIP = "ACTION_STOP_PIP"
    }

    private lateinit var playerView: PlayerView

    // In picture-in-picture mode, clicking the X in the upper right corner will trigger `onStop` first.
    // Clicking the zoom button will not trigger `onStop`.
    var shouldResumeParentActivity = true

    var isParentDestroyed = false

    var isServiceBound = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return finishAndRemoveTask()

        if (!intent.hasExtra("id") || !KVideoPlugin.controllers.contains(intent.getStringExtra("id"))) {
            return finishAndRemoveTask()
        }

        if (Build.VERSION.SDK_INT >= VERSION_CODES.Q && !isServiceBound) {
            try {
                val serviceIntent = Intent(applicationContext, Android12PiPService::class.java)
                startService(serviceIntent)
                bindService(serviceIntent, this, BIND_AUTO_CREATE)
            } catch (_: Exception) {
            }
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        playerView = PlayerView(this)
        setContentView(playerView)

        with(playerView) {
            useController = false
            setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            player = KVideoPlugin.controllers[intent.getStringExtra("id")]!!.player
        }

        if (Build.VERSION.SDK_INT < VERSION_CODES.O) {
            @Suppress("DEPRECATION") enterPictureInPictureMode()
        } else {
            val params = PictureInPictureParams.Builder().setActions(emptyList())
            enterPictureInPictureMode(params.build())
        }

        PiPManager.registerPlayerChangeListener { id ->
            if (id == null) {
                isParentDestroyed = true
                return@registerPlayerChangeListener finishAndRemoveTask()
            }

            if (playerView.player == KVideoPlugin.controllers[id]!!.player) return@registerPlayerChangeListener
            playerView.player = KVideoPlugin.controllers[id]!!.player
        }
    }


    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration
    ) {
        if (isInPictureInPictureMode) PiPManager.notifyPipEnter()
        if (!isInPictureInPictureMode) signalPiPToClose()
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
    }


    override fun onStop() {
        shouldResumeParentActivity = false
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        if (intent.action == ACTION_STOP_PIP) finishAndRemoveTask()
    }

    // Due to the foreground service startup restriction in Android 12, if the activity interface is closed
    // too early after returning from picture-in-picture mode, the app cannot be launched normally.
    private fun signalPiPToClose() {
        if (!shouldResumeParentActivity) return finishAndRemoveTask()

        if (isDestroyed || isFinishing) return
        val intent = Intent(this, this.javaClass)
        intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        intent.setAction(ACTION_STOP_PIP)
        startActivity(intent)
    }

    override fun finishAndRemoveTask() {
        super.finishAndRemoveTask()
        if (::playerView.isInitialized) playerView.player = null
        PiPManager.notifyPipExited(shouldResumeParentActivity)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (Build.VERSION.SDK_INT >= VERSION_CODES.Q && isServiceBound) {
            unbindService(this)
            val serviceIntent = Intent(applicationContext, Android12PiPService::class.java)
            stopService(serviceIntent)
        }

        if (!isParentDestroyed) {
            // iterate app tasks available and navigate to launcher task (browse task)
            val activityManager = baseContext.getSystemService(ACTIVITY_SERVICE) as ActivityManager
            val appTasks = activityManager.appTasks
            for (task in appTasks) {
                val baseIntent = task.taskInfo?.baseIntent
                val categories = baseIntent?.categories
                if (categories != null && categories.contains(Intent.CATEGORY_LAUNCHER)) {
                    task.moveToFront()
                    return
                }
            }
        }
    }


    override fun onServiceConnected(p0: ComponentName?, p1: IBinder?) {
        isServiceBound = true
    }

    override fun onServiceDisconnected(p0: ComponentName?) {
        isServiceBound = false
    }

}

typealias PiPListener = (mode: PiPMode) -> Unit
private typealias PiPUpdatePlayerListener = (String?) -> Unit

object PiPManager {
    private var isActive = false

    private var listener: PiPListener? = null
    private var playerUpdateListener: PiPUpdatePlayerListener? = null

    fun setListener(listener: PiPListener?) {
        this.listener = listener
        isActive = true
    }

    fun registerPlayerChangeListener(listener: PiPUpdatePlayerListener) {
        playerUpdateListener = listener
    }

    fun notifyPipEnter() {
        isActive = true
        listener?.invoke(PiPMode.ACTIVE)
    }

    fun notifyPipExited(shouldResume: Boolean) {
        isActive = false
        listener?.invoke(if (shouldResume) PiPMode.INACTIVE else PiPMode.CLOSED)
    }

    fun isPiPActive(): Boolean = isActive
    fun updatePlayer(suffix: String) {
        playerUpdateListener?.invoke(suffix)
    }

    fun stopPiPActivity() = playerUpdateListener?.invoke(null)
}

/**
 * To solve the problem that starting picture-in-picture multiple times is considered as background startup,
 * resulting in the inability to start.
 * This problem occurs on Android 12 and is currently only found on MIUI's Android 12.
 */
class Android12PiPService : Service() {
    override fun onBind(intent: Intent?): IBinder = Android12BridgeServiceBinder()
    class Android12BridgeServiceBinder : Binder()
}