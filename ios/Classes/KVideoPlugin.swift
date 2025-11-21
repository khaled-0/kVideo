import AVFoundation
import Flutter
import UIKit

public class KVideoPlugin: NSObject, FlutterPlugin, PlayerInstance {

    public static var controllers: [String: PlayerController] = [:]

    private var binaryMessenger: FlutterBinaryMessenger!
    private var registrar: FlutterPluginRegistrar!

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = KVideoPlugin()

        instance.binaryMessenger = registrar.messenger()
        instance.registrar = registrar

        PlayerInstanceSetup.setUp(
            binaryMessenger: registrar.messenger(),
            api: instance
        )

        // Cleanup
        controllers.values.forEach { $0.dispose() }
        controllers.removeAll()

        // Register PlatformView
        registrar.register(
            PlayerFactory { id in return controllers[id]! },
            withId: "dev.khaled.kvideo"
        )
    }

    // MARK: - PlayerInstance (Pigeon API)

    public func create(id: String) throws {
        Self.controllers[id]?.dispose()
        Self.controllers[id] = PlayerController(
            suffix: id,
            messenger: binaryMessenger
        )
    }

    public func dispose(id: String) throws {
        Self.controllers[id]?.dispose()
        Self.controllers[id] = nil
    }
}

class PlayerFactory: NSObject, FlutterPlatformViewFactory {

    private let getController: (String) -> PlayerController

    init(getController: @escaping (String) -> PlayerController) {
        self.getController = getController
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let id = args as! String
        let controller = getController(id)

        return PlayerView(controller: controller, frame: frame)
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return PigeonPigeonCodec.shared
    }
}

class PlayerView: UIView, FlutterPlatformView {

    // Override the property to make AVPlayerLayer the view's backing layer.
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    // The associated player object.
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    private var controller: PlayerController

    init(controller: PlayerController, frame: CGRect) {
        self.controller = controller
        super.init(frame: frame)
        self.player = controller.player
        controller.playerLayer = playerLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func view() -> UIView { return self }

    func dispose() {}
}
