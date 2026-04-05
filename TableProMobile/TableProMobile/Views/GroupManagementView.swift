//
//  GroupManagementView.swift
//  TableProMobile
//

import SwiftUI
import TableProModels

struct GroupManagementView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var editingGroup: ConnectionGroup?
    @State private var showingAddGroup = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                    Button {
                        editingGroup = group
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(ConnectionColorPicker.swiftUIColor(for: group.color))
                                .frame(width: 12, height: 12)

                            Text(group.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            let count = appState.connections.filter { $0.groupId == group.id }.count
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            appState.deleteGroup(group.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    var sorted = appState.groups.sorted(by: { $0.sortOrder < $1.sortOrder })
                    sorted.move(fromOffsets: source, toOffset: destination)
                    for (index, group) in sorted.enumerated() {
                        var updated = group
                        updated.sortOrder = index
                        appState.updateGroup(updated)
                    }
                }
            }
            .overlay {
                if appState.groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups", systemImage: "folder")
                    } description: {
                        Text("Create a group to organize your connections.")
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button {
                        showingAddGroup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                GroupFormSheet { group in
                    appState.addGroup(group)
                }
            }
            .sheet(item: $editingGroup) { group in
                GroupFormSheet(editing: group) { updated in
                    appState.updateGroup(updated)
                }
            }
        }
    }
}
