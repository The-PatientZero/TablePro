//
//  ToolbarWindowConfigurator.swift
//  TablePro
//
//  Configures NSToolbar for SwiftUI windows.
//  Provides SwiftUI integration via NSViewRepresentable.
//

import AppKit
import SwiftUI

/// Configures NSToolbar for SwiftUI windows
@MainActor
final class ToolbarWindowConfigurator {
    // MARK: - Properties

    private var controller: ToolbarController?

    // MARK: - Configuration

    func configure(
        window: NSWindow,
        state: ConnectionToolbarState
    ) {
        // Only configure once
        guard controller == nil else { return }

        // CRITICAL: Remove any existing toolbar to avoid observer conflicts
        // SwiftUI may have set up its own toolbar with KVO observers
        if let existingToolbar = window.toolbar {
            // Clear delegate to stop observation
            existingToolbar.delegate = nil
            window.toolbar = nil
        }

        let factory = DefaultToolbarItemFactory()
        let controller = ToolbarController(
            identifier: NSToolbar.Identifier("com.TablePro.mainToolbar"),
            factory: factory,
            state: state
        )

        controller.attach(to: window)
        self.controller = controller
    }
}

// MARK: - SwiftUI Integration

/// SwiftUI view that configures the window's toolbar
/// Use this in the background of your main content view to attach the toolbar
struct ToolbarConfigurationView: NSViewRepresentable {
    @ObservedObject var state: ConnectionToolbarState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        // Start observing window to configure toolbar when available
        context.coordinator.startObserving(view: view, state: state)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Toolbar is configured once, no updates needed
        // State changes are handled by ToolbarController's Combine subscriptions
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private let configurator = ToolbarWindowConfigurator()
        private var windowObservation: NSKeyValueObservation?

        func startObserving(view: NSView, state: ConnectionToolbarState) {
            // Observe window property - configure when window becomes available
            windowObservation = view.observe(\.window, options: [.new, .initial]) { [weak self] _, change in
                guard let self = self,
                      let window = change.newValue as? NSWindow else { return }

                // Configure once, then stop observing
                Task { @MainActor in
                    self.configurator.configure(window: window, state: state)
                    self.windowObservation?.invalidate()
                    self.windowObservation = nil
                }
            }
        }

        deinit {
            windowObservation?.invalidate()
        }
    }
}

// MARK: - View Extension

extension View {
    /// Apply custom NSToolbar to this view's window
    /// This replaces the SwiftUI .toolbar() modifier
    ///
    /// Usage:
    /// ```swift
    /// mainContentView
    ///     .customToolbar(state: toolbarState)
    /// ```
    func customToolbar(state: ConnectionToolbarState) -> some View {
        self.background(
            ToolbarConfigurationView(state: state)
                .frame(width: 0, height: 0)  // Invisible bridge
        )
    }
}
