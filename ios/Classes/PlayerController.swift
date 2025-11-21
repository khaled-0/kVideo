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
import UIKit

public class PlayerController: NSObject, PlayerControllerApi {

    // ---------------------------------------------------------------------
    // MARK: - Properties
    // ---------------------------------------------------------------------

    let suffix: String
    let messenger: FlutterBinaryMessenger

    var player = AVPlayer()
    var playerItem: AVPlayerItem?
    var playerLayer: AVPlayerLayer

    private var eventHandler: PlayerEventHandler!

    // PiP
    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?

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

        try? setupPiPIfPossible()
    }

    func play(media: Media) throws {
        guard let url = URL(string: media.url) else { return }

        let item = AVPlayerItem(url: url)
        self.playerItem = item

        // TODO: DRM (FairPlay) will go here later if needed

        // Handle start from second
        if let start = media.startFromSecond, start > 0 {
            let cm = CMTime(seconds: Double(start), preferredTimescale: 1000)
            item.seek(to: cm)
        }

        // TODO: IMA Ads equivalent (Google IMA for iOS)

        player.replaceCurrentItem(with: item)
        player.play()
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
        if playerLayer.videoGravity == .resizeAspectFill { return .fill }
        return .fit
    }

    func setFit(fit: BoxFitMode) throws {
        if fit == .fill {
            playerLayer.videoGravity = .resizeAspectFill
        } else {
            playerLayer.videoGravity = .resizeAspect
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Tracks (Video / Audio / Subtitle)
    // ---------------------------------------------------------------------

    func getTracks() throws -> [TrackData] {
        guard let item = player.currentItem else { return [] }

        return item.tracks.map { track in
            TrackData(
                id: track.assetTrack.map { String($0.trackID) },
                type: mapTrackType(track),
                language: track.assetTrack?.languageCode,
                label: track.assetTrack?.extendedLanguageTag,
                bitrate: track.assetTrack.map { Int64($0.estimatedDataRate) },
                width: track.assetTrack.map { Int64($0.naturalSize.width) },
                height: track.assetTrack.map { Int64($0.naturalSize.height) }
            )
        }
    }

    private func mapTrackType(_ track: AVPlayerItemTrack) -> TrackType {
        guard let mediaType = track.assetTrack?.mediaType else {
            return .unknown
        }
        switch mediaType {
        case .video: return .video
        case .audio: return .audio
        case .subtitle, .text: return .subtitle
        default: return .unknown
        }
    }

    func setTrackPreference(track: TrackData?) throws {
        // TODO:
        // AVPlayer does not support manual track selection without AVMutableComposition
        // Implementable if needed — I can add full working code.
    }

    // ---------------------------------------------------------------------
    // MARK: - Playback status
    // ---------------------------------------------------------------------

    func getPlaybackStatus() throws -> PlaybackStatus {
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
            return
        }

        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.startPictureInPicture()
    }

    private func setupPiPIfPossible() throws {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }
        pipPossibleObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.new]
        ) { [weak self] _, _ in
            guard let self = self else { return }
            self.pipController = AVPictureInPictureController(
                playerLayer: self.playerLayer
            )
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Dispose
    // ---------------------------------------------------------------------

    deinit {
        dispose()
    }

    func dispose() {
        pipController?.stopPictureInPicture()
        pipController = nil

        player.pause()
        player.replaceCurrentItem(with: nil)
        eventHandler.removeObservers()
    }

    func initAndroidTextureView() throws -> VideoTextureData {
        return VideoTextureData()
    }

    func isPlayingIMA() throws -> Bool {
        return false  // TODO:
    }

}
