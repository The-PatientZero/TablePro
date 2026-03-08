//
//  ClickHouseConnection.swift
//  TablePro
//
//  Swift wrapper around the ClickHouse HTTP API (port 8123).
//  Uses URLSession for HTTP requests — no C bridge needed.
//

import Foundation
import os

// MARK: - Error Types

struct ClickHouseError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { "ClickHouse Error: \(message)" }

    static let notConnected = ClickHouseError(message: "Not connected to database")
    static let connectionFailed = ClickHouseError(message: "Failed to establish connection")
}

// MARK: - Query Result

struct ClickHouseQueryResult {
    let columns: [String]
    let columnTypeNames: [String]
    let rows: [[String?]]
    let affectedRows: Int
    var summary: ClickHouseQueryProgress?
}

// MARK: - Connection Class

/// Thread-safe ClickHouse connection over the HTTP API.
/// Uses a dedicated URLSession instance for request lifecycle control.
final class ClickHouseConnection: @unchecked Sendable {
    // MARK: - Properties

    private static let logger = Logger(subsystem: "com.TablePro", category: "ClickHouseConnection")

    private let host: String
    private let port: Int
    private let user: String
    private let password: String
    private let useTLS: Bool
    private let skipTLSVerification: Bool

    private let lock = NSLock()
    private var _isConnected = false
    private var _currentDatabase: String
    private var _lastQueryId: String?
    private var currentTask: URLSessionDataTask?
    private var session: URLSession?

    /// Query prefixes that return tabular results and need FORMAT suffix
    private static let selectPrefixes: Set<String> = [
        "SELECT", "SHOW", "DESCRIBE", "DESC", "EXISTS", "EXPLAIN", "WITH"
    ]

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    var lastQueryId: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastQueryId
    }

    // MARK: - Initialization

    init(
        host: String,
        port: Int,
        user: String,
        password: String,
        database: String,
        useTLS: Bool = false,
        skipTLSVerification: Bool = false
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self._currentDatabase = database
        self.useTLS = useTLS
        self.skipTLSVerification = skipTLSVerification
    }

    // MARK: - Connection

    func connect() async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        lock.lock()
        if skipTLSVerification {
            session = URLSession(configuration: config, delegate: InsecureTLSDelegate(), delegateQueue: nil)
        } else {
            session = URLSession(configuration: config)
        }
        lock.unlock()

        do {
            _ = try await executeQuery("SELECT 1")
        } catch {
            lock.lock()
            session?.invalidateAndCancel()
            session = nil
            lock.unlock()
            Self.logger.error("Connection test failed: \(error.localizedDescription)")
            throw ClickHouseError.connectionFailed
        }

        lock.lock()
        _isConnected = true
        lock.unlock()

        Self.logger.debug("Connected to ClickHouse at \(self.host):\(self.port)")
    }

    func switchDatabase(_ database: String) async throws {
        lock.lock()
        _currentDatabase = database
        lock.unlock()
    }

    func disconnect() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
        _isConnected = false
        lock.unlock()

        Self.logger.debug("Disconnected from ClickHouse")
    }

    // MARK: - Query Execution

    func executeQuery(_ query: String, queryId: String? = nil) async throws -> ClickHouseQueryResult {
        lock.lock()
        guard let session = self.session else {
            lock.unlock()
            throw ClickHouseError.notConnected
        }
        let database = _currentDatabase
        if let queryId {
            _lastQueryId = queryId
        }
        lock.unlock()

        let request = try buildRequest(query: query, database: database, queryId: queryId)
        let isSelect = Self.isSelectLikeQuery(query)

        let (data, response) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data = data, let response = response else {
                        continuation.resume(throwing: ClickHouseError(message: "Empty response from server"))
                        return
                    }
                    continuation.resume(returning: (data, response))
                }

                self.lock.lock()
                self.currentTask = task
                self.lock.unlock()

                task.resume()
            }
        } onCancel: {
            self.cancel()
        }

        lock.lock()
        currentTask = nil
        lock.unlock()

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.logger.error("ClickHouse HTTP \(httpResponse.statusCode): \(body)")
            throw ClickHouseError(message: body.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var summaryProgress: ClickHouseQueryProgress?
        if let httpResponse = response as? HTTPURLResponse,
           let summaryHeader = httpResponse.value(forHTTPHeaderField: "X-ClickHouse-Summary") {
            summaryProgress = Self.parseSummaryHeader(summaryHeader)
        }

        if isSelect {
            var result = parseTabSeparatedResponse(data)
            result.summary = summaryProgress
            return result
        }

        return ClickHouseQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: 0, summary: summaryProgress)
    }

    func cancel() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        lock.unlock()
    }

    // MARK: - Kill Query

    func killQuery(queryId: String) {
        guard !queryId.isEmpty else { return }

        lock.lock()
        let hasSession = session != nil
        lock.unlock()

        guard hasSession else { return }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let killSession = URLSession(configuration: config)

        do {
            let escapedId = queryId.replacingOccurrences(of: "'", with: "\\'")
            let request = try buildRequest(
                query: "KILL QUERY WHERE query_id = '\(escapedId)'",
                database: ""
            )
            let task = killSession.dataTask(with: request) { _, _, _ in
                killSession.invalidateAndCancel()
            }
            task.resume()
            Self.logger.debug("Sent KILL QUERY for query_id: \(queryId)")
        } catch {
            killSession.invalidateAndCancel()
            Self.logger.error("Failed to send KILL QUERY: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func buildRequest(query: String, database: String, queryId: String? = nil) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = useTLS ? "https" : "http"
        components.host = host
        components.port = port
        components.path = "/"

        var queryItems = [URLQueryItem]()
        if !database.isEmpty {
            queryItems.append(URLQueryItem(name: "database", value: database))
        }
        if let queryId {
            queryItems.append(URLQueryItem(name: "query_id", value: queryId))
        }
        queryItems.append(URLQueryItem(name: "send_progress_in_http_headers", value: "1"))
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw ClickHouseError(message: "Failed to construct request URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let credentials = "\(user):\(password)"
        if let credData = credentials.data(using: .utf8) {
            request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        // Strip trailing semicolons — ClickHouse HTTP interface treats them as multi-statement delimiters
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ";+$", with: "", options: .regularExpression)

        if Self.isSelectLikeQuery(trimmedQuery) {
            request.httpBody = (trimmedQuery + " FORMAT TabSeparatedWithNamesAndTypes").data(using: .utf8)
        } else {
            request.httpBody = trimmedQuery.data(using: .utf8)
        }

        return request
    }

    private static func isSelectLikeQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstWord = trimmed.split(separator: " ", maxSplits: 1).first else {
            return false
        }
        return selectPrefixes.contains(firstWord.uppercased())
    }

    private static func parseSummaryHeader(_ header: String) -> ClickHouseQueryProgress? {
        guard let data = header.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let rowsRead = (json["read_rows"] as? String).flatMap { UInt64($0) } ?? 0
        let bytesRead = (json["read_bytes"] as? String).flatMap { UInt64($0) } ?? 0
        let totalRows = (json["total_rows_to_read"] as? String).flatMap { UInt64($0) } ?? 0
        let elapsed = (json["elapsed_ns"] as? String).flatMap { Double($0) }.map { $0 / 1_000_000_000 } ?? 0

        return ClickHouseQueryProgress(
            rowsRead: rowsRead,
            bytesRead: bytesRead,
            totalRowsToRead: totalRows,
            elapsedSeconds: elapsed
        )
    }

    private func parseTabSeparatedResponse(_ data: Data) -> ClickHouseQueryResult {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return ClickHouseQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: 0, summary: nil)
        }

        let lines = text.components(separatedBy: "\n")

        guard lines.count >= 2 else {
            return ClickHouseQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: 0, summary: nil)
        }

        let columns = lines[0].components(separatedBy: "\t")
        let columnTypes = lines[1].components(separatedBy: "\t")

        var rows: [[String?]] = []
        for i in 2..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }

            let fields = line.components(separatedBy: "\t")
            let row = fields.map { field -> String? in
                if field == "\\N" {
                    return nil
                }
                return unescapeTsvField(field)
            }
            rows.append(row)
        }

        return ClickHouseQueryResult(
            columns: columns,
            columnTypeNames: columnTypes,
            rows: rows,
            affectedRows: rows.count,
            summary: nil
        )
    }

    /// Unescape TSV escape sequences: `\\` -> `\`, `\t` -> tab, `\n` -> newline
    private func unescapeTsvField(_ field: String) -> String {
        var result = ""
        result.reserveCapacity(field.count)
        var iterator = field.makeIterator()

        while let char = iterator.next() {
            if char == "\\" {
                if let next = iterator.next() {
                    switch next {
                    case "\\": result.append("\\")
                    case "t": result.append("\t")
                    case "n": result.append("\n")
                    default:
                        result.append("\\")
                        result.append(next)
                    }
                } else {
                    result.append("\\")
                }
            } else {
                result.append(char)
            }
        }

        return result
    }

    // MARK: - TLS Delegate

    private class InsecureTLSDelegate: NSObject, URLSessionDelegate {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
