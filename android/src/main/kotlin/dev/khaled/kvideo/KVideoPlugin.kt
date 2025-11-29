package dev.khaled.kvideo

import android.content.Context
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView.SHOW_BUFFERING_NEVER
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.view.TextureRegistry


class KVideoPlugin : FlutterPlugin, PlayerInstance {

    companion object {
        val controllers = mutableMapOf<String, PlayerController>()
    }

    private lateinit var context: Context
    private lateinit var binaryMessenger: BinaryMessenger
    private lateinit var textureRegistry: TextureRegistry


    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        binaryMessenger = flutterPluginBinding.binaryMessenger
        textureRegistry = flutterPluginBinding.textureRegistry

        PlayerInstance.setUp(binaryMessenger, this)
        controllers.keys.forEach { dispose(it) }
        controllers.clear()

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "dev.khaled.kvideo", PlayerFactory(
                controllers::getValue
            )
        )

        DownloadManagerApi.setUp(binaryMessenger, KDownloadManager(context, binaryMessenger))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        controllers.keys.forEach { dispose(it) }
        controllers.clear()
    }

    override fun create(id: String) {
        controllers[id]?.dispose()
        controllers[id] = PlayerController(context, id, binaryMessenger, textureRegistry)
    }

    override fun dispose(id: String) {
        controllers[id]?.dispose()
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