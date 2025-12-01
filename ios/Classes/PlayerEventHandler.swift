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

        player.addObserver(
            self,
            forKeyPath: "timeControlStatus",
            options: [],
            context: nil
        )
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
        attachObservers()
    }

    func removeObservers() {
        let player = controller.player
        if let timeObserver = timeObserver {
            controller.player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        if let statusObserver = statusObserver {
            controller.player.removeTimeObserver(statusObserver)
            self.statusObserver = nil
        }

        
        guard observerAdded == true else { return }

        player.removeObserver(self, forKeyPath: "timeControlStatus")
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
        case "status", "timeControlStatus":
            handleStatusUpdate(item: item)
        case "loadedTimeRanges":
            sendBufferUpdate(item: item)
        case "rate":
            sendSpeedUpdate()

        default:
            break
        }

    }

    @objc func itemDidPlayToEndTime(_ notification: Notification) {
        listener.onPlaybackUpdate(status: .finished) { _ in }
    }

    func handleStatusUpdate(item: AVPlayerItem) {
        if item.status == .readyToPlay {
            disableBuiltInSubtitle()
            self.listener.onTracksLoaded(
                tracks: (try? controller.getTracks()) ?? []
            ) { _ in }
        }

        if item.status == .failed {
            print("Playback error: \(item.error.debugDescription)")
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

    func sendSpeedUpdate() {
        let rate = controller.player.rate
        if rate == 0.0 { return }
        listener.onPlaybackSpeedUpdate(speed: Double(rate)) { _ in }
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

    func disableBuiltInSubtitle() {
        guard let item = controller.player.currentItem else { return }
        if let group = item.asset.mediaSelectionGroup(
            forMediaCharacteristic: .legible
        ) {
            item.select(nil, in: group)
        }
    }
}

// MARK: - Observers for Player Events
extension PlayerEventHandler {
    func attachObservers() {
        let player = controller.player

        // Observe playback rate
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) {
            [weak self] player, _ in
            guard player.currentItem != nil else {return}
            self?.handleStatusUpdate(item: player.currentItem!)
        }

        // Observe playback duration updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDurationUpdate),
            name: AVPlayerItem.newAccessLogEntryNotification,
            object: controller.player.currentItem
        )

    }


    // Handle Item Duration Update
    @objc func handleItemDurationUpdate(notification: Notification) {
        guard let item = controller.player.currentItem else { return }
        let duration = item.duration.seconds
        if duration.isFinite {
            self.listener.onDurationUpdate(second: Int64(duration)) {
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
