//
//  NativeTabBar.swift
//  TablePro
//
//  NSViewRepresentable bridge wrapping NativeTabBarView for use in SwiftUI.
//

import SwiftUI

/// SwiftUI wrapper for the native AppKit tab bar
struct NativeTabBar: NSViewRepresentable {
    @ObservedObject var tabManager: QueryTabManager

    func makeNSView(context: Context) -> NativeTabBarView {
        let view = NativeTabBarView()

        view.onTabSelect = { [weak tabManager] id in
            guard let tab = tabManager?.tabs.first(where: { $0.id == id }) else { return }
            tabManager?.selectTab(tab)
        }

        view.onTabClose = { [weak tabManager] id in
            guard let tab = tabManager?.tabs.first(where: { $0.id == id }) else { return }
            tabManager?.closeTab(tab)
        }

        view.onTabReorder = { [weak tabManager] fromIndex, toIndex in
            guard let tabManager = tabManager,
                  fromIndex >= 0, fromIndex < tabManager.tabs.count,
                  toIndex >= 0, toIndex < tabManager.tabs.count,
                  fromIndex != toIndex else { return }
            let tab = tabManager.tabs.remove(at: fromIndex)
            tabManager.tabs.insert(tab, at: toIndex)
        }

        view.onAddTab = { [weak tabManager] in
            tabManager?.addTab()
        }

        view.onDuplicateTab = { [weak tabManager] id in
            guard let tab = tabManager?.tabs.first(where: { $0.id == id }) else { return }
            tabManager?.duplicateTab(tab)
        }

        view.onTogglePin = { [weak tabManager] id in
            guard let tab = tabManager?.tabs.first(where: { $0.id == id }) else { return }
            tabManager?.togglePin(tab)
        }

        view.onCloseOtherTabs = { [weak tabManager] id in
            guard let tabManager = tabManager else { return }
            let kept = tabManager.tabs.filter { $0.id == id || $0.isPinned }
            tabManager.tabs = kept.isEmpty ? [] : kept
            tabManager.selectedTabId = id
        }

        return view
    }

    func updateNSView(_ nsView: NativeTabBarView, context: Context) {
        let snapshots = tabManager.tabs.map { tab in
            TabSnapshot(
                id: tab.id,
                title: tab.title,
                isPinned: tab.isPinned,
                isExecuting: tab.isExecuting,
                tabType: tab.tabType
            )
        }
        nsView.updateTabs(snapshots, selectedId: tabManager.selectedTabId)
    }
}
