//
//  AIChatStorage.swift
//  TablePro
//
//  File-based persistence for AI chat conversations.
//

import Foundation
import os

/// Manages persistent storage of AI chat conversations as individual JSON files
final class AIChatStorage {
    static let shared = AIChatStorage()

    private static let logger = Logger(subsystem: "com.TablePro", category: "AIChatStorage")

    private let directory: URL

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        let appSupport: URL
        if let resolved = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            appSupport = resolved
        } else {
            Self.logger.error("Application Support directory unavailable, falling back to temporary directory")
            appSupport = FileManager.default.temporaryDirectory
        }
        directory = appSupport
            .appendingPathComponent("TablePro", isDirectory: true)
            .appendingPathComponent("ai_chats", isDirectory: true)

        createDirectoryIfNeeded()
    }

    // MARK: - Public Methods

    /// Save a conversation to disk
    func save(_ conversation: AIConversation) {
        let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")

        do {
            let data = try Self.encoder.encode(conversation)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save conversation \(conversation.id): \(error.localizedDescription)")
        }
    }

    /// Load all conversations, sorted by updatedAt descending
    func loadAll() -> [AIConversation] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )

            let conversations: [AIConversation] = files
                .filter { $0.pathExtension == "json" }
                .compactMap { fileURL in
                    do {
                        let data = try Data(contentsOf: fileURL)
                        return try Self.decoder.decode(AIConversation.self, from: data)
                    } catch {
                        Self.logger.error("Failed to load conversation from \(fileURL.lastPathComponent): \(error.localizedDescription)")
                        return nil
                    }
                }

            return conversations.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            Self.logger.error("Failed to list conversations: \(error.localizedDescription)")
            return []
        }
    }

    /// Delete a conversation by ID
    func delete(_ id: UUID) {
        let fileURL = directory.appendingPathComponent("\(id.uuidString).json")

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Self.logger.error("Failed to delete conversation \(id): \(error.localizedDescription)")
        }
    }

    /// Delete all conversations
    func deleteAll() {
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
                createDirectoryIfNeeded()
            }
        } catch {
            Self.logger.error("Failed to delete all conversations: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            Self.logger.error("Failed to create ai_chats directory: \(error.localizedDescription)")
        }
    }
}
