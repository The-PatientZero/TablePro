//
//  NativeTabItemView.swift
//  TablePro
//
//  AppKit NSView subclass representing a single tab in the native tab bar.
//

import AppKit
import QuartzCore

/// Custom pasteboard type for tab drag-and-drop
private let tabPasteboardType = NSPasteboard.PasteboardType("com.TablePro.tab")

/// AppKit view representing a single tab item with native rendering
final class NativeTabItemView: NSView {
    // MARK: - Properties

    private(set) var tabId: UUID
    private var title: String
    private var isPinned: Bool
    private var isExecuting: Bool
    private var tabType: TabType
    private var isSelected: Bool = false
    private var isHovered: Bool = false
    private var isWindowKey: Bool = true

    // MARK: - Callbacks

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onTogglePin: ((UUID) -> Void)?
    var onCloseOthers: ((UUID) -> Void)?

    // MARK: - Subviews

    private let pinIcon = NSImageView()
    private let statusIcon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?

    // MARK: - Constants

    private static let height: CGFloat = 28
    private static let minWidth: CGFloat = 80
    private static let maxWidth: CGFloat = 200
    private static let cornerRadius: CGFloat = 6
    private static let horizontalPadding: CGFloat = 10
    private static let elementSpacing: CGFloat = 5

    // MARK: - Initialization

    init(tabId: UUID, title: String, isPinned: Bool, isExecuting: Bool, tabType: TabType) {
        self.tabId = tabId
        self.title = title
        self.isPinned = isPinned
        self.isExecuting = isExecuting
        self.tabType = tabType
        super.init(frame: .zero)
        setupSubviews()
        setupDragSource()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupSubviews() {
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius

        // Pin icon
        pinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pinIcon.contentTintColor = .systemOrange
        pinIcon.translatesAutoresizingMaskIntoConstraints = false
        pinIcon.setContentHuggingPriority(.required, for: .horizontal)
        pinIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(pinIcon)

        // Status icon (table/doc icon)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.setContentHuggingPriority(.required, for: .horizontal)
        statusIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(statusIcon)

        // Spinner
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.setContentHuggingPriority(.required, for: .horizontal)
        spinner.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(spinner)

        // Title label
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        // Close button
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close tab"
        )
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(closeButton)

        setupConstraints()
        updateAppearance()
    }

    private func setupConstraints() {
        let iconSize: CGFloat = 12

        NSLayoutConstraint.activate([
            // Self sizing
            heightAnchor.constraint(equalToConstant: Self.height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minWidth),
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth),

            // Pin icon
            pinIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            pinIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: iconSize),
            pinIcon.heightAnchor.constraint(equalToConstant: iconSize),

            // Status icon (after pin if visible, else at leading)
            statusIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: iconSize),
            statusIcon.heightAnchor.constraint(equalToConstant: iconSize),

            // Spinner (same position as status icon)
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: statusIcon.leadingAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),

            // Title label
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(
                equalTo: statusIcon.trailingAnchor,
                constant: Self.elementSpacing
            ),

            // Close button
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor,
                constant: Self.elementSpacing
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Self.horizontalPadding
            ),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14)
        ])

        // Status icon leading depends on pin visibility (will update dynamically)
        updateStatusIconLeading()
    }

    private var statusIconLeadingConstraint: NSLayoutConstraint?

    private func updateStatusIconLeading() {
        statusIconLeadingConstraint?.isActive = false
        if isPinned {
            statusIconLeadingConstraint = statusIcon.leadingAnchor.constraint(
                equalTo: pinIcon.trailingAnchor,
                constant: Self.elementSpacing
            )
        } else {
            statusIconLeadingConstraint = statusIcon.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Self.horizontalPadding
            )
        }
        statusIconLeadingConstraint?.isActive = true
    }

    // MARK: - Window Key State

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didBecomeKeyNotification, object: nil
        )
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResignKeyNotification, object: nil
        )

        guard let window = window else { return }
        isWindowKey = window.isKeyWindow

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowKeyStateChanged),
            name: NSWindow.didBecomeKeyNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowKeyStateChanged),
            name: NSWindow.didResignKeyNotification, object: window
        )

        updateAppearance()
    }

    @objc private func windowKeyStateChanged(_ notification: Notification) {
        isWindowKey = window?.isKeyWindow ?? true
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    // MARK: - Drag Source

    private func setupDragSource() {
        // Drag will be initiated in mouseDragged
    }

    // MARK: - Update

    func update(title: String, isPinned: Bool, isExecuting: Bool, tabType: TabType, isSelected: Bool) {
        self.title = title
        self.isPinned = isPinned
        self.isExecuting = isExecuting
        self.tabType = tabType
        self.isSelected = isSelected
        updateStatusIconLeading()
        updateAppearance()
    }

    private func updateAppearance() {
        // Pin icon visibility
        pinIcon.isHidden = !isPinned

        // Spinner / status icon
        if isExecuting {
            spinner.isHidden = false
            spinner.startAnimation(nil)
            statusIcon.isHidden = true
        } else {
            spinner.isHidden = true
            spinner.stopAnimation(nil)
            statusIcon.isHidden = false

            let symbolName = tabType == .table ? "tablecells" : "doc.text"
            statusIcon.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: tabType == .table ? "Table" : "Query"
            )
            statusIcon.contentTintColor = tabType == .table ? .systemBlue : .secondaryLabelColor
        }

        // Title
        titleLabel.stringValue = title
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor

        // Close button (visible on hover, hidden for pinned tabs)
        closeButton.isHidden = !isHovered || isPinned

        // Background — wrap in CATransaction to suppress implicit animations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if self.isSelected {
                self.layer?.backgroundColor = NSColor.controlAccentColor
                    .withAlphaComponent(0.15).cgColor
            } else if self.isHovered {
                self.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            } else {
                self.layer?.backgroundColor = nil
            }
        }
        CATransaction.commit()
    }

    // MARK: - Mouse Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(tabId)
    }

    override func mouseDragged(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tabId.uuidString, forType: tabPasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        // Create drag image from current view
        let image = snapshot()
        draggingItem.setDraggingFrame(bounds, contents: image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let context = NSGraphicsContext.current {
            layer?.render(in: context.cgContext)
        }
        image.unlockFocus()
        return image
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let duplicateItem = NSMenuItem(title: "Duplicate Tab", action: #selector(duplicateTab), keyEquivalent: "")
        duplicateItem.target = self
        menu.addItem(duplicateItem)

        let pinTitle = isPinned ? "Unpin Tab" : "Pin Tab"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinTab), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)

        menu.addItem(.separator())

        let closeAction: Selector? = isPinned ? nil : #selector(closeTab)
        let closeItem = NSMenuItem(title: "Close Tab", action: closeAction, keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        let closeOthersItem = NSMenuItem(
            title: "Close Other Tabs",
            action: #selector(closeOtherTabs),
            keyEquivalent: ""
        )
        closeOthersItem.target = self
        menu.addItem(closeOthersItem)

        return menu
    }

    // MARK: - Actions

    @objc private func closeButtonClicked() {
        onClose?(tabId)
    }

    @objc private func duplicateTab() {
        onDuplicate?(tabId)
    }

    @objc private func togglePinTab() {
        onTogglePin?(tabId)
    }

    @objc private func closeTab() {
        onClose?(tabId)
    }

    @objc private func closeOtherTabs() {
        onCloseOthers?(tabId)
    }
}

// MARK: - NSDraggingSource

extension NativeTabItemView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
}
