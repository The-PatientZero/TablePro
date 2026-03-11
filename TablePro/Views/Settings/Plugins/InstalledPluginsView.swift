//
//  InstalledPluginsView.swift
//  TablePro
//

import AppKit
import SwiftUI
import TableProPluginKit
import UniformTypeIdentifiers

struct InstalledPluginsView: View {
    private let pluginManager = PluginManager.shared

    @State private var selectedPluginId: String?
    @State private var showErrorAlert = false
    @State private var errorAlertTitle = ""
    @State private var errorAlertMessage = ""
    @State private var dismissedRestartBanner = false

    var body: some View {
        Form {
            if pluginManager.needsRestart && !dismissedRestartBanner {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Restart TablePro to fully unload removed plugins.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            dismissedRestartBanner = true
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Installed Plugins") {
                ForEach(pluginManager.plugins) { plugin in
                    pluginRow(plugin)
                }
            }

            Section {
                HStack {
                    Button("Install from File...") {
                        installFromFile()
                    }
                    .disabled(pluginManager.isInstalling)

                    if pluginManager.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            if let selected = selectedPlugin {
                pluginDetailSection(selected)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first,
                  provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                return false
            }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let ext = url.pathExtension.lowercased()
                guard ext == "zip" || ext == "tableplugin" else { return }
                Task { @MainActor in
                    installPlugin(from: url)
                }
            }
            return true
        }
        .alert(errorAlertTitle, isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorAlertMessage)
        }
    }

    // MARK: - Plugin Row

    @ViewBuilder
    private func pluginRow(_ plugin: PluginEntry) -> some View {
        HStack {
            pluginIcon(plugin.iconName)
                .frame(width: 20)
                .foregroundStyle(plugin.isEnabled ? .primary : .tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .foregroundStyle(plugin.isEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(plugin.source == .builtIn ? "Built-in" : "User")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            plugin.source == .builtIn
                                ? Color.blue.opacity(0.15)
                                : Color.green.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                        .foregroundStyle(plugin.source == .builtIn ? .blue : .green)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { pluginManager.setEnabled($0, pluginId: plugin.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPluginId = selectedPluginId == plugin.id ? nil : plugin.id
            }
        }
    }

    @ViewBuilder
    private func pluginIcon(_ name: String) -> some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            Image(systemName: name)
        } else {
            Image(name)
                .renderingMode(.template)
        }
    }

    // MARK: - Detail Section

    private var selectedPlugin: PluginEntry? {
        guard let id = selectedPluginId else { return nil }
        return pluginManager.plugins.first { $0.id == id }
    }

    @ViewBuilder
    private func pluginDetailSection(_ plugin: PluginEntry) -> some View {
        Section(plugin.name) {
            LabeledContent("Version:", value: plugin.version)
            LabeledContent("Bundle ID:", value: plugin.id)
            LabeledContent("Source:", value: plugin.source == .builtIn
                ? String(localized: "Built-in")
                : String(localized: "User-installed"))

            if !plugin.capabilities.isEmpty {
                LabeledContent("Capabilities:") {
                    Text(plugin.capabilities.map(\.displayName).joined(separator: ", "))
                }
            }

            if let typeId = plugin.databaseTypeId {
                LabeledContent("Database Type:", value: typeId)

                if !plugin.additionalTypeIds.isEmpty {
                    LabeledContent("Also handles:", value: plugin.additionalTypeIds.joined(separator: ", "))
                }

                if let port = plugin.defaultPort {
                    LabeledContent("Default Port:", value: "\(port)")
                }
            }

            if !plugin.pluginDescription.isEmpty {
                Text(plugin.pluginDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let settable = pluginManager.pluginInstances[plugin.id] as? any SettablePluginDiscoverable,
               let pluginSettings = settable.settingsView() {
                Divider()
                pluginSettings
            }

            if plugin.source == .userInstalled {
                HStack {
                    Spacer()
                    Button("Uninstall", role: .destructive) {
                        uninstallPlugin(plugin)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func installFromFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Plugin")
        panel.allowedContentTypes = [.zip] + (UTType("com.tablepro.plugin").map { [$0] } ?? [])
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        installPlugin(from: url)
    }

    private func installPlugin(from url: URL) {
        Task {
            do {
                let entry = try await pluginManager.installPlugin(from: url)
                selectedPluginId = entry.id
            } catch {
                errorAlertTitle = String(localized: "Plugin Installation Failed")
                errorAlertMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func uninstallPlugin(_ plugin: PluginEntry) {
        Task { @MainActor in
            let confirmed = await AlertHelper.confirmDestructive(
                title: String(localized: "Uninstall Plugin?"),
                message: String(localized: "\"\(plugin.name)\" will be removed from your system. This action cannot be undone."),
                confirmButton: String(localized: "Uninstall"),
                cancelButton: String(localized: "Cancel")
            )

            guard confirmed else { return }

            do {
                try pluginManager.uninstallPlugin(id: plugin.id)
                selectedPluginId = nil
            } catch {
                errorAlertTitle = String(localized: "Uninstall Failed")
                errorAlertMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - PluginCapability Display Names

private extension PluginCapability {
    var displayName: String {
        switch self {
        case .databaseDriver: String(localized: "Database Driver")
        case .exportFormat: String(localized: "Export Format")
        case .importFormat: String(localized: "Import Format")
        }
    }
}

#Preview {
    InstalledPluginsView()
        .frame(width: 550, height: 500)
}
