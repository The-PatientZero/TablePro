//
//  HistoryRowView.swift
//  TablePro
//
//  Table cell view for query history entries.
//  Extracted from HistoryListViewController for better maintainability.
//

import AppKit

/// Table cell view for query history entries
final class HistoryRowView: NSTableCellView {
    private let statusIcon: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let queryLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: DesignConstants.FontSize.small + 1, weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let secondaryLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: DesignConstants.FontSize.small)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: DesignConstants.FontSize.small)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let durationLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: DesignConstants.FontSize.small)
        label.textColor = .tertiaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var isSetup = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        guard !isSetup else { return }
        isSetup = true

        addSubview(statusIcon)
        addSubview(queryLabel)
        addSubview(secondaryLabel)
        addSubview(timeLabel)
        addSubview(durationLabel)

        NSLayoutConstraint.activate([
            // Status icon
            statusIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            statusIcon.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            statusIcon.widthAnchor.constraint(equalToConstant: 14),
            statusIcon.heightAnchor.constraint(equalToConstant: 14),

            // Query label (first line)
            queryLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 8),
            queryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            queryLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            // Secondary label (second line - database/tags)
            secondaryLabel.leadingAnchor.constraint(equalTo: queryLabel.leadingAnchor),
            secondaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            secondaryLabel.topAnchor.constraint(equalTo: queryLabel.bottomAnchor, constant: 2),

            // Time label (third line left)
            timeLabel.leadingAnchor.constraint(equalTo: queryLabel.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: secondaryLabel.bottomAnchor, constant: 2),

            // Duration label (third line right)
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            durationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: timeLabel.trailingAnchor, constant: 8)
        ])
    }

    func configureForHistory(_ entry: QueryHistoryEntry) {
        // Status icon
        let imageName = entry.wasSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill"
        statusIcon.image = NSImage(systemSymbolName: imageName, accessibilityDescription: entry.wasSuccessful ? "Success" : "Error")
        statusIcon.contentTintColor = entry.wasSuccessful ? .systemGreen : .systemRed

        // Query preview
        queryLabel.stringValue = entry.queryPreview

        // Database
        secondaryLabel.stringValue = entry.databaseName

        // Relative time
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timeLabel.stringValue = formatter.localizedString(for: entry.executedAt, relativeTo: Date())

        // Duration
        durationLabel.stringValue = entry.formattedExecutionTime
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        queryLabel.font = .monospacedSystemFont(ofSize: DesignConstants.FontSize.small + 1, weight: .regular)
        statusIcon.image = nil
        queryLabel.stringValue = ""
        secondaryLabel.stringValue = ""
        timeLabel.stringValue = ""
        durationLabel.stringValue = ""
    }
}
