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

class PlayerEventHandler {
    public let listener: PlayerEventListener
    private var controller: PlayerController

    private var timeObserver: Any?

    private var statusObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?

    private var timeControlObserver: NSKeyValueObservation?
    private var speedObserver: NSKeyValueObservation?

    private var durationObserver: NSKeyValueObservation?
    private var timeRangeObserver: NSKeyValueObservation?

    private var playerNotificationsObserver: NSKeyValueObservation?

    init(messenger: FlutterBinaryMessenger, controller: PlayerController) {
        self.listener = PlayerEventListener(
            binaryMessenger: messenger,
            messageChannelSuffix: controller.suffix
        )
        self.controller = controller

        attachPlayerObservers()
        attachPeriodicProgressUpdate()
    }

    deinit { removeObservers() }

    func removeObservers() {
        let player = controller.player

        if let timeObserver = self.timeObserver {
            controller.player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        self.statusObserver?.invalidate()
        self.statusObserver = nil

        self.itemStatusObserver?.invalidate()
        self.itemStatusObserver = nil

        self.timeControlObserver?.invalidate()
        self.timeControlObserver = nil

        self.speedObserver?.invalidate()
        self.speedObserver = nil

        self.durationObserver?.invalidate()
        self.durationObserver = nil

        self.timeRangeObserver?.invalidate()
        self.timeRangeObserver = nil

        self.playerNotificationsObserver?.invalidate()
        self.playerNotificationsObserver = nil

        NotificationCenter.default.removeObserver(self)

    }

    func attachPlayerObservers() {
        let player = controller.player

        statusObserver = player.observe(\.status, options: [.new]) {
            [weak self] player, _ in
            guard player.currentItem != nil else { return }
            self?.handleStatusUpdate(item: player.currentItem!)
        }

        itemStatusObserver = player.observe(
            \.currentItem?.status,
            options: [.new]
        ) {
            [weak self] player, _ in
            guard player.currentItem != nil else { return }
            self?.handleStatusUpdate(item: player.currentItem!)
        }

        speedObserver = player.observe(\.rate, options: [.new]) {
            [weak self] player, rate in
            guard let rate = rate.newValue else { return }
            if rate == 0.0 { return }
            self?.listener.onPlaybackSpeedUpdate(speed: Double(rate)) { _ in }
        }

        timeControlObserver = player.observe(
            \.timeControlStatus,
            options: [.new]
        ) {
            [weak self] player, _ in
            guard player.currentItem != nil else { return }
            self?.handleStatusUpdate(item: player.currentItem!)
        }

        durationObserver = player.observe(
            \.currentItem?.duration,
            options: [.new]
        ) {
            [weak self] player, change in
            var duration = change.newValue??.seconds ?? 0
            if !duration.isFinite { duration = 0 }
            self?.listener.onDurationUpdate(second: Int64(duration)) {
                _ in
            }
        }

        timeRangeObserver = player.observe(
            \.currentItem?.loadedTimeRanges,
            options: [.new]
        ) {
            [weak self] player, _ in
            guard let currentItem = player.currentItem else { return }
            self?.sendBufferUpdate(item: currentItem)
        }

        playerNotificationsObserver = player.observe(
            \.currentItem,
            options: [.new]
        ) {
            [weak self] _, _ in
            guard let self else { return }

            NotificationCenter.default.removeObserver(self)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentDidFinishPlaying(_:)),
                name: AVPlayerItem.didPlayToEndTimeNotification,
                object: player.currentItem
            )

        }
    }

    func handleStatusUpdate(item: AVPlayerItem?) {

        if item?.status == .readyToPlay {
            disableBuiltInSubtitle()
            self.listener.onTracksLoaded(
                tracks: (try? controller.getTracks()) ?? []
            ) { _ in }
        }

        if item?.status == .failed {
            NSLog("Playback error: \(item!.error.debugDescription)")
            self.listener.onPlaybackError(
                error: item!.error.debugDescription
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

    @objc func contentDidFinishPlaying(_ notification: Notification) {
        // Make sure we don't call contentComplete as a result of an ad completing.
        if notification.object as? AVPlayerItem == controller.player.currentItem
        {
            listener.onPlaybackUpdate(status: .finished) { _ in }
            controller.adsLoader.contentComplete()
        }
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

            guard controller.player.currentTime().isValid else { return }

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
