//
//  DatabaseSwitcherSheet.swift
//  OpenTable
//
//  Modal sheet to display and switch between databases.
//  Similar to TablePlus's "Open database" feature (Cmd+K).
//

import SwiftUI

/// Modal sheet to display available databases and switch between them
struct DatabaseSwitcherSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    let currentDatabase: String?
    let databaseType: DatabaseType
    let onSelect: (String) -> Void

    @State private var databases: [String] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: String?
    @State private var shouldScrollToSelection = false
    @FocusState private var isListFocused: Bool

    var filteredDatabases: [String] {
        if searchText.isEmpty {
            return databases
        }
        return databases.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Open database")
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 12)

            Divider()

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 13))

                TextField("Search for database...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        openSelectedDatabase()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Database list or empty state
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if databaseType == .sqlite {
                sqliteEmptyState
            } else if filteredDatabases.isEmpty {
                emptyState
            } else {
                databaseListView
            }

            Divider()

            // Footer buttons
            footerView
        }
        .frame(width: 360, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadDatabases()
        }
        .onChange(of: searchText) { _, _ in
            // Reset selection when search changes
            selectedItem = filteredDatabases.first
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(up: true)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(up: false)
            return .handled
        }
        .onKeyPress(.return) {
            openSelectedDatabase()
            return .handled
        }
    }

    // MARK: - Database List

    private var databaseListView: some View {
        ScrollViewReader { proxy in
            List(filteredDatabases, id: \.self, selection: $selectedItem) { database in
                databaseRow(database)
                    .tag(database)
                    .id(database)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .environment(\.defaultMinListRowHeight, 28)
            .focusable()
            .focused($isListFocused)
            .onChange(of: filteredDatabases) { _, newList in
                // Reset selection when list changes
                if let selected = selectedItem, !newList.contains(selected) {
                    selectedItem = newList.first
                }
            }
            .onChange(of: selectedItem) { _, newValue in
                // Scroll to selected item when navigating with keyboard
                if let item = newValue {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(item, anchor: .center)
                    }
                }
            }
            .onChange(of: shouldScrollToSelection) { _, shouldScroll in
                // Scroll to selection after databases load
                if shouldScroll, let item = selectedItem {
                    // Scroll once the selection flag is set; defer focus to next runloop
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(item, anchor: .center)
                    }
                    shouldScrollToSelection = false

                    // Focus the list and underlying NSTableView to show blue selection
                    DispatchQueue.main.async {
                        isListFocused = true

                        // Find and focus NSTableView in sheet window
                        // Sheets become key window, or check attached sheets
                        if let sheetWindow = NSApp.keyWindow,
                           sheetWindow.isSheet || sheetWindow.sheetParent != nil,
                           let tableView = findTableView(in: sheetWindow.contentView) {
                            sheetWindow.makeFirstResponder(tableView)
                        } else if let mainWindow = NSApp.mainWindow,
                                  let sheet = mainWindow.attachedSheet,
                                  let tableView = findTableView(in: sheet.contentView) {
                            sheet.makeFirstResponder(tableView)
                        }
                    }
                }
            }
        }
    }

    private func databaseRow(_ database: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cylinder")
                .font(.system(size: 13))
                .foregroundStyle(database == currentDatabase ? .blue : .secondary)

            Text(database)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if database == currentDatabase {
                Text("current")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .overlay(
            DoubleClickView {
                selectedItem = database
                openSelectedDatabase()
            }
        )
    }

    // MARK: - Empty States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading databases...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.orange)

            Text("Failed to load databases")
                .font(.system(size: 13, weight: .medium))

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                loadDatabases()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sqliteEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            Text("SQLite is file-based")
                .font(.system(size: 13, weight: .medium))

            Text("Each SQLite file is a separate database.\nTo open a different database, create a new connection.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            if searchText.isEmpty {
                Text("No databases found")
                    .font(.system(size: 13, weight: .medium))
            } else {
                Text("No matching databases")
                    .font(.system(size: 13, weight: .medium))

                Text("No databases match \"\(searchText)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }

            Spacer()

            Button("Open") {
                openSelectedDatabase()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedItem == nil || selectedItem == currentDatabase)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func moveSelection(up: Bool) {
        guard !filteredDatabases.isEmpty else { return }

        // Determine the current index only if the selected item exists in the filtered list
        if let selected = selectedItem,
           let currentIndex = filteredDatabases.firstIndex(of: selected) {
            if up {
                let newIndex = max(0, currentIndex - 1)
                selectedItem = filteredDatabases[newIndex]
            } else {
                let newIndex = min(filteredDatabases.count - 1, currentIndex + 1)
                selectedItem = filteredDatabases[newIndex]
            }
        } else {
            // No valid current selection; choose a sensible starting point
            selectedItem = up ? filteredDatabases.last : filteredDatabases.first
        }
    }

    private func loadDatabases() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let driver = DatabaseManager.shared.activeDriver else {
                    await MainActor.run {
                        errorMessage = "No active connection"
                        isLoading = false
                    }
                    return
                }

                let result = try await driver.fetchDatabases()

                await MainActor.run {
                    databases = result
                    isLoading = false

                    // Pre-select current database if available
                    if let current = currentDatabase, result.contains(current) {
                        selectedItem = current
                    } else {
                        selectedItem = result.first
                    }

                    // Trigger scroll to selection and focus
                    shouldScrollToSelection = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func openSelectedDatabase() {
        guard let database = selectedItem else { return }

        // Don't reopen current database
        if database == currentDatabase {
            dismiss()
            return
        }

        onSelect(database)
        dismiss()
    }

    /// Recursively find NSTableView in view hierarchy
    private func findTableView(in view: NSView?) -> NSTableView? {
        guard let view = view else { return nil }

        if let tableView = view as? NSTableView {
            return tableView
        }

        for subview in view.subviews {
            if let found = findTableView(in: subview) {
                return found
            }
        }

        return nil
    }
}


// MARK: - DoubleClickView

/// NSViewRepresentable that detects double-clicks without interfering with native List selection
private struct DoubleClickView: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughDoubleClickView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PassThroughDoubleClickView)?.onDoubleClick = onDoubleClick
    }
}

private class PassThroughDoubleClickView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        }
        // Always forward to next responder for List selection
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }
}

// MARK: - Preview

#Preview("MySQL Databases") {
    DatabaseSwitcherSheet(
        isPresented: .constant(true),
        currentDatabase: "laravel",
        databaseType: .mysql,
        onSelect: { db in print("Selected: \(db)") }
    )
}

#Preview("SQLite Empty") {
    DatabaseSwitcherSheet(
        isPresented: .constant(true),
        currentDatabase: nil,
        databaseType: .sqlite,
        onSelect: { db in print("Selected: \(db)") }
    )
}
