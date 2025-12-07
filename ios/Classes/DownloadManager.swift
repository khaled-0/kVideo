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
    public static let session = VidLoader()
    
    private let storageKey = "dev.khaled.kvideo.downloads.encrypted"
    private let session = DownloadManager.session
    private let listener: DownloadEventListener
    private lazy var observer = VidObserver(
        type: ObserverType.all,
        stateChanged: self.stateChanged
    )

    init(messenger: FlutterBinaryMessenger) {
        self.listener = DownloadEventListener(binaryMessenger: messenger)
        super.init()
        session.observe(with: observer)
    }

    deinit {
        session.remove(observer: observer)
    }

    // MARK: - Public API

    /// Start downloading a media
    func download(media: Media, customId: String?) throws -> String? {
        guard let url = URL(string: media.url) else { return nil }
        let assetId = customId ?? UUID().uuidString

        session.download(
            DownloadValues(
                identifier: assetId,
                url: url,
                title: "",
                artworkData: nil,
                minRequiredBitrate: nil,
                headers: media.headers ?? [:]
            )
        )

        return assetId
    }

    /// Cancel a download
    func remove(
        id: String,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        session.cancel(identifier: id)
        if let saved = loadCompletedDownloads().first(where: {
            $0.identifier == id
        }) {
            deleteCompletedDownload(item: saved)
            listener.onRemoved(id: id) { _ in }
            return completion(.success(Void()))
        }
    }

    func removeAll(completion: @escaping (Result<Void, any Error>) -> Void) {
        session.cancelActiveItems()
        removeCompletedDownloads()
        completion(.success(Void()))
    }

    func getStatusFor(
        id: String,
        completion: @escaping (Result<DownloadData?, any Error>) -> Void
    ) {
        if let saved = loadCompletedDownloads().first(where: {
            $0.identifier == id
        }) {
            return completion(.success(saved.toDownloadData()))
        }

        guard let item = session.itemInformation(for: id) else {
            return completion(.success(nil))
        }

        let status = item.getStatus()
        let downloadData = DownloadData(
            id: item.identifier,
            progress: Int64(item.progress * 100),
            status: status.status,
            originUri: item.mediaLink,
            localUri: item.location?.absoluteString,
            error: status.error
        )

        return completion(.success(downloadData))
    }

    func getAllDownloads(
        completion: @escaping (Result<[String], any Error>) -> Void
    ) {
        var downloadTasks: [String] = []
        session.items().forEach {
            downloadTasks.append($0.identifier)
        }

        downloadTasks.append(
            contentsOf: loadCompletedDownloads().compactMap {
                return $0.identifier
            }
        )

        completion(.success(downloadTasks))
    }

    func setAndroidDataSourceHeaders(headers: [String: String]) throws {}

}

// MARK: - Event Listener
extension DownloadManager {

    func stateChanged(info: ItemInformation) {
        switch info.state {
        case .running(let progress),
            .noConnection(let progress),
            .paused(let progress):
            self.listener.onProgress(
                id: info.identifier,
                progress: Int64(progress * 100)
            ) {
                _ in
            }

        case .completed:
            saveCompletedDownload(info)
            self.listener.onCompletion(
                id: info.identifier,
                location: info.location?.absoluteString ?? ""
            ) {
                _ in
            }

        case .canceled:
            self.listener.onRemoved(id: info.identifier) {
                _ in
            }

        case .failed(let error):
            self.listener.onError(
                id: info.identifier,
                error: error.localizedDescription
            ) {
                _ in
            }

        case .unknown, .prefetching, .waiting, .keyLoaded:
            self.listener.onProgress(
                id: info.identifier,
                progress: Int64(info.progress * 100)
            ) {
                _ in
            }
        }
    }
}

// MARK: - Store Completed Entries
extension DownloadManager {

    private func saveCompletedDownload(_ item: ItemInformation) {
        var saved = loadCompletedDownloads()
        if let index = saved.firstIndex(where: {
            $0.identifier == item.identifier
        }) {
            saved[index] = item
        } else {
            saved.append(item)
        }

        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func loadCompletedDownloads() -> [ItemInformation] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode(
                [ItemInformation].self,
                from: data
            )
        else { return [] }

        return saved
    }

    func removeCompletedDownloads() {
        loadCompletedDownloads().forEach { download in
            if let path = download.location {
                do {
                    try FileManager.default.removeItem(at: path)
                    print("Deleted file at \(path)")
                } catch {
                    print("Failed to delete file at \(path)")
                }
            }
        }

        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func deleteCompletedDownload(item: ItemInformation) {
        var completedDownloads = self.loadCompletedDownloads()
        if let index = completedDownloads.firstIndex(of: item) {
            let download = completedDownloads[index]
            if let path = download.location {
                do {
                    try FileManager.default.removeItem(at: path)
                    self.listener.onRemoved(id: download.identifier) { _ in }
                    print("Deleted file at \(path)")
                } catch {
                    print("Failed to delete file at \(path)")
                }
            }
            // Remove from saved completed downloads
            completedDownloads.remove(at: index)

            // Save updated completed downloads
            if let encoded = try? JSONEncoder().encode(completedDownloads) {
                UserDefaults.standard.set(encoded, forKey: storageKey)
            }
        }
    }
}

extension ItemInformation {
    func toDownloadData() -> DownloadData {
        let status = getStatus()
        return DownloadData(
            id: self.identifier,
            progress: Int64(self.progress * 100),
            status: status.status,
            originUri: self.mediaLink,
            localUri: self.location?.absoluteString,
            error: status.error
        )
    }

    func getStatus() -> (status: DownloadStatus, error: String?) {
        switch self.state {
        case .running(_):
            return (status: .downloading, error: nil)

        case .completed:
            return (status: .finished, error: nil)

        case .failed(let err):
            return (status: .error, error: err.localizedDescription)

        case .canceled:
            return (status: .error, error: "ERR: Canceled")

        case .waiting, .prefetching:
            return (status: .waiting, error: nil)
        default:
            return (status: .waiting, error: nil)
        }
    }
}
