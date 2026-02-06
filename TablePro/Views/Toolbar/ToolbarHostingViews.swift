//
//  ToolbarHostingViews.swift
//  TablePro
//
//  NSView wrappers for hosting SwiftUI content in NSToolbar.
//  Bridges SwiftUI views to AppKit NSToolbarItem.
//

import AppKit
import Combine
import SwiftUI

/// NSView that hosts SwiftUI ToolbarPrincipalContent
final class ToolbarPrincipalContentHostingView: NSView {
    // MARK: - Properties

    private let hostingController: NSHostingController<ToolbarPrincipalContent>
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(state: ConnectionToolbarState) {
        let content = ToolbarPrincipalContent(state: state)
        self.hostingController = NSHostingController(rootView: content)

        super.init(frame: .zero)

        setupHostingController()
        observeStateChanges(state: state)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupHostingController() {
        // Add hosting controller's view as subview
        addSubview(hostingController.view)

        // Pin to edges
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Set initial size based on fitting size
        let fittingSize = hostingController.view.fittingSize
        setFrameSize(fittingSize)
    }

    private func observeStateChanges(state: ConnectionToolbarState) {
        // Re-layout when tag changes (tag badge may appear/disappear)
        state.$tagId
            .sink { [weak self] _ in
                self?.invalidateIntrinsicContentSize()
                self?.needsLayout = true
            }
            .store(in: &cancellables)

        // Re-layout when connection name or database name changes (affects width)
        state.$connectionName
            .sink { [weak self] _ in
                self?.invalidateIntrinsicContentSize()
                self?.needsLayout = true
            }
            .store(in: &cancellables)

        state.$databaseName
            .sink { [weak self] _ in
                self?.invalidateIntrinsicContentSize()
                self?.needsLayout = true
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        // Return the fitting size of the hosted SwiftUI view
        let fittingSize = hostingController.view.fittingSize

        // Constrain maximum width to prevent excessive expansion
        let maxWidth: CGFloat = 600
        let width = min(fittingSize.width, maxWidth)

        return NSSize(width: width, height: fittingSize.height)
    }

    override func layout() {
        super.layout()
        hostingController.view.frame = bounds
    }
}
