//
//  DownloadManager.swift
//  Pods
//
//  Created by Khaled on 27/11/25.
//

import AVFoundation
import Flutter
import Foundation

class NewDownloadManager: NSObject, DownloadManagerApi {
    private let session = VidLoader()
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
    func download(media: Media) throws -> String? {
        guard let url = URL(string: media.url) else { return nil }
        let assetId = UUID().uuidString

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
        let saved = loadCompletedDownloads().first(where: { $0.id == id })
        if saved != nil {
            deleteCompletedDownload(download: saved!)
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
        let saved = loadCompletedDownloads().first(where: { $0.id == id })
        if saved != nil { return completion(.success(saved!)) }

        guard let item = session.itemInformation(for: id) else {
            return completion(.success(nil))
        }

        var status: DownloadStatus
        var error: String?

        switch item.state {
        case .running(_):
            status = .downloading
        case .waiting, .prefetching:
            status = .waiting

        case .completed:
            status = .finished

        case .failed(let err):
            status = .error
            error = err.localizedDescription

        case .canceled:
            status = .error
            error = "ERR: Canceled"

        default:
            status = .waiting
        }

        let downloadData = DownloadData(
            id: item.identifier,
            progress: Int64(item.progress * 100),
            status: status,
            originUri: item.mediaLink,
            localUri: item.location?.absoluteString,
            error: error
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
            contentsOf: loadCompletedDownloads().compactMap { return $0.id }
        )

        completion(.success(downloadTasks))
    }

    func setAndroidDataSourceHeaders(headers: [String: String]) throws {}

}

// MARK: - Event Listener
extension NewDownloadManager {

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
extension NewDownloadManager {

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
                    print("Failed to delete file at \(path)")
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
