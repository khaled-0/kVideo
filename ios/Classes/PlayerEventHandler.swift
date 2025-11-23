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
    private var controller: PlayerController
    private var timeObserver: Any?

    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    private var videoSizeObserver: NSKeyValueObservation?
    private var playbackLikelyObserver: NSKeyValueObservation?

    private var observerAdded = false

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

    deinit { removeObservers() }

    func addObservers() {
        let player = controller.player
        guard let item = player.currentItem else { return }

        player.addObserver(self, forKeyPath: "rate", options: [], context: nil)
        item.addObserver(
            self,
            forKeyPath: "loadedTimeRanges",
            options: [],
            context: nil
        )
        item.addObserver(
            self,
            forKeyPath: "status",
            options: [],
            context: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEndTime(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        observerAdded = true
    }

    func removeObservers() {
        let player = controller.player
        if let observer = timeObserver {
            controller.player.removeTimeObserver(observer)
            timeObserver = nil
        }

        guard observerAdded == true else { return }

        player.removeObserver(self, forKeyPath: "rate")
        player.currentItem?.removeObserver(self, forKeyPath: "status")
        player.currentItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
        NotificationCenter.default.removeObserver(self)
        observerAdded = false
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let item = object as? AVPlayerItem else { return }

        switch keyPath {
        // MARK: - Status
        case "status":
            handleStatusUpdate(item: item)
        case "loadedTimeRanges":
            sendBufferUpdate(item: item)

        default:
            break
        }

        print("Update \(keyPath) \(change?.debugDescription)")
    }

    @objc func itemDidPlayToEndTime(_ notification: Notification) {
        listener.onPlaybackUpdate(status: .finished) { _ in }
    }

    func handleStatusUpdate(item: AVPlayerItem) {

        if item.status == .readyToPlay {
            self.listener.onTracksLoaded(
                tracks: (try? controller.getTracks()) ?? []
            ) { _ in }
        }

        if item.status == .failed {
            self.listener.onPlaybackError(
                error: item.error.debugDescription
            ) { _ in }
        }

        // Notify playback update
        self.listener.onPlaybackUpdate(
            status: (try? controller.getPlaybackStatus()) ?? .finished
        ) { _ in }

    }

    func sendBufferUpdate(item: AVPlayerItem) {
        let currentTime = item.currentTime()

        // Find the buffered range that contains the current time
        guard
            let range = item.loadedTimeRanges.first(where: { range in
                let timeRange = range.timeRangeValue
                return currentTime >= timeRange.start
                    && currentTime <= timeRange.start + timeRange.duration
            })?.timeRangeValue
        else { return }

        // Calculate buffered duration ahead of current time
        let bufferedAhead = CMTimeGetSeconds(
            (range.start + range.duration) - currentTime
        )

        listener.onBufferUpdate(second: Int64(bufferedAhead)) { _ in }
    }

}

// MARK: - Periodic Progress Update
extension PlayerEventHandler {
    func attachPeriodicProgressUpdate() {
        let player = controller.player
        let interval = CMTime(seconds: 1.0, preferredTimescale: 1)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            let posSeconds = Int64(controller.player.currentTime().seconds)
            self.listener.onProgressUpdate(second: posSeconds) { _ in }

            let buffered =
                controller.player.currentItem?.loadedTimeRanges
                .first?.timeRangeValue.end.seconds ?? 0
            self.listener.onBufferUpdate(second: Int64(buffered)) { _ in }
        }
    }
}

// MARK: - Observers for Player Events
extension PlayerEventHandler {
    func attachObservers() {
        let player = controller.player

        // Observe timeControlStatus for playback state (Ready, Playing, Buffering)
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) {
            [weak self] _, _ in
            self?.handlePlayerStatusChange(player)
        }

        // Observe playback rate
        rateObserver = player.observe(\.rate, options: [.new]) {
            [weak self] player, _ in
            self?.handlePlaybackSpeedChange(player)
        }

        // Observe playback duration updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDurationUpdate),
            name: AVPlayerItem.newAccessLogEntryNotification,
            object: controller.player.currentItem
        )

        // Observe playback errors from AVPlayerItem
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackError(notification:)),
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: controller.player.currentItem
        )
    }

    // Handle Playback Speed Changes
    func handlePlaybackSpeedChange(_ player: AVPlayer) {
        self.listener.onPlaybackSpeedUpdate(speed: Double(player.rate)) { _ in }
    }

    // Handle Item Duration Update
    @objc func handleItemDurationUpdate(notification: Notification) {
        guard let item = controller.player.currentItem else { return }
        let duration = item.duration.seconds
        if duration.isFinite {
            self.listener.onDurationUpdate(durationSecond: Int64(duration)) {
                _ in
            }
        }
    }

}

// MARK: - IMA Event (Ads)
extension PlayerEventHandler {
    func onIMAEvent(isAdPlaying: Bool) {
        listener.onIMAStatusChange(showingAd: isAdPlaying) { _ in }
    }
}
