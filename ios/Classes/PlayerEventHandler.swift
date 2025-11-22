//
//  PlayerEventHandler.swift
//  Pods
//
//  Created by Khaled on 21/11/25.
//

import AVFoundation
import Flutter
import Foundation
import UIKit

class PlayerEventHandler: NSObject {

    private let listener: PlayerEventListener
    private weak var controller: PlayerController?
    private var timeObserver: Any?

    private var statusObserver: NSKeyValueObservation?
    private var playbackLikelyObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    private var videoSizeObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    init(messenger: FlutterBinaryMessenger, controller: PlayerController) {
        self.listener = PlayerEventListener(
            binaryMessenger: messenger,
            messageChannelSuffix: controller.suffix
        )
        self.controller = controller

        super.init()

        attachObservers()
        attachPeriodicProgressUpdate()
    }

    deinit {
        removeObservers()
    }
}

extension PlayerEventHandler {
    func attachPeriodicProgressUpdate() {
        guard let player = controller?.player else { return }

        let interval = CMTime(seconds: 1.0, preferredTimescale: 1)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let controller = self.controller else {
                return
            }

            let posSeconds = Int64(controller.player.currentTime().seconds)
            self.listener.onProgressUpdate(second: posSeconds) { _ in }

            let buffered =
                controller.player.currentItem?.loadedTimeRanges
                .first?.timeRangeValue.end.seconds ?? 0
            self.listener.onBufferUpdate(second: Int64(buffered)) { _ in }
        }
    }
}

extension PlayerEventHandler {
    func attachObservers() {
        guard let controller = controller else { return }
        let player = controller.player

        // Ready / Playing / Buffering
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) {
            [weak self] _, _ in
            guard let self = self, let controller = self.controller else {
                return
            }
            if player.status == .readyToPlay {
                disableSubtitles(for: player.currentItem!)
                self.listener.onTracksLoaded(
                    tracks: (try? controller.getTracks()) ?? []
                ) { _ in }
            }

            self.listener.onPlaybackUpdate(
                status: (try? controller.getPlaybackStatus()) ?? .finished
            ) { _ in }
        }

        // Playback speed
        rateObserver = player.observe(\.rate, options: [.new]) {
            [weak self] player, _ in
            guard let self = self else { return }
            self.listener.onPlaybackSpeedUpdate(speed: Double(player.rate)) {
                _ in
            }
        }

        // Duration update (similar to onMediaItemTransition)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let item = controller.player.currentItem else { return }
            let duration = item.duration.seconds
            if duration.isFinite {
                self?.listener.onDurationUpdate(durationSecond: Int64(duration))
                { _ in }
            }
        }

        // Playback errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: controller.player.currentItem,
            queue: .main
        ) { [weak self] notification in
            let msg =
                (notification.userInfo?[
                    AVPlayerItemFailedToPlayToEndTimeErrorKey
                ] as? NSError)?.localizedDescription ?? "unknown error"
            self?.listener.onPlaybackError(error: msg) { _ in }
        }
    }
}

extension PlayerEventHandler {
    func onIMAEvent(isAdPlaying: Bool) {
        listener.onIMAStatusChange(showingAd: isAdPlaying) { _ in }
    }
}

extension PlayerEventHandler {
    func removeObservers() {
        if let observer = timeObserver {
            controller?.player.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver = nil
        videoSizeObserver = nil
        rateObserver = nil
        playbackLikelyObserver = nil
        errorObserver = nil

        NotificationCenter.default.removeObserver(self)
    }
}

extension PlayerEventHandler {
    private func disableSubtitles(for item: AVPlayerItem) {
        let asset = item.asset
        if let group = asset.mediaSelectionGroup(
            forMediaCharacteristic: .legible
        ) {
            item.select(nil, in: group)
        }
    }
}
