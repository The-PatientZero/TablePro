//
//  RegistryClient.swift
//  TablePro
//

import Foundation
import os

@MainActor @Observable
final class RegistryClient {
    static let shared = RegistryClient()

    private(set) var manifest: RegistryManifest?
    private(set) var fetchState: RegistryFetchState = .idle
    private(set) var lastFetchDate: Date?

    private var cachedETag: String? {
        get { UserDefaults.standard.string(forKey: "registryETag") }
        set { UserDefaults.standard.set(newValue, forKey: "registryETag") }
    }

    private let session: URLSession
    private static let logger = Logger(subsystem: "com.TablePro", category: "RegistryClient")

    // swiftlint:disable:next force_unwrapping
    private static let registryURL = URL(string:
        "https://raw.githubusercontent.com/TableProApp/plugins/main/plugins.json")!

    private static let manifestCacheKey = "registryManifestCache"
    private static let lastFetchKey = "registryLastFetch"

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        if let cachedData = UserDefaults.standard.data(forKey: Self.manifestCacheKey),
           let cached = try? decoder.decode(RegistryManifest.self, from: cachedData) {
            manifest = cached
            lastFetchDate = UserDefaults.standard.object(forKey: Self.lastFetchKey) as? Date
        }
    }

    // MARK: - Fetching

    func fetchManifest(forceRefresh: Bool = false) async {
        fetchState = .loading

        var request = URLRequest(url: Self.registryURL)
        if !forceRefresh, let etag = cachedETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            switch httpResponse.statusCode {
            case 304:
                Self.logger.debug("Registry manifest not modified (304)")
                fetchState = .loaded

            case 200...299:
                let decoded = try decoder.decode(RegistryManifest.self, from: data)
                manifest = decoded

                UserDefaults.standard.set(data, forKey: Self.manifestCacheKey)
                cachedETag = httpResponse.value(forHTTPHeaderField: "ETag")
                lastFetchDate = Date()
                UserDefaults.standard.set(lastFetchDate, forKey: Self.lastFetchKey)

                fetchState = .loaded
                Self.logger.info("Fetched registry manifest with \(decoded.plugins.count) plugin(s)")

            default:
                let message = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                Self.logger.error("Registry fetch failed: HTTP \(httpResponse.statusCode) \(message)")
                fallbackToCacheOrFail(message: "Server returned HTTP \(httpResponse.statusCode)")
            }
        } catch is DecodingError {
            Self.logger.error("Failed to decode registry manifest")
            fallbackToCacheOrFail(message: String(localized: "Failed to parse plugin registry"))
        } catch {
            Self.logger.error("Registry fetch failed: \(error.localizedDescription)")
            fallbackToCacheOrFail(message: error.localizedDescription)
        }
    }

    private func fallbackToCacheOrFail(message: String) {
        if manifest != nil {
            fetchState = .loaded
            Self.logger.warning("Using cached registry manifest after fetch failure")
        } else {
            fetchState = .failed(message)
        }
    }

    // MARK: - Search

    func search(query: String, category: RegistryCategory?) -> [RegistryPlugin] {
        guard let plugins = manifest?.plugins else { return [] }

        var filtered = plugins

        if let category {
            filtered = filtered.filter { $0.category == category }
        }

        if !query.isEmpty {
            let lowercased = query.lowercased()
            filtered = filtered.filter { plugin in
                plugin.name.lowercased().contains(lowercased)
                    || plugin.summary.lowercased().contains(lowercased)
                    || plugin.author.name.lowercased().contains(lowercased)
            }
        }

        return filtered
    }
}

enum RegistryFetchState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
