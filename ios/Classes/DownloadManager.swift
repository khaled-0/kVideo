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

        task.taskDescription = assetId
        task.resume()
        return assetId
    }

    /// Cancel a download
    func remove(id: String) throws {
        guard let task = getTasks().first(where: { $0.taskDescription == id })
        else { return }
        task.cancel()
    }

    func removeAll() throws {
        session.invalidateAndCancel()
    }

    /// Resume pending tasks after app launch
    func restorePendingDownloads() {
        session.getAllTasks { tasks in
            tasks.forEach { task in
                if task.state == .completed { return }
                guard task as? AVAssetDownloadTask != nil else { return }
                guard let assetId = task.taskDescription else { return }
                task.resume()
                print("Restored pending download for assetId: \(assetId)")
            }
        }
    }

    func getStatusFor(id: String) throws -> DownloadData? {
        guard let task = getTasks().first(where: { $0.taskDescription == id })
        else { return nil }

        guard let downloadTask = task as? URLSessionDownloadTask else {
            return nil
        }

        // Extract progress as a percentage
        let bytesReceived = downloadTask.countOfBytesReceived
        let bytesExpected = downloadTask.countOfBytesExpectedToReceive

        var progress: Int64 = 0
        if bytesExpected > 0 {
            progress = Int64(
                (Double(bytesReceived) / Double(bytesExpected)) * 100
            )
        }

        // Determine the status based on the task's state
        var status: DownloadStatus
        switch downloadTask.state {
        case .running:
            status = .downloading
        case .suspended:
            status = .waiting
        case .canceling:
            status = .waiting
        case .completed:
            status = .finished
        @unknown default:
            status = .waiting
        }

        if downloadTask.error != nil { status = .error }

        // Create a DownloadData object
        let downloadData = DownloadData(
            id: downloadTask.taskDescription,
            progress: progress,
            status: status,
            originUri: downloadTask.originalRequest?.url?.absoluteString,
            localUri: downloadTask.response?.url?.absoluteString,
            error: downloadTask.error?.localizedDescription
        )

        return downloadData
    }

    func getAllDownloads() throws -> [String] {
        return getTasks().compactMap { task in
            return task.taskDescription
        }
    }

    func setAndroidDataSourceHeaders(headers: [String: String]) throws {}

    private func getTasks() -> [URLSessionTask] {
        var downloadTasks: [URLSessionTask] = []
        session.getAllTasks { tasks in
            tasks.forEach { task in
                if task.state == .running && task is URLSessionDownloadTask {
                    downloadTasks.append(task)
                }
            }
        }

        return downloadTasks
    }
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

        let bytesReceived = assetDownloadTask.countOfBytesReceived
        let bytesExpected = assetDownloadTask.countOfBytesExpectedToReceive

        if bytesExpected < 0 { return }
        let progress = Int64(
            (Double(bytesReceived) / Double(bytesExpected)) * 100
        )
        self.listener.onProgress(id: id, progress: progress) { _ in }

    }

    /// Completion
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
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
