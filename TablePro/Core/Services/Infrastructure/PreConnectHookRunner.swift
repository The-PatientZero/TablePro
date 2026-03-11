//
//  PreConnectHookRunner.swift
//  TablePro
//

import Foundation
import os

/// Runs a shell script before establishing a database connection.
/// Non-zero exit aborts the connection with an error.
enum PreConnectHookRunner {
    private static let logger = Logger(subsystem: "com.TablePro", category: "PreConnectHookRunner")

    enum HookError: LocalizedError {
        case scriptFailed(exitCode: Int32, stderr: String)
        case timeout

        var errorDescription: String? {
            switch self {
            case let .scriptFailed(exitCode, stderr):
                let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.isEmpty {
                    return String(localized: "Pre-connect script failed with exit code \(exitCode)")
                }
                return String(localized: "Pre-connect script failed (exit \(exitCode)): \(message)")
            case .timeout:
                return String(localized: "Pre-connect script timed out after 10 seconds")
            }
        }
    }

    /// Run a shell script before connecting. Throws on non-zero exit or timeout.
    static func run(script: String, environment: [String: String]? = nil) async throws {
        logger.info("Running pre-connect script")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]

        var env = ProcessInfo.processInfo.environment
        if let environment {
            for (key, value) in environment {
                env[key] = value
            }
        }
        process.environment = env

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        // 10-second timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationReason == .uncaughtSignal {
            throw HookError.timeout
        }

        if process.terminationStatus != 0 {
            logger.warning("Pre-connect script failed with exit code \(process.terminationStatus)")
            throw HookError.scriptFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        logger.info("Pre-connect script completed successfully")
    }
}
