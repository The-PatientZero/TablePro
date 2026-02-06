//
//  HistoryListViewController.swift
//  TablePro
//
//  Left pane controller for query history list with search and filtering.
//  Child views and data provider extracted to separate files.
//

import AppKit

// MARK: - Delegate Protocol

protocol HistoryListViewControllerDelegate: AnyObject {
    func historyListViewController(
        _ controller: HistoryListViewController, didSelectHistoryEntry entry: QueryHistoryEntry)
    func historyListViewController(
        _ controller: HistoryListViewController, didDoubleClickHistoryEntry entry: QueryHistoryEntry
    )
    func historyListViewControllerDidClearSelection(_ controller: HistoryListViewController)
}

// MARK: - UI Date Filter

enum UIDateFilter: Int {
    case today = 0
    case week = 1
    case month = 2
    case all = 3

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .all: return "All Time"
        }
    }

    var toDateFilter: DateFilter {
        switch self {
        case .today: return .today
        case .week: return .thisWeek
        case .month: return .thisMonth
        case .all: return .all
        }
    }
}

// MARK: - HistoryListViewController

final class HistoryListViewController: NSViewController, NSMenuItemValidation {
    // MARK: - Properties

    weak var delegate: HistoryListViewControllerDelegate?

    private let dataProvider = HistoryDataProvider()

    private var dateFilter: UIDateFilter = .all {
        didSet {
            if oldValue != dateFilter {
                dataProvider.dateFilter = dateFilter
                loadData()
            }
        }
    }

    private var searchText: String = "" {
        didSet {
            dataProvider.searchText = searchText
            scheduleSearch()
        }
    }

    private var pendingDeletionRow: Int?
    private var pendingDeletionCount: Int?

    // MARK: - UI Components

    private let headerView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var searchField: NSSearchField = {
        let field = NSSearchField()
        field.placeholderString = "Search queries..."
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.controlSize = .small
        return field
    }()

    private lazy var filterButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        for filter in [UIDateFilter.today, .week, .month, .all] {
            button.addItem(withTitle: filter.title)
        }
        button.selectItem(at: UIDateFilter.all.rawValue)
        button.target = self
        button.action = #selector(filterChanged(_:))
        return button
    }()

    private lazy var clearAllButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear All")
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(clearAllClicked(_:))
        button.toolTip = "Clear all history"
        return button
    }()

    private let scrollView: NSScrollView = {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        return scroll
    }()

    private lazy var tableView: HistoryTableView = {
        let table = HistoryTableView()
        table.style = .plain
        table.headerView = nil
        table.rowHeight = DesignConstants.RowHeight.comfortable
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.doubleAction = #selector(tableViewDoubleClick(_:))
        table.target = self
        table.keyboardDelegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        column.width = 300
        table.addTableColumn(column)

        return table
    }()

    private lazy var emptyStateView: NSView = {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
        ])
        imageView.contentTintColor = .tertiaryLabelColor
        self.emptyImageView = imageView

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        self.emptyTitleLabel = titleLabel

        let subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.preferredMaxLayoutWidth = 200
        self.emptySubtitleLabel = subtitleLabel

        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }()

    private weak var emptyImageView: NSImageView?
    private weak var emptyTitleLabel: NSTextField?
    private weak var emptySubtitleLabel: NSTextField?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
        restoreState()
        loadDataAsync()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(headerView)

        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        let topRow = NSStackView(views: [NSView(), clearAllButton, filterButton])
        topRow.distribution = .fill
        topRow.spacing = 8

        headerStack.addArrangedSubview(topRow)
        headerStack.addArrangedSubview(searchField)

        headerView.addSubview(headerStack)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        scrollView.documentView = tableView
        view.addSubview(scrollView)
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            headerStack.topAnchor.constraint(equalTo: headerView.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            divider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(historyDidUpdate), name: .queryHistoryDidUpdate, object: nil)
    }

    // MARK: - State Persistence

    private func restoreState() {
        let savedFilter = UserDefaults.standard.integer(forKey: "HistoryPanel.dateFilter")

        if let filter = UIDateFilter(rawValue: savedFilter) {
            dateFilter = filter
            filterButton.selectItem(at: filter.rawValue)
        }
    }

    private func saveState() {
        UserDefaults.standard.set(dateFilter.rawValue, forKey: "HistoryPanel.dateFilter")
    }

    // MARK: - Data Loading

    private func loadData() {
        dataProvider.loadData()
        tableView.reloadData()
        updateEmptyState()

        if let deletedRow = pendingDeletionRow, let countBefore = pendingDeletionCount {
            selectRowAfterDeletion(deletedRow: deletedRow, countBefore: countBefore)
            pendingDeletionRow = nil
            pendingDeletionCount = nil
        } else if tableView.selectedRow < 0 {
            delegate?.historyListViewControllerDidClearSelection(self)
        }
    }

    private func loadDataAsync() {
        dataProvider.loadDataAsync { [weak self] in
            guard let self = self else { return }
            self.tableView.reloadData()
            self.updateEmptyState()

            if let deletedRow = self.pendingDeletionRow, let countBefore = self.pendingDeletionCount
            {
                self.selectRowAfterDeletion(deletedRow: deletedRow, countBefore: countBefore)
                self.pendingDeletionRow = nil
                self.pendingDeletionCount = nil
            } else if self.tableView.selectedRow < 0 {
                self.delegate?.historyListViewControllerDidClearSelection(self)
            }
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        dataProvider.scheduleSearch { [weak self] in
            self?.tableView.reloadData()
            self?.updateEmptyState()
        }
    }

    // MARK: - Actions

    @objc private func filterChanged(_ sender: NSPopUpButton) {
        if let filter = UIDateFilter(rawValue: sender.indexOfSelectedItem) {
            dateFilter = filter
            saveState()
        }
    }

    @objc private func tableViewDoubleClick(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }

        guard let entry = dataProvider.historyEntry(at: row) else { return }
        delegate?.historyListViewController(self, didDoubleClickHistoryEntry: entry)
    }

    @objc private func historyDidUpdate() {
        loadData()
    }

    @objc private func clearAllClicked(_ sender: Any?) {
        let count = dataProvider.count
        let itemName = count == 1 ? "history entry" : "history entries"

        guard count > 0 else { return }

        Task { @MainActor in
            let confirmed = await AlertHelper.confirmDestructive(
                title: "Clear All History?",
                message:
                    "This will permanently delete \(count) \(itemName). This action cannot be undone.",
                confirmButton: "Clear All",
                cancelButton: "Cancel"
            )

            if confirmed {
                _ = dataProvider.clearAll()
            }
        }
    }

    // MARK: - UI Updates

    private func updateEmptyState() {
        let isEmpty = dataProvider.isEmpty
        emptyStateView.isHidden = !isEmpty
        scrollView.isHidden = isEmpty

        guard isEmpty else { return }

        let isSearching = !searchText.isEmpty

        if isSearching {
            emptyImageView?.image = NSImage(
                systemSymbolName: "magnifyingglass", accessibilityDescription: "No results")
            emptyTitleLabel?.stringValue = "No Matching Queries"
            emptySubtitleLabel?.stringValue = "Try adjusting your search terms\nor date filter."
        } else {
            emptyImageView?.image = NSImage(
                systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "No history")
            emptyTitleLabel?.stringValue = "No Query History Yet"
            emptySubtitleLabel?.stringValue =
                "Your executed queries will\nappear here for quick access."
        }
    }

    // MARK: - Context Menu

    private func buildContextMenu(for row: Int) -> NSMenu {
        let menu = NSMenu()

        let copyItem = NSMenuItem(
            title: "Copy Query", action: #selector(copyQuery(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.tag = row
        menu.addItem(copyItem)

        let runItem = NSMenuItem(
            title: "Run in New Tab", action: #selector(runInNewTab(_:)), keyEquivalent: "\r")
        runItem.tag = row
        menu.addItem(runItem)

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(
            title: "Delete", action: #selector(deleteEntry(_:)), keyEquivalent: "\u{8}")
        deleteItem.keyEquivalentModifierMask = []
        deleteItem.tag = row
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func copyQuery(_ sender: NSMenuItem) {
        guard let query = dataProvider.query(at: sender.tag) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(query, forType: .string)
    }

    @objc private func runInNewTab(_ sender: NSMenuItem) {
        guard let query = dataProvider.query(at: sender.tag) else { return }

        NotificationCenter.default.post(name: .newTab, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .loadQueryIntoEditor, object: query)
        }
    }

    @objc private func deleteEntry(_ sender: NSMenuItem) {
        _ = dataProvider.deleteItem(at: sender.tag)
    }

    // MARK: - Selection After Deletion

    private func selectRowAfterDeletion(deletedRow: Int, countBefore: Int) {
        let currentCount = dataProvider.count

        guard currentCount > 0 else {
            tableView.deselectAll(nil)
            delegate?.historyListViewControllerDidClearSelection(self)
            return
        }

        let newSelection = deletedRow < currentCount ? deletedRow : currentCount - 1
        tableView.selectRowIndexes(IndexSet(integer: newSelection), byExtendingSelection: false)
        tableView.scrollRowToVisible(newSelection)

        if let entry = dataProvider.historyEntry(at: newSelection) {
            delegate?.historyListViewController(self, didSelectHistoryEntry: entry)
        }
    }
}

// MARK: - NSTableViewDataSource

extension HistoryListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        dataProvider.count
    }
}

// MARK: - NSTableViewDelegate

extension HistoryListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
    {
        guard let entry = dataProvider.historyEntry(at: row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: nil) as? HistoryRowView
            ?? HistoryRowView()
        cell.identifier = identifier
        cell.configureForHistory(entry)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else {
            delegate?.historyListViewControllerDidClearSelection(self)
            return
        }

        if let entry = dataProvider.historyEntry(at: row) {
            delegate?.historyListViewController(self, didSelectHistoryEntry: entry)
        }
    }

    func tableView(
        _ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge
    ) -> [NSTableViewRowAction] {
        if edge == .trailing {
            let delete = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, row in
                _ = self?.dataProvider.deleteItem(at: row)
            }
            return [delete]
        }
        return []
    }
}

// MARK: - NSSearchFieldDelegate

extension HistoryListViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSSearchField {
            searchText = field.stringValue
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
    {
        if commandSelector == #selector(cancelOperation(_:)) {
            if !searchText.isEmpty {
                searchField.stringValue = ""
                searchText = ""
                return true
            }
        }
        return false
    }
}

// MARK: - Context Menu

extension HistoryListViewController {
    override func rightMouseDown(with event: NSEvent) {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)

        if row >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            let menu = buildContextMenu(for: row)
            NSMenu.popUpContextMenu(menu, with: event, for: tableView)
        }
    }
}

// MARK: - HistoryTableViewKeyboardDelegate

extension HistoryListViewController: HistoryTableViewKeyboardDelegate {
    func handleDeleteKey() {
        deleteSelectedRow()
    }

    @objc func delete(_ sender: Any?) {
        deleteSelectedRow()
    }

    @objc func copy(_ sender: Any?) {
        copyQueryForSelectedRow()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(delete(_:)) {
            return tableView.selectedRow >= 0 && !dataProvider.isEmpty
        }
        if menuItem.action == #selector(copy(_:)) {
            return tableView.selectedRow >= 0
        }
        return true
    }

    func handleReturnKey() {
        runInNewTabForSelectedRow()
    }

    func handleSpaceKey() {
        // Preview panel - future implementation
    }

    /// Handle ESC key - clear search or selection (responder chain method)
    @objc override func cancelOperation(_ sender: Any?) {
        if !searchText.isEmpty {
            searchField.stringValue = ""
            searchText = ""
            searchField.window?.makeFirstResponder(tableView)
        } else if tableView.selectedRow >= 0 {
            tableView.deselectAll(nil)
        }
    }

    func deleteSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0 else { return }

        pendingDeletionRow = row
        pendingDeletionCount = dataProvider.count
        _ = dataProvider.deleteItem(at: row)
    }

    private func copyQueryForSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0, let query = dataProvider.query(at: row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(query, forType: .string)
    }

    private func runInNewTabForSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0, let query = dataProvider.query(at: row) else { return }

        NotificationCenter.default.post(name: .newTab, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .loadQueryIntoEditor, object: query)
        }
    }
}
