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
    func remove(
        id: String,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        let saved = loadCompletedDownloads().first(where: { $0.id == id })
        if saved != nil {
            deleteCompletedDownload(download: saved!)
            listener.onRemoved(id: id) { _ in }
            return completion(.success(Void()))
        }

        getTasks {
            let task = $0.first(where: { $0.taskDescription == id })
            task?.cancel()
            self.listener.onRemoved(id: id) { _ in }
            completion(.success(Void()))
        }
    }

    func removeAll(completion: @escaping (Result<Void, any Error>) -> Void) {
        getTasks { tasks in
            tasks.forEach {
                self.remove(id: $0.taskDescription!) { _ in }
                self.listener.onRemoved(id: $0.taskDescription!) { _ in }
            }
        }

        removeCompletedDownloads()
        completion(.success(Void()))
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

    func getStatusFor(
        id: String,
        completion: @escaping (Result<DownloadData?, any Error>) -> Void
    ) {
        let saved = loadCompletedDownloads().first(where: { $0.id == id })
        if saved != nil { return completion(.success(saved!)) }

        getTasks { tasks in
            guard let task = tasks.first(where: { $0.taskDescription == id })
            else { return completion(.success(nil)) }

            // Extract progress as a percentage
            let bytesReceived = task.countOfBytesReceived
            let bytesExpected = task.countOfBytesExpectedToReceive
            guard bytesExpected > 0 else { return completion(.success(nil)) }

            // Calculate progress as a percentage
            let progress = Int64(
                (Double(bytesReceived) / Double(bytesExpected)) * 100
            )

            // Determine the status based on the task's state
            var status: DownloadStatus
            switch task.state {
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

            if task.error != nil { status = .error }

            // Create a DownloadData object
            let downloadData = DownloadData(
                id: task.taskDescription,
                progress: progress,
                status: status,
                originUri: task.originalRequest?.url?.absoluteString,
                localUri: task.response?.url?.absoluteString,
                error: task.error?.localizedDescription
            )

            return completion(.success(downloadData))
        }
    }

    func getAllDownloads(
        completion: @escaping (Result<[String], any Error>) -> Void
    ) {
        var downloadTasks: [String] = []
        getTasks { tasks in
            tasks.forEach { task in
                downloadTasks.append(task.taskDescription!)
            }
        }

        downloadTasks.append(
            contentsOf: loadCompletedDownloads().compactMap { return $0.id }
        )

        completion(.success(downloadTasks))
    }

    func setAndroidDataSourceHeaders(headers: [String: String]) throws {}

    private func getTasks(completion: @escaping ([URLSessionTask]) -> Void) {
        session.getAllTasks { tasks in
            completion(tasks)
        }
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

        guard bytesExpected > 0 else { return }

        // Calculate progress as a percentage
        let progress = Int64(
            (Double(bytesReceived) / Double(bytesExpected)) * 100
        )

        let clampedProgress = min(max(progress, 0), 100)
        self.listener.onProgress(id: id, progress: clampedProgress) { _ in }

    }

    /// Completion
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }

        let downloadData = DownloadData(
            id: id,
            progress: 100,
            status: .finished,
            originUri: assetDownloadTask.urlAsset.url.absoluteString,
            localUri: location.absoluteString,
            error: nil
        )

        saveCompletedDownload(downloadData)

        self.listener.onCompletion(id: id, location: location.absoluteString) {
            _ in
        }
    }

    /// Error Handling
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {

        guard let error, let id = task.taskDescription else { return }

        if (error as NSError).code == NSURLErrorCancelled {
            self.listener.onRemoved(id: id) { _ in }
            return
        }

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

// MARK: - Store Completed Entries
extension DownloadManager {

    private func saveCompletedDownload(_ downloadData: DownloadData) {
        var saved = loadCompletedDownloads().map {
            DownloadDataCodable(from: $0)
        }

        if let index = saved.firstIndex(where: { $0.id == downloadData.id }) {
            saved[index] = DownloadDataCodable(from: downloadData)
        } else {
            saved.append(DownloadDataCodable(from: downloadData))
        }

        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(
                encoded,
                forKey: "dev.khaled.kvideo.downloads"
            )
        }
    }

    func loadCompletedDownloads() -> [DownloadData] {
        guard
            let data = UserDefaults.standard.data(
                forKey: "dev.khaled.kvideo.downloads"
            ),
            let saved = try? JSONDecoder().decode(
                [DownloadDataCodable].self,
                from: data
            )
        else { return [] }

        return saved.map { $0.toDownloadData() }
    }

    func removeCompletedDownloads() {
        loadCompletedDownloads().forEach { download in
            if let path = download.localUri, let url = URL(string: path) {
                do {
                    try FileManager.default.removeItem(at: url)
                    self.listener.onRemoved(id: download.id!) { _ in }
                    print("Deleted file at \(path)")
                } catch {
                    print("Failed to delete file at \(path)")
                }
            }
        }

        UserDefaults.standard.removeObject(
            forKey: "dev.khaled.kvideo.downloads"
        )
    }

    func deleteCompletedDownload(download: DownloadData) {
        var completedDownloads = self.loadCompletedDownloads()
        if let index = completedDownloads.firstIndex(where: {
            $0.id == download.id
        }) {
            let download = completedDownloads[index]

            if let path = download.localUri, let url = URL(string: path) {
                do {
                    try FileManager.default.removeItem(at: url)
                    print("Deleted file at \(path)")
                } catch {
                    print(
                        "Failed to delete file at \(path)"
                    )
                }
            }

            // Remove from saved completed downloads
            completedDownloads.remove(at: index)

            // Save updated completed downloads
            if let encoded = try? JSONEncoder().encode(
                completedDownloads.map { DownloadDataCodable(from: $0) }
            ) {
                UserDefaults.standard.set(
                    encoded,
                    forKey: "dev.khaled.kvideo.downloads"
                )
            }
        }
    }
}

struct DownloadDataCodable: Codable {
    let id: String?
    let progress: Int64
    let status: Int
    let originUri: String?
    let localUri: String?
    let error: String?

    init(from downloadData: DownloadData) {
        self.id = downloadData.id
        self.progress = downloadData.progress ?? 0
        self.status =
            downloadData.status?.rawValue ?? DownloadStatus.waiting.rawValue
        self.originUri = downloadData.originUri
        self.localUri = downloadData.localUri
        self.error = downloadData.error
    }

    func toDownloadData() -> DownloadData {
        return DownloadData(
            id: id,
            progress: progress,
            status: DownloadStatus(rawValue: status),
            originUri: originUri,
            localUri: localUri,
            error: error
        )
    }
}
