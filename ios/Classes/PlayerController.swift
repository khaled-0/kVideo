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

public class PlayerController: NSObject, FlutterPlatformView,
    PlayerViewDelegate, AVPictureInPictureControllerDelegate,
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
    var tracks: [TrackData] = []

    var playerView: PlayerView = PlayerView(frame: CGRect.zero)
    public func view() -> UIView { return playerView }

    private var pipController: AVPictureInPictureController?

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

        pipController = AVPictureInPictureController(
            playerLayer: playerView.playerLayer
        )
        pipController?.delegate = self
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

        fetchAllTrackData(for: url) { tracks in
            self.tracks = tracks
        }
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

    func playerViewDidMoveToWindow() {

    }

}

extension PlayerController {
    func fetchAllTrackData(
        for url: URL,
        completion: @escaping ([TrackData]) -> Void
    ) {
        let asset = AVURLAsset(url: url)

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

            // Subtitle tracks
            if let subtitleGroup = asset.mediaSelectionGroup(
                forMediaCharacteristic: .legible
            ) {
                for option in subtitleGroup.options {
                    var data = TrackData()
                    data.type = .subtitle
                    data.language = option.locale?.languageCode
                    data.label = option.displayName
                    trackDataList.append(data)
                }
            }

            // Video tracks (variants)
            if let variants = asset.variants as? [AVAssetVariant] {
                for variant in variants {
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
            }

            completion(trackDataList)
        }
    }
}
