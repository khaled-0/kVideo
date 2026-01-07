//
//  PlayerController.swift
//  Pods
//
//  Created by Khaled on 21/11/25.
//

import AVFoundation
import AVKit
import Flutter
import Foundation
import GoogleInteractiveMediaAds
import UIKit

public class PlayerController: NSObject, FlutterPlatformView,
    PlayerViewDelegate, AVPictureInPictureControllerDelegate,
    IMAAdsLoaderDelegate, IMAAdsManagerDelegate,
    PlayerControllerApi
{

    // ---------------------------------------------------------------------
    // MARK: - Properties
    // ---------------------------------------------------------------------

    let suffix: String
    let messenger: FlutterBinaryMessenger

    var player = AVPlayer()
    private var eventHandler: PlayerEventHandler!
    var playerItem: AVPlayerItem?
    private var drmLoaderDelegate: DRMLoaderDelegate?
    var tracks: [TrackData] = []

    var playerView: PlayerView = PlayerView(frame: .zero)
    public func view() -> UIView { return playerView }

    private var pipController: AVPictureInPictureController?

    // ---------------------------------------------------------------------
    // MARK: - IMA
    // ---------------------------------------------------------------------
    let adsLoader = {
        let settings = IMASettings()
        settings.enableBackgroundPlayback = true
        return IMAAdsLoader(settings: settings)
    }()
    private var adsManager: IMAAdsManager?
    private var imaAdTagUrl: String?
    private var adDisplayContainer: IMAAdDisplayContainer?
    private var imaPiPProxy: IMAPictureInPictureProxy?
    private lazy var imaAVPlayer = IMAAVPlayerVideoDisplay(avPlayer: player)

    // ---------------------------------------------------------------------
    // MARK: - Init
    // ---------------------------------------------------------------------

    init(
        suffix: String,
        messenger: FlutterBinaryMessenger
    ) {
        self.suffix = suffix
        self.messenger = messenger
        super.init()

        playerView.player = player
        playerView.delegate = self
        eventHandler = PlayerEventHandler(
            messenger: messenger,
            controller: self
        )
        PlayerControllerApiSetup.setUp(
            binaryMessenger: messenger,
            api: self,
            messageChannelSuffix: suffix
        )
    }

    // ---------------------------------------------------------------------
    // MARK: - API (from Pigeon)
    // ---------------------------------------------------------------------

    func initialize(configuration: PlayerConfiguration?) throws {
        // TODO: AVPlayer has different buffering & seek config than ExoPlayer
        // Apply some analogous configuration where applicable
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.automaticallyWaitsToMinimizeStalling = true

        pipController = AVPictureInPictureController(
            playerLayer: playerView.playerLayer
        )
        pipController?.delegate = self

        if configuration?.initializeIMA != false {
            adsLoader.delegate = self
            imaPiPProxy = IMAPictureInPictureProxy(
                avPictureInPictureControllerDelegate: self
            )
            pipController?.delegate = imaPiPProxy
            adDisplayContainer = IMAAdDisplayContainer(
                adContainer: playerView.adContainerView,
                viewController: getRootViewController(),
                companionSlots: nil
            )
        }
    }

    func play(media: Media) throws {
        guard let url = URL(string: media.url) else {
            print("Unsupported url: \(media.url)")
            return
        }

        var asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": media.headers ?? [:]]
        )

        self.drmLoaderDelegate = nil

        if url.scheme == "file" {
            if let file = DownloadManager.session.asset(location: url) {
                print("Playing file \(url.absoluteString)")
                asset = file
            }
        } else {
            if let licenseUrl = media.drmLicenseUrl,
                let certificate = media.drmCertificate,
                let license = URL(string: licenseUrl)
            {
                self.drmLoaderDelegate = DRMLoaderDelegate(
                    certificate: certificate,
                    license: license
                )
                asset.resourceLoader.setDelegate(
                    self.drmLoaderDelegate,
                    queue: DispatchQueue(label: "drm", qos: .default)
                )
            }
        }

        self.imaAdTagUrl = nil
        if media.imaTagUrl != nil {
            self.imaAdTagUrl = media.imaTagUrl
        }

        asset.resourceLoader.preloadsEligibleContentKeys = true
        self.playerItem = AVPlayerItem(asset: asset)
        self.tracks = []

        // Handle start from second
        if let start = media.startFromSecond, start > 0 {
            let cm = CMTime(seconds: Double(start), preferredTimescale: 1000)
            self.playerItem!.seek(to: cm, completionHandler: nil)
        }

        player.replaceCurrentItem(with: self.playerItem)
        self.player.play()

        asset.fetchAllTrackData { tracks in
            self.tracks = tracks
        }

        if self.imaAdTagUrl != nil { requestAds() }
    }

    func stop() throws { player.pause() }
    func pause() throws { player.pause() }
    func resume() throws { player.play() }
    func seekTo(positionMs: Int64) throws {
        let cm = CMTime(value: positionMs, timescale: 1000)
        player.seek(to: cm)
    }
    func seekForward() throws {
        let p = player.currentTime()
        let cm = CMTime(seconds: p.seconds + 10, preferredTimescale: 1000)
        player.seek(to: cm)
    }
    func seekBack() throws {
        let p = player.currentTime()
        let cm = CMTime(
            seconds: max(0, p.seconds - 10),
            preferredTimescale: 1000
        )
        player.seek(to: cm)
    }

    func setPlaybackSpeed(speed: Double) throws {
        player.rate = Float(speed)
    }

    func getProgressSecond() throws -> Int64 {
        return Int64(player.currentTime().seconds)
    }

    // ---------------------------------------------------------------------
    // MARK: - Fit / Resize
    // ---------------------------------------------------------------------

    func getFit() throws -> BoxFitMode {
        if playerView.playerLayer.videoGravity == .resizeAspectFill {
            return .fill
        }
        return .fit
    }

    func setFit(fit: BoxFitMode) throws {
        if fit == .fill {
            playerView.playerLayer.videoGravity = .resizeAspectFill
        } else {
            playerView.playerLayer.videoGravity = .resizeAspect
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Tracks (Video / Audio / Subtitle)
    // ---------------------------------------------------------------------

    func getTracks() throws -> [TrackData] { return tracks }

    func setTrackPreference(track: TrackData?) throws {
        guard let playerItem = player.currentItem else { return }

        guard let trackData = track else {
            playerItem.preferredPeakBitRate = 0
            playerItem.preferredMaximumResolution = .zero
            return
        }

        if trackData.type == .audio {
            if let audioGroup = playerItem.asset.mediaSelectionGroup(
                forMediaCharacteristic: .audible
            ) {
                // Find the audio option by language or label
                if let option = audioGroup.options.first(where: {
                    $0.locale?.languageCode == trackData.language
                        || $0.displayName == trackData.label
                }) {
                    playerItem.select(option, in: audioGroup)
                } else {
                    playerItem.select(nil, in: audioGroup)
                }
            }
        }

        if trackData.type == .video {
            if let bitrate = trackData.bitrate {
                playerItem.preferredPeakBitRate = Double(bitrate)
            }

            if let width = trackData.width, let height = trackData.height {
                playerItem.preferredMaximumResolution = CGSize(
                    width: Double(width),
                    height: Double(height)
                )
            }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Playback status
    // ---------------------------------------------------------------------

    func getPlaybackStatus() throws -> PlaybackStatus {
        if player.currentItem?.status == .failed { return .error }

        if player.status == .failed { return .error }
        if player.status == .unknown { return .finished }

        if player.timeControlStatus == .playing {
            return .playing
        }

        if player.timeControlStatus == .paused {
            return .paused
        }

        return .preparing
    }

    func getPlaybackSpeed() throws -> Double {
        return Double(player.rate)
    }

    // ---------------------------------------------------------------------
    // MARK: - PiP
    // ---------------------------------------------------------------------

    func enterPiPMode() throws {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return print("Picture In Picture is unsupported")
        }
        pipController?.startPictureInPicture()
    }

    // ---------------------------------------------------------------------
    // MARK: - Dispose
    // ---------------------------------------------------------------------

    deinit { dispose() }

    func dispose() {
        pipController?.stopPictureInPicture()
        pipController = nil
        drmLoaderDelegate = nil

        player.pause()
        player.replaceCurrentItem(with: nil)
        eventHandler.removeObservers()
        eventHandler = nil

        // Clean up IMA SDK
        adsManager?.destroy()
        adsManager = nil

        adsLoader.delegate = nil
        self.adDisplayContainer = nil
        self.playerView.adContainerView.removeFromSuperview()
    }

    func initAndroidTextureView() throws -> VideoTextureData {
        return VideoTextureData()
    }

    func isPlayingIMA() throws -> Bool {
        return adsManager?.adPlaybackInfo.isPlaying == true
    }

    func playerViewDidMoveToWindow() {
        requestAds()
    }

}

extension AVURLAsset {
    func fetchAllTrackData(
        completion: @escaping ([TrackData]) -> Void
    ) {
        let asset = self
        let keys = [
            "availableMediaCharacteristicsWithMediaSelectionOptions",
            "variants",
        ]

        asset.loadValuesAsynchronously(forKeys: keys) {
            var trackDataList: [TrackData] = []

            // Audio tracks
            if let audioGroup = asset.mediaSelectionGroup(
                forMediaCharacteristic: .audible
            ) {
                for option in audioGroup.options {
                    var data = TrackData()
                    data.type = .audio
                    data.language = option.locale?.languageCode
                    data.label = option.displayName
                    trackDataList.append(data)
                }
            }

            // Video tracks (variants)

            for variant in asset.variants {
                guard let videoAttributes = variant.videoAttributes else {
                    continue
                }

                var data = TrackData()
                data.type = .video
                data.bitrate = Int64(variant.peakBitRate ?? 0)
                data.width = Int64(videoAttributes.presentationSize.width)
                data.height = Int64(videoAttributes.presentationSize.height)
                trackDataList.append(data)
            }

            completion(trackDataList)
        }
    }
}

// MARK: - IMA

extension PlayerController {
    private func requestAds() {
        guard imaAdTagUrl != nil else { return }
        guard adsLoader.delegate != nil else { return }

        adsManager?.destroy()
        adsLoader.contentComplete()
        adsManager = nil

        let request = IMAAdsRequest(
            adTagUrl: imaAdTagUrl!,
            adDisplayContainer: adDisplayContainer!,
            avPlayerVideoDisplay: imaAVPlayer,
            pictureInPictureProxy: imaPiPProxy!,
            userContext: self.playerItem
        )

        self.adsLoader.requestAds(with: request)
        self.imaAdTagUrl = nil
    }

    public func adsLoader(
        _ loader: IMAAdsLoader,
        adsLoadedWith adsLoadedData: IMAAdsLoadedData
    ) {
        // Grab the instance of the IMAAdsManager and set ourselves as the delegate.
        self.adsManager = adsLoadedData.adsManager
        adsManager?.delegate = self

        // Create ads rendering settings and tell the SDK to use the in-app browser.
        let adsRenderingSettings = IMAAdsRenderingSettings()
        adsRenderingSettings.enablePreloading = true

        // Initialize the ads manager.
        adsManager?.initialize(with: adsRenderingSettings)
    }

    func getRootViewController() -> UIViewController? {
        return UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

// MARK: - IMAAdsManagerDelegate
extension PlayerController {
    public func adsManager(
        _ adsManager: IMAAdsManager,
        didReceive event: IMAAdEvent
    ) {
        if player.currentItem == nil { return }

        print("AdsManager Event:", IMAAdEventTypeToString(event.type))

        switch event.type {
        case .LOADED:
            if pipController?.isPictureInPictureActive != true {
                adsManager.start()
            }

        case .STARTED:
            eventHandler.listener.onIMAStatusChange(showingAd: true) { _ in }

        case .SKIPPED, .COMPLETE, .ALL_ADS_COMPLETED:
            eventHandler.listener.onIMAStatusChange(showingAd: false) { _ in }

        default:
            break
        }
    }

    public func adsManager(
        _ adsManager: IMAAdsManager,
        didReceive error: IMAAdError
    ) {
        print("AdsManager error:", error.message ?? error)
    }

    public func adsLoader(
        _ loader: IMAAdsLoader,
        failedWith adErrorData: IMAAdLoadingErrorData
    ) {
        if let message = adErrorData.adError.message {
            print("Error loading ads: \(message)")
        }
        player.play()
    }

    public func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
        if player.currentItem == nil { return }
        eventHandler.listener.onIMAStatusChange(showingAd: true) { _ in }
        player.pause()
    }

    public func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
        if player.currentItem == nil { return }
        eventHandler.listener.onIMAStatusChange(showingAd: false) { _ in }
        player.play()
    }

    func IMAAdEventTypeToString(_ type: IMAAdEventType) -> String {
        switch type {
        case .AD_BREAK_READY:
            return "kIMAAdEvent_AD_BREAK_READY"
        case .AD_BREAK_FETCH_ERROR:
            return "kIMAAdEvent_AD_BREAK_FETCH_ERROR"
        case .AD_BREAK_ENDED:
            return "kIMAAdEvent_AD_BREAK_ENDED"
        case .AD_BREAK_STARTED:
            return "kIMAAdEvent_AD_BREAK_STARTED"
        case .AD_PERIOD_ENDED:
            return "kIMAAdEvent_AD_PERIOD_ENDED"
        case .AD_PERIOD_STARTED:
            return "kIMAAdEvent_AD_PERIOD_STARTED"
        case .ALL_ADS_COMPLETED:
            return "kIMAAdEvent_ALL_ADS_COMPLETED"
        case .CLICKED:
            return "kIMAAdEvent_CLICKED"
        case .COMPLETE:
            return "kIMAAdEvent_COMPLETE"
        case .CUEPOINTS_CHANGED:
            return "kIMAAdEvent_CUEPOINTS_CHANGED"
        case .ICON_FALLBACK_IMAGE_CLOSED:
            return "kIMAAdEvent_ICON_FALLBACK_IMAGE_CLOSED"
        case .ICON_TAPPED:
            return "kIMAAdEvent_ICON_TAPPED"
        case .FIRST_QUARTILE:
            return "kIMAAdEvent_FIRST_QUARTILE"
        case .LOADED:
            return "kIMAAdEvent_LOADED"
        case .LOG:
            return "kIMAAdEvent_LOG"
        case .MIDPOINT:
            return "kIMAAdEvent_MIDPOINT"
        case .PAUSE:
            return "kIMAAdEvent_PAUSE"
        case .RESUME:
            return "kIMAAdEvent_RESUME"
        case .SKIPPED:
            return "kIMAAdEvent_SKIPPED"
        case .STARTED:
            return "kIMAAdEvent_STARTED"
        case .STREAM_LOADED:
            return "kIMAAdEvent_STREAM_LOADED"
        case .STREAM_STARTED:
            return "kIMAAdEvent_STREAM_STARTED"
        case .TAPPED:
            return "kIMAAdEvent_TAPPED"
        case .THIRD_QUARTILE:
            return "kIMAAdEvent_THIRD_QUARTILE"
        case .SHOW_AD_UI:
            return "kIMAAdEvent_SHOW_AD_UI"
        case .HIDE_AD_UI:
            return "kIMAAdEvent_HIDE_AD_UI"
        @unknown default:
            return "Unknown (\(type.rawValue))"
        }
    }
}

// MARK: - PiP Event Listener
extension PlayerController {
    public func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        self.eventHandler.listener.onPiPModeChange(inPip: true) { _ in }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        self.eventHandler.listener.onPiPModeChange(inPip: false) { _ in }
    }
}
