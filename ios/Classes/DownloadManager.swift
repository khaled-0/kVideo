//
//  DownloadManager.swift
//  Pods
//
//  Created by Khaled on 27/11/25.
//

import AVFoundation
import Flutter
import Foundation

class DownloadManager: NSObject, DownloadManagerApi {

    private let listener: DownloadEventListener

    // MARK: - Internal Storage
    private var session: AVAssetDownloadURLSession!
    private var activeTasks: [String: AVAssetDownloadTask] = [:]

    init(messenger: FlutterBinaryMessenger) {
        self.listener = DownloadEventListener(binaryMessenger: messenger)
        super.init()

        let config = URLSessionConfiguration.background(
            withIdentifier: "dev.khaled.kvideo"
        )

        self.session = AVAssetDownloadURLSession(
            configuration: config,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )

        restorePendingDownloads()
    }

    // MARK: - Public API

    /// Start downloading a media
    func download(media: Media) throws -> String? {
        guard let url = URL(string: media.url) else { return nil }
        let assetId = UUID().uuidString
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": media.headers ?? [:]]
        )

        // TODO: DRM Delegate

        let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: assetId,
            assetArtworkData: nil,
            options: nil
        )

        guard let task else { return nil }

        activeTasks[assetId] = task
        task.taskDescription = assetId
        task.resume()
        return assetId
    }

    /// Cancel a download
    func remove(id: String) throws {
        guard let task = activeTasks[id] else { return }
        task.cancel()
        activeTasks.removeValue(forKey: id)
    }

    func removeAll() throws {
        for (key, value) in activeTasks {
            value.cancel()
            activeTasks.removeValue(forKey: key)
        }
    }

    /// Resume pending tasks after app launch
    func restorePendingDownloads() {
        session.getAllTasks { tasks in
            tasks.forEach { task in
                if task.state == .completed { return }
                guard let downloadTask = task as? AVAssetDownloadTask else {
                    return
                }
                guard let assetId = task.taskDescription else { return }
                self.activeTasks[assetId] = downloadTask
                task.resume()
                print("Restored pending download for assetId: \(assetId)")
            }
        }
    }
    
    func setAndroidDataSourceHeaders(headers: [String : String]) throws {}
}

// MARK: - Event Listener
extension DownloadManager: AVAssetDownloadDelegate {

    /// Progress Updates
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {

        guard let id = assetDownloadTask.taskDescription else { return }

        let loadedSeconds =
            loadedTimeRanges
            .map { $0.timeRangeValue.duration.seconds }
            .reduce(0, +)

        let totalSeconds = timeRangeExpectedToLoad.duration.seconds

        let progress = loadedSeconds / totalSeconds
        self.listener.onProgress(id: id, progress: progress * 100) { _ in }
    }

    /// Completion
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        activeTasks.removeValue(forKey: id)
        self.listener.onCompletion(id: id, location: location.absoluteString) {
            _ in
        }
        restorePendingDownloads()
    }

    /// Error Handling
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {

        guard let error, let id = task.taskDescription else { return }
        activeTasks.removeValue(forKey: id)
        self.listener.onError(id: id, error: error.localizedDescription) {
            _ in
        }
    }

    /// Called when background events finish
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession)
    {
        //        // Hook for AppDelegate/SceneDelegate to notify the system the events are done.
        //        NotificationCenter.default.post(
        //            name: Notification.Name("HLSBackgroundEventsFinished"),
        //            object: nil
        //        )
    }
}
