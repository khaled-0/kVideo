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

        // Player Controller
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

        // Download Manager
        let downloader = DownloadManager(messenger: registrar.messenger())
        DownloadManagerApiSetup.setUp(
            binaryMessenger: registrar.messenger(),
            api: downloader
        )

        // Necessary for PiP
        try? AVAudioSession.sharedInstance().setCategory(
            AVAudioSession.Category.playback
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
        return getController(id) as FlutterPlatformView
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return PigeonPigeonCodec.shared
    }
}

protocol PlayerViewDelegate: NSObject {
    func playerViewDidMoveToWindow()
}

class PlayerView: UIView {

    weak var delegate: PlayerViewDelegate?

    // MARK: - Player & Layer
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    var playerLayer: AVPlayerLayer { return layer as! AVPlayerLayer }

    // MARK: - Ad Container
    let adContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        adContainerView.frame = bounds
        adContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(adContainerView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    // MARK: - Layer
    override class var layerClass: AnyClass { return AVPlayerLayer.self }

    // MARK: - Lifecycle
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { delegate?.playerViewDidMoveToWindow() }
    }
}
