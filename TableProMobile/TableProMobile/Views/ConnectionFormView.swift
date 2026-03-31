//
//  ConnectionFormView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels
import UniformTypeIdentifiers

struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var name = ""
    @State private var type: DatabaseType = .mysql
    @State private var host = "127.0.0.1"
    @State private var port = "3306"
    @State private var username = ""
    @State private var password = ""
    @State private var database = ""
    @State private var sslEnabled = false

    // SQLite file picker
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var showNewDatabaseAlert = false
    @State private var newDatabaseName = ""

    var onSave: (DatabaseConnection) -> Void

    private let databaseTypes: [(DatabaseType, String)] = [
        (.mysql, "MySQL"),
        (.postgresql, "PostgreSQL"),
        (.sqlite, "SQLite"),
        (.redis, "Redis"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)

                    Picker("Database Type", selection: $type) {
                        ForEach(databaseTypes, id: \.0.rawValue) { dbType, label in
                            Text(label).tag(dbType)
                        }
                    }
                    .onChange(of: type) { _, newType in
                        updateDefaultPort(for: newType)
                        selectedFileURL = nil
                        database = ""
                    }
                }

                if type == .sqlite {
                    sqliteSection
                } else {
                    serverSection
                }

                if type != .sqlite && type != .redis {
                    Section {
                        Toggle("SSL", isOn: $sslEnabled)
                    }
                }
            }
            .navigationTitle("New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: sqliteContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFilePickerResult(result)
            }
            .alert("New Database", isPresented: $showNewDatabaseAlert) {
                TextField("Database name", text: $newDatabaseName)
                Button("Create") { createNewDatabase() }
                Button("Cancel", role: .cancel) { newDatabaseName = "" }
            } message: {
                Text("Enter a name for the new SQLite database.")
            }
        }
    }

    // MARK: - SQLite Section

    private var sqliteSection: some View {
        Section("Database File") {
            if let url = selectedFileURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.body)
                        Text(url.deletingLastPathComponent().lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        selectedFileURL = nil
                        database = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                showFilePicker = true
            } label: {
                Label("Open Database File", systemImage: "folder")
            }

            Button {
                showNewDatabaseAlert = true
            } label: {
                Label("Create New Database", systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Server Section (MySQL, PostgreSQL, Redis)

    private var serverSection: some View {
        Group {
            Section("Server") {
                TextField("Host", text: $host)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                TextField("Port", text: $port)
                    .keyboardType(.numberPad)

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $password)
            }

            Section("Database") {
                TextField("Database Name", text: $database)
                    .textInputAutocapitalization(.never)
            }
        }
    }

    // MARK: - Logic

    private var canSave: Bool {
        if type == .sqlite {
            return !database.isEmpty
        }
        return !host.isEmpty
    }

    private var sqliteContentTypes: [UTType] {
        [UTType.database, UTType(filenameExtension: "sqlite3") ?? .data, .data]
    }

    private func updateDefaultPort(for type: DatabaseType) {
        switch type {
        case .mysql, .mariadb: port = "3306"
        case .postgresql: port = "5432"
        case .redis: port = "6379"
        case .sqlite: port = ""
        default: port = "3306"
        }
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        // Save security-scoped bookmark for reopening after app restart
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            // Copy file to app's Documents for reliable access
            let destURL = copyToDocuments(url)
            selectedFileURL = destURL
            database = destURL.path
            if name.isEmpty {
                name = destURL.deletingPathExtension().lastPathComponent
            }

            // Store bookmark for original location reference
            BookmarkStore.save(bookmarkData, for: destURL.lastPathComponent)
        } catch {
            // Fallback: just use the file path directly
            selectedFileURL = url
            database = url.path
            if name.isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func copyToDocuments(_ sourceURL: URL) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destURL = documentsDir.appendingPathComponent(sourceURL.lastPathComponent)

        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
        return destURL
    }

    private func createNewDatabase() {
        guard !newDatabaseName.isEmpty else { return }

        let safeName = newDatabaseName.hasSuffix(".db") ? newDatabaseName : "\(newDatabaseName).db"
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDir.appendingPathComponent(safeName)

        // SQLite creates the file on first connect — just set the path
        selectedFileURL = fileURL
        database = fileURL.path
        if name.isEmpty {
            name = newDatabaseName
        }
        newDatabaseName = ""
    }

    private func save() {
        let connection = DatabaseConnection(
            name: name.isEmpty ? (selectedFileURL?.lastPathComponent ?? host) : name,
            type: type,
            host: host,
            port: Int(port) ?? 3306,
            username: username,
            database: database,
            sslEnabled: sslEnabled
        )

        if !password.isEmpty {
            try? appState.connectionManager.storePassword(password, for: connection.id)
        }

        onSave(connection)
    }
}

// MARK: - Bookmark Storage

enum BookmarkStore {
    private static let key = "com.TablePro.Mobile.bookmarks"

    static func save(_ data: Data, for filename: String) {
        var bookmarks = loadAll()
        bookmarks[filename] = data
        UserDefaults.standard.set(try? JSONEncoder().encode(bookmarks), forKey: key)
    }

    static func load(for filename: String) -> Data? {
        loadAll()[filename]
    }

    private static func loadAll() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return dict
    }
}
