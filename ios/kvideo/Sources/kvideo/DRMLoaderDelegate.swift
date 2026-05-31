//
//  DRMDelegate.swift
//  Pods
//
//  Created by Khaled on 23/11/25.
//

import AVFoundation

class DRMLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {

    var certificate: String
    var licenseURL: URL

    init(certificate: String, license: URL) {
        self.certificate = certificate
        self.licenseURL = license
        super.init()
    }

    func getContentKeyAsync(requestBytes: Data) async throws -> Data {
        var request = URLRequest(url: licenseURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/octet-stream",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = requestBytes

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    func getCertificateAsync() async throws -> Data {
        if certificate.hasPrefix("http") {
            let url = URL(string: certificate)!
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }

        guard let data = Data(base64Encoded: certificate) else {
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorClientCertificateRejected
            )
        }
        return data
    }

    // MARK: - AVAssetResourceLoaderDelegate - This is the entrypoint for FairPlay
    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest:
            AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let assetURI = loadingRequest.request.url else { return false }
        guard assetURI.scheme == "skd" else { return false }

        Task {
            do {
                let certificate = try await getCertificateAsync()

                let spcData = try loadingRequest.streamingContentKeyRequestData(
                    forApp: certificate,
                    contentIdentifier: assetURI.absoluteString.data(
                        using: .utf8
                    )!
                )

                let ckc = try await getContentKeyAsync(requestBytes: spcData)

                loadingRequest.dataRequest?.respond(with: ckc)
                loadingRequest.finishLoading()
            } catch {
                print("DRM Error: \(error)")
                loadingRequest.finishLoading(with: error)
            }
        }
        return true
    }

    // MARK: - AVAssetResourceLoaderDelegate - same as initial request
    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForRenewalOfRequestedResource renewalRequest:
            AVAssetResourceRenewalRequest
    ) -> Bool {
        return self.resourceLoader(
            resourceLoader,
            shouldWaitForLoadingOfRequestedResource: renewalRequest
        )
    }
}
