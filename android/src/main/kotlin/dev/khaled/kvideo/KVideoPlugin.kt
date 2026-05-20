package dev.khaled.kvideo

import android.app.PictureInPictureParams
import android.content.Context
import android.media.MediaDrm
import android.media.MediaDrm.PROPERTY_ALGORITHMS
import android.media.MediaDrm.PROPERTY_DESCRIPTION
import android.media.MediaDrm.PROPERTY_VENDOR
import android.media.MediaDrm.PROPERTY_VERSION
import android.os.Build
import android.os.Build.VERSION_CODES
import android.util.Log
import android.view.View
import androidx.annotation.OptIn
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView.SHOW_BUFFERING_NEVER
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.view.TextureRegistry
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter

class KVideoPlugin : FlutterPlugin, ActivityAware, PlayerInstance, DRMInfoApi,
    PluginRegistry.UserLeaveHintListener, DefaultLifecycleObserver {

    companion object {
        val controllers = mutableMapOf<String, PlayerController>()
    }

    private lateinit var context: Context
    private lateinit var binaryMessenger: BinaryMessenger
    private lateinit var textureRegistry: TextureRegistry

    private var activityPluginBinding: ActivityPluginBinding? = null

    var isParentInPiPMode = false


    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        binaryMessenger = flutterPluginBinding.binaryMessenger
        textureRegistry = flutterPluginBinding.textureRegistry

        PlayerInstance.setUp(binaryMessenger, this)

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "dev.khaled.kvideo", PlayerFactory(
                controllers::getValue
            )
        )

        DownloadManagerApi.setUp(binaryMessenger, KDownloadManager(context, binaryMessenger))
        DRMInfoApi.setUp(binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    override fun create(id: String) {
        controllers[id]?.dispose()
        controllers[id] = PlayerController(context, id, binaryMessenger, textureRegistry)
    }

    override fun dispose(id: String) {
        controllers[id]?.dispose()
        controllers.remove(id)
    }

    override fun getWidevineInfo(): WidevineInfo {
        val mediaDrm = MediaDrm(C.WIDEVINE_UUID)
        // https://stackoverflow.com/questions/24892532/drmmanagerclient-acquiredrminfo-is-failing
        return WidevineInfo(
            vendor = mediaDrm.getPropertyString(PROPERTY_VENDOR),
            version = mediaDrm.getPropertyString(PROPERTY_VERSION),
            description = mediaDrm.getPropertyString(PROPERTY_DESCRIPTION),
            algorithms = mediaDrm.getPropertyString(PROPERTY_ALGORITHMS),
            securityLevel = mediaDrm.getPropertyString("securityLevel"),
            maxHdcpLevel = mediaDrm.getPropertyString("maxHdcpLevel"),
        )
    }

    override fun setAutoEnterPiPMode(value: Boolean) {
        activityPluginBinding?.let {
            if (value) {
                it.addOnUserLeaveHintListener(this)
            } else {
                it.removeOnUserLeaveHintListener(this)
            }
        }

    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityPluginBinding = binding
        FlutterLifecycleAdapter.getActivityLifecycle(binding).addObserver(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityPluginBinding = binding
        FlutterLifecycleAdapter.getActivityLifecycle(binding).addObserver(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityPluginBinding?.let {
            FlutterLifecycleAdapter.getActivityLifecycle(it).removeObserver(this)
        }
        activityPluginBinding = null
    }

    override fun onDetachedFromActivity() {
        activityPluginBinding?.let {
            FlutterLifecycleAdapter.getActivityLifecycle(it).removeObserver(this)
        }
        activityPluginBinding = null
    }


    override fun onUserLeaveHint() {
        val activity = activityPluginBinding?.activity
        if (Build.VERSION.SDK_INT < VERSION_CODES.O) {
            @Suppress("DEPRECATION") activity?.enterPictureInPictureMode()
        } else {
            val params = PictureInPictureParams.Builder()
            activity?.enterPictureInPictureMode(params.build())
        }

        if (activity?.isInPictureInPictureMode ?: false) {
            isParentInPiPMode = true
            controllers.values.forEach {
                it.pipListener.invoke(PiPMode.PARENT)
            }
        }
    }


    override fun onStop(owner: LifecycleOwner) {
        super.onStop(owner)
        if (!isParentInPiPMode) return
        controllers.values.forEach {
            it.pipListener.invoke(PiPMode.CLOSED)
        }

        isParentInPiPMode = false
    }

    override fun onResume(owner: LifecycleOwner) {
        super.onResume(owner)
        if (!isParentInPiPMode) return
        controllers.values.forEach {
            it.pipListener.invoke(PiPMode.INACTIVE)
        }

        isParentInPiPMode = false
    }
}

private class PlayerFactory(
    val getController: (id: String) -> PlayerController
) : PlatformViewFactory(PlayerControllerApi.codec) {
    @Suppress("UNCHECKED_CAST")
    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        return PlayerView(getController(args as String))
    }
}

@OptIn(UnstableApi::class)
class PlayerView(val controller: PlayerController) : PlatformView {
    init {
        with(controller.playerView) {
            useController = false
            setShowBuffering(SHOW_BUFFERING_NEVER)
        }
    }

    override fun getView(): View = controller.playerView

    override fun dispose() {}
}