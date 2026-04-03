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

    // SSH
    @State private var sshEnabled = false
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUsername = ""
    @State private var sshPassword = ""
    @State private var sshAuthMethod: SSHConfiguration.SSHAuthMethod = .password
    @State private var sshKeyPath = ""
    @State private var sshKeyContent = ""
    @State private var sshKeyPassphrase = ""
    @State private var sshKeyInputMode = KeyInputMode.file
    @State private var showSSHKeyPicker = false

    enum KeyInputMode: String, CaseIterable {
        case file = "Import File"
        case paste = "Paste Key"
    }

    // Test connection
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private let existingConnection: DatabaseConnection?
    var onSave: (DatabaseConnection) -> Void

    private let databaseTypes: [(DatabaseType, String)] = [
        (.mysql, "MySQL"),
        (.mariadb, "MariaDB"),
        (.postgresql, "PostgreSQL"),
        (.sqlite, "SQLite"),
        (.redis, "Redis"),
    ]

    init(editing connection: DatabaseConnection? = nil, onSave: @escaping (DatabaseConnection) -> Void) {
        self.existingConnection = connection
        self.onSave = onSave
        if let connection {
            _name = State(initialValue: connection.name)
            _type = State(initialValue: connection.type)
            _host = State(initialValue: connection.host)
            _port = State(initialValue: String(connection.port))
            _username = State(initialValue: connection.username)
            _database = State(initialValue: connection.database)
            _sslEnabled = State(initialValue: connection.sslEnabled)
            _sshEnabled = State(initialValue: connection.sshEnabled)
            if let ssh = connection.sshConfiguration {
                _sshHost = State(initialValue: ssh.host)
                _sshPort = State(initialValue: String(ssh.port))
                _sshUsername = State(initialValue: ssh.username)
                _sshAuthMethod = State(initialValue: ssh.authMethod)
                _sshKeyPath = State(initialValue: ssh.privateKeyPath ?? "")
                _sshKeyContent = State(initialValue: ssh.privateKeyData ?? "")
                if ssh.privateKeyData != nil && !ssh.privateKeyData!.isEmpty {
                    _sshKeyInputMode = State(initialValue: .paste)
                }
            }
            if connection.type == .sqlite {
                _selectedFileURL = State(initialValue: URL(fileURLWithPath: connection.database))
            }
        }
    }

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

                if type != .sqlite {
                    sshSection
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing...")
                            } else {
                                Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                    }
                    .disabled(isTesting || !canSave)

                    if let testResult {
                        HStack(spacing: 8) {
                            Image(systemName: testResult.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(testResult.success ? .green : .red)
                            Text(testResult.message)
                                .font(.footnote)
                                .foregroundStyle(testResult.success ? .green : .red)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existingConnection != nil ? "Edit Connection" : "New Connection")
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
            .fileImporter(
                isPresented: $showSSHKeyPicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }

                    // Read key content directly — more reliable than copying file
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        sshKeyContent = content
                        sshKeyInputMode = .paste
                    } else {
                        // Fallback: copy to app Documents
                        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                        let dest = docsDir.appendingPathComponent("ssh_" + url.lastPathComponent)
                        try? FileManager.default.removeItem(at: dest)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        sshKeyPath = dest.path
                    }
                }
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

    // MARK: - SSH Section

    @ViewBuilder
    private var sshSection: some View {
        Section {
            Toggle("SSH Tunnel", isOn: $sshEnabled)
        }

        if sshEnabled {
            Section("SSH Server") {
                TextField("SSH Host", text: $sshHost)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("SSH Port", text: $sshPort)
                    .keyboardType(.numberPad)
                TextField("SSH Username", text: $sshUsername)
                    .textInputAutocapitalization(.never)

                Picker("Auth Method", selection: $sshAuthMethod) {
                    Text("Password").tag(SSHConfiguration.SSHAuthMethod.password)
                    Text("Private Key").tag(SSHConfiguration.SSHAuthMethod.privateKey)
                }
            }

            if sshAuthMethod == .password {
                Section("SSH Password") {
                    SecureField("Password", text: $sshPassword)
                }
            } else {
                Section("Private Key") {
                    Picker("Input Method", selection: $sshKeyInputMode) {
                        ForEach(KeyInputMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if sshKeyInputMode == .file {
                        Button {
                            showSSHKeyPicker = true
                        } label: {
                            HStack {
                                Text(sshKeyPath.isEmpty
                                    ? "Select Private Key"
                                    : URL(fileURLWithPath: sshKeyPath).lastPathComponent)
                                Spacer()
                                Image(systemName: "folder")
                            }
                        }
                    } else {
                        TextEditor(text: $sshKeyContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 120)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .overlay(alignment: .topLeading) {
                                if sshKeyContent.isEmpty {
                                    Text("Paste private key (PEM format)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    SecureField("Passphrase (optional)", text: $sshKeyPassphrase)
                }
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

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let destURL = copyToDocuments(url)
        selectedFileURL = destURL
        database = destURL.path
        if name.isEmpty {
            name = destURL.deletingPathExtension().lastPathComponent
        }
    }

    private func copyToDocuments(_ sourceURL: URL) -> URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return sourceURL
        }
        let destURL = documentsDir.appendingPathComponent(sourceURL.lastPathComponent)

        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
        return destURL
    }

    private func createNewDatabase() {
        guard !newDatabaseName.isEmpty else { return }

        let safeName = newDatabaseName.hasSuffix(".db") ? newDatabaseName : "\(newDatabaseName).db"
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsDir.appendingPathComponent(safeName)

        selectedFileURL = fileURL
        database = fileURL.path
        if name.isEmpty {
            name = newDatabaseName
        }
        newDatabaseName = ""
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        let tempId = UUID()
        var testConn = buildConnection()
        testConn.id = tempId

        if !password.isEmpty {
            try? appState.connectionManager.storePassword(password, for: tempId)
        }

        let secureStore = KeychainSecureStore()
        if sshEnabled && !sshPassword.isEmpty {
            try? secureStore.store(sshPassword, forKey: "com.TablePro.sshpassword.\(tempId.uuidString)")
        }
        if sshEnabled && !sshKeyPassphrase.isEmpty {
            try? secureStore.store(sshKeyPassphrase, forKey: "com.TablePro.keypassphrase.\(tempId.uuidString)")
        }

        appState.sshProvider.pendingConnectionId = tempId

        do {
            _ = try await appState.connectionManager.connect(testConn)
            await appState.connectionManager.disconnect(tempId)
            testResult = TestResult(success: true, message: "Connection successful")
        } catch {
            testResult = TestResult(success: false, message: error.localizedDescription)
        }

        try? appState.connectionManager.deletePassword(for: tempId)
        try? secureStore.delete(forKey: "com.TablePro.sshpassword.\(tempId.uuidString)")
        try? secureStore.delete(forKey: "com.TablePro.keypassphrase.\(tempId.uuidString)")
        isTesting = false
    }

    private func buildConnection() -> DatabaseConnection {
        var conn = DatabaseConnection(
            id: existingConnection?.id ?? UUID(),
            name: name.isEmpty ? (selectedFileURL?.lastPathComponent ?? host) : name,
            type: type,
            host: host,
            port: Int(port) ?? 3306,
            username: username,
            database: database,
            sshEnabled: sshEnabled,
            sslEnabled: sslEnabled
        )
        if sshEnabled {
            conn.sshConfiguration = SSHConfiguration(
                host: sshHost,
                port: Int(sshPort) ?? 22,
                username: sshUsername,
                authMethod: sshAuthMethod,
                privateKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
                privateKeyData: sshKeyContent.isEmpty ? nil : sshKeyContent
            )
        }
        return conn
    }

    private func save() {
        let connection = buildConnection()

        if !password.isEmpty {
            try? appState.connectionManager.storePassword(password, for: connection.id)
        }

        if sshEnabled {
            let secureStore = KeychainSecureStore()


            if !sshPassword.isEmpty {
                try? secureStore.store(sshPassword, forKey: "com.TablePro.sshpassword.\(connection.id.uuidString)")
            }
            if !sshKeyPassphrase.isEmpty {
                try? secureStore.store(sshKeyPassphrase, forKey: "com.TablePro.keypassphrase.\(connection.id.uuidString)")
            }
        }

        onSave(connection)
    }
}

private struct TestResult {
    let success: Bool
    let message: String
}

