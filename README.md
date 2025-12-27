# TablePro

A native macOS database client built with SwiftUI and AppKit, designed as a fast, lightweight alternative to TablePlus. TablePro prioritizes Apple-native frameworks and system libraries for optimal performance and native macOS experience.

## Features

### Multi-Database Support
- **MySQL/MariaDB** via native MariaDB Connector/C
- **PostgreSQL** via libpq
- **SQLite** via native SQLite C API

### Connection Management
- Multiple saved connection profiles with color-coded tags
- Secure credential storage using macOS Keychain
- SSH tunnel support with system SSH integration
- Connection testing before save
- Session-based connection management with state preservation

### Advanced Query Editor
- SQL syntax highlighting with native NSTextView
- Multi-tab query interface (Query and Table tabs)
- Execute queries with `Cmd+Enter`
- Query-at-cursor execution
- Line numbers and code folding
- Tab persistence across app sessions

### Intelligent SQL Autocomplete
- Context-aware suggestions based on cursor position
- Table and column name completion with alias support
- 50+ SQL functions organized by category (aggregate, date/time, string, numeric)
- SQL snippets for common query patterns
- Schema-aware suggestions using native driver metadata
- Keyboard navigation with `Up/Down/Enter/Escape`
- Manual trigger with `Ctrl+Space`

### High-Performance Data Grid
- NSTableView-based grid optimized for large datasets
- Virtual scrolling for handling millions of rows
- Row numbers column
- Column resizing and reordering
- Alternating row colors for readability
- Multiple row selection

### Inline Cell Editing with Change Tracking
- Double-click to edit any cell
- NULL value display with italic gray placeholder
- Empty string and DEFAULT value support
- Modified cells highlighted with yellow background
- Context menu: Set NULL/Empty/Default, Copy value
- Undo/Redo support for cell edits
- Auto-generated UPDATE/INSERT/DELETE statements
- Batch commit with `Cmd+S`
- Discard changes and restore original values

### Table Structure View
- View columns with types, nullable status, and defaults
- View indexes with primary/unique indicators
- View foreign keys with ON DELETE/UPDATE rules
- DDL preview for CREATE TABLE statements
- Toggle between Data and Structure views

### Data Export
- Export to CSV with proper escaping
- Export to JSON (pretty-printed)
- Copy to clipboard as tab-separated values

### Advanced Filtering
- Quick search across all columns
- Column-specific filters with operators (=, !=, >, <, LIKE, IN, IS NULL, etc.)
- Filter presets for saving and reusing filters
- SQL preview of generated WHERE clauses
- Persistent filter settings per table

### Query History & Bookmarks
- Automatic query history tracking with timestamps
- Search and filter query history
- Bookmark frequently used queries
- Query history panel with keyboard navigation

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Enter` | Execute query |
| `Cmd+S` | Save/commit changes |
| `Cmd+R` | Refresh data |
| `Cmd+W` | Close tab |
| `Cmd+N` | New connection |
| `Cmd+T` | New query tab |
| `Cmd+E` | Export to CSV |
| `Cmd+Shift+E` | Export to JSON |
| `Ctrl+Space` | Trigger autocomplete |

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later
- For MySQL/MariaDB: `brew install mariadb-connector-c` (compilation only)
- For PostgreSQL: `brew install libpq` (compilation only)
- For SQLite: No additional requirements (uses native libsqlite3)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/datlechin/TablePro.git
   cd TablePro
   ```

2. Install build dependencies:
   ```bash
   brew install mariadb-connector-c libpq
   ```

3. Open `TablePro.xcodeproj` in Xcode

4. Build and run (`Cmd+R`)

## Build from Command Line

```bash
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build
```

## Architecture

### Project Structure

```
TablePro/
├── Core/
│   ├── Autocomplete/         # SQL autocomplete system
│   │   ├── CompletionEngine.swift
│   │   ├── SQLCompletionProvider.swift
│   │   ├── SQLContextAnalyzer.swift
│   │   ├── SQLSchemaProvider.swift
│   │   └── SQLKeywords.swift
│   ├── ChangeTracking/       # Data change management
│   │   ├── DataChangeManager.swift
│   │   ├── DataChangeModels.swift
│   │   ├── DataChangeUndoManager.swift
│   │   └── SQLStatementGenerator.swift
│   ├── Database/             # Database drivers and connections
│   │   ├── DatabaseDriver.swift (protocol)
│   │   ├── MySQLDriver.swift
│   │   ├── PostgreSQLDriver.swift
│   │   ├── SQLiteDriver.swift
│   │   ├── MariaDBConnection.swift
│   │   ├── LibPQConnection.swift
│   │   └── DatabaseManager.swift
│   ├── Services/             # Core services
│   │   ├── QueryExecutionService.swift
│   │   ├── RowOperationsManager.swift
│   │   ├── TableQueryBuilder.swift
│   │   └── TabPersistenceService.swift
│   ├── SSH/                  # SSH tunnel support
│   │   ├── SSHTunnelManager.swift
│   │   └── SSHConfigParser.swift
│   └── Storage/              # Persistence layer
│       ├── ConnectionStorage.swift
│       ├── QueryHistoryStorage.swift
│       ├── TabStateStorage.swift
│       ├── FilterSettingsStorage.swift
│       └── TagStorage.swift
├── Models/                   # Data models
│   ├── DatabaseConnection.swift
│   ├── ConnectionSession.swift
│   ├── QueryResult.swift
│   ├── QueryTab.swift
│   ├── TableMetadata.swift
│   ├── FilterState.swift
│   └── RowProvider.swift
├── Views/                    # SwiftUI + AppKit views
│   ├── Connection/           # Connection management
│   ├── Editor/               # Query editor
│   ├── Results/              # Data grid
│   ├── Sidebar/              # Database/table browser
│   ├── Structure/            # Table structure view
│   ├── Filter/               # Filtering UI
│   ├── History/              # Query history
│   ├── Toolbar/              # App toolbar
│   └── Main/                 # Main content coordinator
└── Theme/                    # UI theme and design constants
```

### Design Principles

**Native First**: TablePro prioritizes native macOS, Swift, and system-provided solutions over custom implementations.

- **SwiftUI + AppKit**: SwiftUI for modern UI, AppKit bridges only where necessary (NSTextView for editor, NSTableView for grid)
- **Native Database Clients**: Thin protocol layer over libpq, MariaDB Connector/C, and SQLite C API
- **System Integration**: Keychain for credentials, UserDefaults for preferences, NotificationCenter for events
- **Swift Concurrency**: Native async/await for database operations

### Design Patterns

- **Protocol-Oriented Database Layer**: `DatabaseDriver` protocol with database-specific implementations
- **Factory Pattern**: `DatabaseDriverFactory` creates appropriate drivers
- **Singleton Services**: `DatabaseManager`, `ConnectionStorage`, `SSHTunnelManager`
- **Session Management**: Connection sessions preserve state when switching
- **NSViewRepresentable**: SwiftUI wrappers for AppKit components
- **Command Pattern**: Native menu commands and NotificationCenter events

### Key Components

#### Database Drivers (Thin Abstraction Over Native Libraries)

`DatabaseDriver` protocol defines a minimal interface over native database clients:

- `MySQLDriver` → MariaDB Connector/C
- `PostgreSQLDriver` → libpq
- `SQLiteDriver` → SQLite C API

Drivers remain thin adapters, delegating to native libraries without duplicating logic.

#### Autocomplete System

Context-aware SQL completion using:

- `SQLContextAnalyzer` – Lightweight query context parsing
- `SQLCompletionProvider` – Provides suggestions
- `SQLSchemaProvider` – Uses native driver metadata
- `SQLKeywords` – Static keyword definitions

Parsing remains non-blocking and incremental using Swift concurrency.

#### Change Tracking System

Native change tracking for inline editing:

- Cell edits tracked as `DataChange`
- Highlighted via SwiftUI/AppKit
- Batch-committed using generated SQL
- Undo/Redo support

## Event System

TablePro uses **NotificationCenter and native menu commands** instead of custom event buses.

Standard notifications:
- `.newConnection`
- `.newTab`
- `.closeCurrentTab`
- `.saveChanges`
- `.refreshData`
- `.executeQuery`
- `.databaseDidConnect`

## Contributing

Contributions are welcome! Please follow the design principles outlined in `CLAUDE.md`:

> **If macOS or Swift provides a solution, use it.**
> Build custom code only to connect, adapt, or unify native functionality — never to replace it.

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 0.2.0 | Dec 2024 | Data grid editing, SQL function support, autocomplete |
| 0.1.0 | Dec 2024 | Initial release with core features |

## License

MIT License

## Author

Ngo Quoc Dat

## Acknowledgments

Built with native macOS technologies:
- SwiftUI & AppKit for UI
- MariaDB Connector/C for MySQL/MariaDB
- libpq for PostgreSQL
- SQLite C API for SQLite
- macOS Keychain for secure storage
