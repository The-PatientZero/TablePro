//
//  NativeTabBarView.swift
//  TablePro
//
//  AppKit NSView containing the full native tab bar with scroll, drag-and-drop, and + button.
//

import AppKit

/// Custom pasteboard type for tab drag-and-drop
private let tabPasteboardType = NSPasteboard.PasteboardType("com.TablePro.tab")

/// Lightweight snapshot of a QueryTab for passing to AppKit layer
struct TabSnapshot: Equatable {
    let id: UUID
    let title: String
    let isPinned: Bool
    let isExecuting: Bool
    let tabType: TabType
}

/// AppKit container view for the native tab bar
final class NativeTabBarView: NSView {
    // MARK: - Callbacks

    var onTabSelect: ((UUID) -> Void)?
    var onTabClose: ((UUID) -> Void)?
    var onTabReorder: ((Int, Int) -> Void)?
    var onAddTab: (() -> Void)?
    var onDuplicateTab: ((UUID) -> Void)?
    var onTogglePin: ((UUID) -> Void)?
    var onCloseOtherTabs: ((UUID) -> Void)?

    // MARK: - State

    private var tabSnapshots: [TabSnapshot] = []
    private var selectedTabId: UUID?
    private var tabViews: [UUID: NativeTabItemView] = [:]

    // MARK: - Subviews

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let addButton = NSButton()
    private let insertionIndicator = NSView()

    // MARK: - Constants

    private static let barHeight: CGFloat = 32
    private static let addButtonSize: CGFloat = 28
    private static let addButtonTrailingPadding: CGFloat = 8

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        registerForDraggedTypes([tabPasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Stack view (horizontal, inside scroll)
        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        // Scroll view
        scrollView.documentView = stackView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Add button
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.imageScaling = .scaleProportionallyDown
        addButton.target = self
        addButton.action = #selector(addButtonClicked)
        addButton.toolTip = "New Query Tab (⌘T)"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        // Insertion indicator (shown during drag)
        insertionIndicator.wantsLayer = true
        insertionIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        insertionIndicator.layer?.cornerRadius = 1
        insertionIndicator.isHidden = true
        insertionIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(insertionIndicator)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Self height
            heightAnchor.constraint(equalToConstant: Self.barHeight),

            // Scroll view
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(
                equalTo: addButton.leadingAnchor,
                constant: -4
            ),

            // Stack view height = scroll view
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            // Add button
            addButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Self.addButtonTrailingPadding
            ),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: Self.addButtonSize),
            addButton.heightAnchor.constraint(equalToConstant: Self.addButtonSize),

            // Insertion indicator size
            insertionIndicator.widthAnchor.constraint(equalToConstant: 2),
            insertionIndicator.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    // MARK: - Public API

    func updateTabs(_ snapshots: [TabSnapshot], selectedId: UUID?) {
        self.tabSnapshots = snapshots
        self.selectedTabId = selectedId

        let snapshotIds = Set(snapshots.map(\.id))

        // Remove stale views
        for (id, view) in tabViews where !snapshotIds.contains(id) {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
            tabViews.removeValue(forKey: id)
        }

        // Add or update views in order
        var arrangedViews: [NSView] = []
        for snapshot in snapshots {
            let view: NativeTabItemView
            if let existing = tabViews[snapshot.id] {
                view = existing
            } else {
                view = makeTabItemView(for: snapshot)
                tabViews[snapshot.id] = view
            }

            view.update(
                title: snapshot.title,
                isPinned: snapshot.isPinned,
                isExecuting: snapshot.isExecuting,
                tabType: snapshot.tabType,
                isSelected: snapshot.id == selectedId
            )
            arrangedViews.append(view)
        }

        // Reorder stack view to match snapshot order
        let currentArranged = stackView.arrangedSubviews
        if currentArranged.map({ ($0 as? NativeTabItemView)?.tabId }) != snapshots.map(\.id) {
            // Remove all and re-add in correct order
            for subview in currentArranged {
                stackView.removeArrangedSubview(subview)
            }
            for view in arrangedViews {
                stackView.addArrangedSubview(view)
            }
        }

        // Scroll to selected tab
        scrollToSelectedTab()
    }

    // MARK: - Private Helpers

    private func makeTabItemView(for snapshot: TabSnapshot) -> NativeTabItemView {
        let view = NativeTabItemView(
            tabId: snapshot.id,
            title: snapshot.title,
            isPinned: snapshot.isPinned,
            isExecuting: snapshot.isExecuting,
            tabType: snapshot.tabType
        )

        view.onSelect = { [weak self] id in self?.onTabSelect?(id) }
        view.onClose = { [weak self] id in self?.onTabClose?(id) }
        view.onDuplicate = { [weak self] id in self?.onDuplicateTab?(id) }
        view.onTogglePin = { [weak self] id in self?.onTogglePin?(id) }
        view.onCloseOthers = { [weak self] id in self?.onCloseOtherTabs?(id) }

        return view
    }

    private func scrollToSelectedTab() {
        guard let selectedId = selectedTabId,
              let view = tabViews[selectedId] else { return }
        // Convert view frame to scroll view coordinate space
        let frameInScroll = view.convert(view.bounds, to: scrollView.documentView)
        scrollView.contentView.scrollToVisible(frameInScroll)
    }

    // MARK: - Actions

    @objc private func addButtonClicked() {
        onAddTab?()
    }

    // MARK: - Drag Destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadItem(
            withDataConformingToTypes: [tabPasteboardType.rawValue]
        ) else {
            return []
        }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let insertionIndex = insertionIndexForDrop(at: location)
        showInsertionIndicator(at: insertionIndex)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideInsertionIndicator()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hideInsertionIndicator()

        guard let items = sender.draggingPasteboard.pasteboardItems,
              let item = items.first,
              let uuidString = item.string(forType: tabPasteboardType),
              let draggedId = UUID(uuidString: uuidString) else {
            return false
        }

        let location = convert(sender.draggingLocation, from: nil)
        let toIndex = insertionIndexForDrop(at: location)

        guard let fromIndex = tabSnapshots.firstIndex(where: { $0.id == draggedId }) else {
            return false
        }

        if fromIndex != toIndex && fromIndex != toIndex - 1 {
            onTabReorder?(fromIndex, toIndex > fromIndex ? toIndex - 1 : toIndex)
        }

        return true
    }

    private func insertionIndexForDrop(at point: NSPoint) -> Int {
        let locationInStack = convert(point, to: stackView)
        let arrangedSubviews = stackView.arrangedSubviews

        for (index, subview) in arrangedSubviews.enumerated() {
            let midX = subview.frame.midX
            if locationInStack.x < midX {
                return index
            }
        }

        return arrangedSubviews.count
    }

    private func showInsertionIndicator(at index: Int) {
        let arrangedSubviews = stackView.arrangedSubviews
        guard !arrangedSubviews.isEmpty else {
            hideInsertionIndicator()
            return
        }

        insertionIndicator.isHidden = false

        let xPosition: CGFloat
        if index < arrangedSubviews.count {
            let targetView = arrangedSubviews[index]
            let frameInSelf = targetView.convert(targetView.bounds, to: self)
            xPosition = frameInSelf.minX - 1
        } else {
            let lastView = arrangedSubviews[arrangedSubviews.count - 1]
            let frameInSelf = lastView.convert(lastView.bounds, to: self)
            xPosition = frameInSelf.maxX + 1
        }

        insertionIndicator.frame = NSRect(
            x: xPosition,
            y: (bounds.height - 20) / 2,
            width: 2,
            height: 20
        )
    }

    private func hideInsertionIndicator() {
        insertionIndicator.isHidden = true
    }

    // MARK: - Dark Mode

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        // Re-render tab items to update colors
        for snapshot in tabSnapshots {
            tabViews[snapshot.id]?.update(
                title: snapshot.title,
                isPinned: snapshot.isPinned,
                isExecuting: snapshot.isExecuting,
                tabType: snapshot.tabType,
                isSelected: snapshot.id == selectedTabId
            )
        }
    }
}
