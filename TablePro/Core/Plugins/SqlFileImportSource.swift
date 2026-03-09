//
//  SqlFileImportSource.swift
//  TablePro
//

import Foundation
import os
import TableProPluginKit

final class SqlFileImportSource: PluginImportSource, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.TablePro", category: "SqlFileImportSource")

    private let url: URL
    private let encoding: String.Encoding
    private let parser = SQLFileParser()

    private let lock = NSLock()
    private var decompressedURL: URL?

    init(url: URL, encoding: String.Encoding) {
        self.url = url
        self.encoding = encoding
    }

    func fileURL() -> URL {
        url
    }

    func fileSizeBytes() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            return attrs[.size] as? Int64 ?? 0
        } catch {
            Self.logger.warning("Failed to get file size for \(self.url.path(percentEncoded: false)): \(error.localizedDescription)")
            return 0
        }
    }

    func statements() async throws -> AsyncThrowingStream<(statement: String, lineNumber: Int), Error> {
        let fileURL = try await decompressIfNeeded()

        let stream = try await parser.parseFile(url: fileURL, encoding: encoding)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await item in stream {
                        continuation.yield(item)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cleanup() {
        lock.lock()
        let tempURL = decompressedURL
        decompressedURL = nil
        lock.unlock()

        if let tempURL {
            do {
                try FileManager.default.removeItem(at: tempURL)
            } catch {
                Self.logger.warning("Failed to clean up temp file: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        // Best-effort cleanup — decompressedURL is non-isolated, use lock
        lock.lock()
        let tempURL = decompressedURL
        lock.unlock()
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - Private

    private func decompressIfNeeded() async throws -> URL {
        lock.lock()
        if let existing = decompressedURL {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let result = try await FileDecompressor.decompressIfNeeded(url) { $0.path() }

        if result != url {
            lock.lock()
            decompressedURL = result
            lock.unlock()
        }

        return result
    }
}
