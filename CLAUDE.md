# CLAUDE.md

This file provides comprehensive guidance to Claude Code when working with the TablePro codebase.

## Project Overview

**TablePro** is a native macOS database client built with **SwiftUI and AppKit**, designed as a modern alternative to TablePlus. The project follows a strict philosophy: **prioritize Apple-native frameworks and system libraries over custom implementations**.

### Supported Databases

- **MySQL / MariaDB** via MariaDB Connector/C (static library)
- **PostgreSQL** via libpq (native C library)
- **SQLite** via system libsqlite3

### Technology Stack

- **UI Framework**: SwiftUI (primary) + AppKit bridges (only when necessary)
- **Language**: Swift 5.9+
- **Concurrency**: Swift async/await, Task, @MainActor
- **Persistence**: macOS Keychain (credentials), UserDefaults (preferences), JSON files (state)
- **Events**: NotificationCenter + SwiftUI commands
- **Database Access**: Native C libraries with thin Swift protocol layer

## Core Design Philosophy

### Golden Rule: Prefer Native Over Custom

**Always prefer native macOS, Swift, and system-provided solutions over custom implementations.**

#### Use Native APIs For:

- **UI Components**: SwiftUI controls, AppKit when SwiftUI insufficient
- **Concurrency**: Swift async/await, Task, AsyncSequence (NOT custom threading)
- **Persistence**: Keychain, UserDefaults, FileManager (NOT custom databases)
- **Events**: NotificationCenter, Combine (NOT custom event buses)
- **Networking**: URLSession (if needed)
- **Data Structures**: Swift standard library collections
- **Database Protocols**: libpq, MariaDB Connector/C, SQLite C API (NOT custom SQL parsers/connections)

#### Only Build Custom Code When:

1. **Native API does not exist** (e.g., SQL autocomplete context analysis)
2. **Native API insufficient** (e.g., NSTableView performance for large grids)
3. **Unification layer required** (e.g., DatabaseDriver protocol to abstract MySQL/PostgreSQL/SQLite)

#### Code Review Checklist

Before adding custom code, ask:

- Does Foundation/SwiftUI/AppKit provide this?
- Can this be solved with standard library?
- Am I reimplementing existing functionality?
- Is this abstraction truly needed?

## Build Configuration

### Prerequisites

```bash
# Required for compilation
brew install mariadb-connector-c  # MySQL/MariaDB headers
brew install libpq                # PostgreSQL headers

# System Requirements
- macOS 14.0+
- Xcode 15.0+
```

### Build Commands

```bash
# Command-line build
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build

# Xcode
# Open TablePro.xcodeproj and press Cmd+R
```

### Project Structure

```
TablePro/
├── Core/                      # Business logic and services
│   ├── Autocomplete/          # SQL autocomplete engine
│   ├── ChangeTracking/        # Cell edit tracking and commit
│   ├── Database/              # Database drivers and connections
│   ├── Services/              # Query execution, row operations
│   ├── SSH/                   # SSH tunnel management
│   └── Storage/               # Persistence layer
├── Models/                    # Pure data structures
├── Views/                     # SwiftUI + AppKit UI
│   ├── Connection/            # Connection management UI
│   ├── Editor/                # Query editor (NSTextView bridge)
│   ├── Results/               # Data grid (NSTableView bridge)
│   ├── Sidebar/               # Database/table browser
│   ├── Structure/             # Table structure viewer
│   ├── Filter/                # Filtering UI
│   ├── History/               # Query history UI
│   ├── Toolbar/               # App toolbar components
│   └── Main/                  # Main content coordinator
├── Theme/                     # Design constants and theming
├── Extensions/                # Swift extensions
└── Resources/                 # MariaDB client plugins
```

## Architecture Deep Dive

### 1. Database Layer (`Core/Database/`)

#### DatabaseDriver Protocol (Thin Abstraction)

The `DatabaseDriver` protocol defines a **minimal interface** over native database clients:

```swift
protocol DatabaseDriver: AnyObject {
    var connection: DatabaseConnection { get }
    var status: ConnectionStatus { get }
    
    func connect() async throws
    func disconnect()
    func execute(query: String) async throws -> QueryResult
    func fetchTables() async throws -> [TableInfo]
    func fetchColumns(table: String) async throws -> [ColumnInfo]
    func fetchIndexes(table: String) async throws -> [IndexInfo]
    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo]
    func fetchTableDDL(table: String) async throws -> String
    func fetchRowCount(query: String) async throws -> Int
    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult
    func fetchTableMetadata(tableName: String) async throws -> TableMetadata
    func fetchDatabases() async throws -> [String]
}
```

**Key Principle**: Drivers should be **thin adapters** that delegate to native libraries, NOT reimplementations.

#### Driver Implementations

##### MySQLDriver (`MySQLDriver.swift`)

- Uses **MariaDB Connector/C** (static library in `Libs/libmariadb.a`)
- Wraps `MariaDBConnection` class (handles C API via `CMariaDB` module)
- Direct `mysql_*` function calls for all operations
- NEVER reimplement MySQL protocol

##### PostgreSQLDriver (`PostgreSQLDriver.swift`)

- Uses **libpq** (PostgreSQL C library)
- Wraps `LibPQConnection` class (handles C API via `CLibPQ` module)
- Direct `PQ*` function calls for all operations
- NEVER reimplement PostgreSQL protocol

##### SQLiteDriver (`SQLiteDriver.swift`)

- Uses **native SQLite3** (`import SQLite3`)
- Direct `sqlite3_*` function calls
- NEVER use third-party SQLite wrappers

#### DatabaseDriverFactory

Factory pattern for driver creation:

```swift
static func createDriver(for connection: DatabaseConnection) -> DatabaseDriver {
    switch connection.type {
    case .sqlite: return SQLiteDriver(connection: connection)
    case .mysql, .mariadb: return MySQLDriver(connection: connection)
    case .postgresql: return PostgreSQLDriver(connection: connection)
    }
}
```

### 2. Session Management (`DatabaseManager.swift`)

**Singleton**: `DatabaseManager.shared` (marked `@MainActor`)

#### Key Responsibilities

1. **Manage active sessions**: Each connection gets a `ConnectionSession`
2. **Track current session**: UI-selected session
3. **Coordinate queries**: Route through current driver
4. **Handle SSH tunnels**: Integrate with `SSHTunnelManager`
5. **Persist tab state**: Save/restore query tabs

#### Session Lifecycle

```swift
// Connect creates or switches to session
await DatabaseManager.shared.connectToSession(connection)

// Sessions stored by connection ID
activeSessions: [UUID: ConnectionSession]

// Current session drives UI
currentSessionId: UUID?
currentSession: ConnectionSession?
```

#### Important Patterns

- **Sessions persist when switching**: Switching connections preserves query tabs, filters, etc.
- **SSH tunnel handling**: Manager creates tunnels before driver connection
- **Tab restoration**: Tabs restored from `TabStateStorage` on connection
- **Query routing**: All queries go through `activeDriver`

```swift
// Example: Execute query on current session
func execute(query: String) async throws -> QueryResult {
    guard let driver = activeDriver else {
        throw DatabaseError.notConnected
    }
    return try await driver.execute(query: query)
}
```

### 3. Models (`TablePro/Models/`)

**Principle**: Models are **pure data structures** with minimal logic.

#### Key Models

- **DatabaseConnection**: Connection configuration (host, port, credentials, SSH)
- **ConnectionSession**: Active session state (driver, tabs, selected table, filters)
- **QueryTab**: Query or table tab (type, content, result, execution state)
- **QueryResult**: Query execution result (columns, rows, affected rows, error)
- **TableInfo**: Table metadata (name, type, row count, size)
- **ColumnInfo**: Column metadata (name, type, nullable, default)
- **DataChange**: Tracked cell edit (row, column, old value, new value, change type)
- **FilterState**: Active filters for a table
- **QueryHistoryEntry**: Historical query with timestamp

#### Design Rules

- **NO UI logic** in models (use Views for UI)
- **NO persistence logic** in models (use Storage layer)
- **NO business logic** in models (use Services/Managers)
- **Use structs** for value types (prefer struct over class)
- **Codable** for serialization where needed

### 4. Storage Layer (`Core/Storage/`)

#### ConnectionStorage (Singleton)

- **Credentials**: Stored in **macOS Keychain** (`SecItemAdd`, `SecItemCopyMatching`)
- **Connection configs**: Stored in **UserDefaults** (JSON-encoded)
- **SSH passwords**: Separate Keychain entries

```swift
// GOOD: Use Keychain for sensitive data
ConnectionStorage.shared.savePassword(password, for: connectionId)

// BAD: Custom encryption or file storage for passwords
```

#### TabStateStorage (Singleton)

- **Tab state**: Saved to JSON files in Application Support directory
- **Per connection**: Each connection has separate tab state file
- **Automatic**: Saved on tab changes, restored on connection

#### QueryHistoryStorage (Singleton)

- **Query history**: SQLite database in Application Support
- **Indexed**: By connection ID and timestamp
- **Search**: Full-text search on query text

#### FilterSettingsStorage (Singleton)

- **Filter presets**: Saved to JSON files
- **Per table**: Each table can have saved filter presets

### 5. UI Architecture

#### SwiftUI First, AppKit Only When Necessary

**Primary UI**: SwiftUI for all modern UI components

**AppKit Bridges** (via `NSViewRepresentable`):

1. **SQLEditorView** → wraps `NSTextView`
   - Reason: Syntax highlighting, advanced text editing APIs
   - File: `Views/Editor/SQLEditorView.swift`
   - Coordinator: `EditorCoordinator` handles NSTextView delegate

2. **DataGridView** → wraps `NSTableView`
   - Reason: High-performance rendering of large datasets (100k+ rows)
   - File: `Views/Results/DataGridView.swift`
   - Custom: `KeyHandlingTableView` for keyboard navigation

3. **SQLCompletionWindowController** → `NSPanel`
   - Reason: Floating autocomplete window positioning
   - File: `Views/Editor/SQLCompletionWindowController.swift`

**Guidelines for AppKit Bridges**:

- Use ONLY when SwiftUI lacks necessary APIs
- Wrap minimal AppKit surface area
- Expose SwiftUI-friendly bindings
- NEVER reimplement AppKit behaviors
- Document why AppKit is required

#### View Hierarchy

```
TableProApp (@main)
└── ContentView (NavigationSplitView)
    ├── Sidebar: SidebarView
    │   ├── Connection list
    │   └── Table browser
    ├── Content: MainContentView
    │   ├── Query tabs: QueryTabBar
    │   ├── Query editor: QueryEditorView
    │   │   └── SQLEditorView (NSTextView)
    │   ├── Data grid: DataGridView (NSTableView)
    │   └── Structure: TableStructureView
    └── Detail: RightSidebarView (optional)
        ├── Query history
        └── Bookmarks
```

#### View Coordinator Pattern

`MainContentCoordinator` manages complex view state:

- **Centralized state**: Loads data, handles notifications
- **Async operations**: Query execution, table loading
- **Error handling**: Alert state management
- **Marked @MainActor**: All UI updates on main thread

```swift
@MainActor
final class MainContentCoordinator: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadTableData(table: String) async {
        // Coordinate loading...
    }
}
```

### 6. Event & Command System

**Use Native Event Mechanisms**:

#### NotificationCenter (Cross-Component Events)

Standard notifications (defined in various files):

```swift
extension Notification.Name {
    static let databaseDidConnect = Notification.Name("databaseDidConnect")
    static let newConnection = Notification.Name("newConnection")
    static let newTab = Notification.Name("newTab")
    static let closeCurrentTab = Notification.Name("closeCurrentTab")
    static let saveChanges = Notification.Name("saveChanges")
    static let refreshData = Notification.Name("refreshData")
    static let executeQuery = Notification.Name("executeQuery")
}
```

**Usage Pattern**:

```swift
// Post
NotificationCenter.default.post(name: .databaseDidConnect, object: nil)

// Observe (in SwiftUI)
.onReceive(NotificationCenter.default.publisher(for: .executeQuery)) { _ in
    executeCurrentQuery()
}
```

#### SwiftUI Commands (Menu Items)

Menu items use SwiftUI `.commands` modifier:

```swift
.commands {
    CommandGroup(replacing: .newItem) {
        Button("New Connection") {
            NotificationCenter.default.post(name: .newConnection, object: nil)
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}
```

**NEVER**:
- Build custom event bus systems
- Use singletons for event distribution
- Create custom command routing

### 7. SQL Autocomplete System (`Core/Autocomplete/`)

#### Architecture (Layered, Native-Friendly)

1. **SQLContextAnalyzer** (`SQLContextAnalyzer.swift`)
   - Lightweight SQL parsing to determine cursor context
   - Returns: `SQLContext` (keyword, table reference, column reference, function, etc.)
   - **Important**: NOT a full SQL parser, just context detection
   - Uses regex and string manipulation (no external parser dependencies)

2. **SQLSchemaProvider** (`SQLSchemaProvider.swift`)
   - Fetches schema metadata from active database driver
   - Caches table/column lists for performance
   - Uses `DatabaseDriver` protocol methods (native database queries)

3. **SQLKeywords** (`SQLKeywords.swift`)
   - Static keyword definitions (SELECT, WHERE, JOIN, etc.)
   - Organized by SQL category
   - Simple arrays, no complex logic

4. **SQLCompletionProvider** (`SQLCompletionProvider.swift`)
   - Combines context + schema + keywords → suggestions
   - Returns `SQLCompletionItem` array
   - Prioritizes suggestions based on context

5. **CompletionEngine** (`CompletionEngine.swift`)
   - Main coordinator for autocomplete
   - Triggers completion on user input or Ctrl+Space
   - Manages completion window display

#### Performance Guidelines

- **Non-blocking**: All schema fetching uses `async/await`
- **Incremental**: Parse only what's needed for context
- **Cached**: Schema cached per session, invalidated on refresh
- **Swift concurrency**: Use Task for background work

```swift
// GOOD: Async schema fetching
func fetchCompletions(query: String, cursorPosition: Int) async -> [SQLCompletionItem] {
    let context = SQLContextAnalyzer.analyze(query, at: cursorPosition)
    let schema = await schemaProvider.getSchema()
    return provider.completions(for: context, schema: schema)
}

// BAD: Synchronous blocking or custom threading
```

### 8. Change Tracking System (`Core/ChangeTracking/`)

#### DataChangeManager (Tracks Edits)

- **Tracks cell edits**: Before commit to database
- **Change types**: Update, Insert, Delete
- **Highlights**: Modified cells shown with yellow background
- **Undo/Redo**: Native undo manager integration

#### DataChange Model

```swift
struct DataChange: Identifiable {
    let id: UUID
    let rowIndex: Int
    let columnName: String
    let oldValue: String?
    let newValue: String?
    let changeType: ChangeType  // .update, .insert, .delete
}
```

#### SQLStatementGenerator

- **Generates SQL**: Converts `DataChange` array → SQL statements
- **Batch operations**: Multiple changes → single transaction
- **Handles NULL**: Special handling for NULL, empty string, DEFAULT

```swift
// Example generated SQL
UPDATE users SET name = 'John', email = NULL WHERE id = 1;
INSERT INTO users (name, email) VALUES ('Jane', 'jane@example.com');
DELETE FROM users WHERE id = 3;
```

#### Change Commit Flow

1. User edits cell → `DataChangeManager` records change
2. Cell highlighted → SwiftUI view shows yellow background
3. User presses Cmd+S → `SQLStatementGenerator` creates SQL
4. SQL executed in transaction → All or nothing
5. Success → Clear tracked changes, refresh grid
6. Failure → Rollback, show error, preserve changes

### 9. SSH Tunnel Support (`Core/SSH/`)

#### SSHTunnelManager (Singleton)

- **Creates tunnels**: Using system `ssh` command via Process
- **Port forwarding**: Local port → Remote database through SSH
- **Authentication**: Password or private key
- **Lifecycle**: Tunnel created before driver connection, closed on disconnect

#### Integration Pattern

```swift
// DatabaseManager handles SSH transparently
if connection.sshConfig.enabled {
    // Create tunnel first
    let tunnelPort = try await SSHTunnelManager.shared.createTunnel(...)
    
    // Connect driver to localhost:tunnelPort
    let tunnelConnection = DatabaseConnection(
        host: "127.0.0.1",
        port: tunnelPort,
        ...
    )
    driver = DatabaseDriverFactory.createDriver(for: tunnelConnection)
}
```

**Important**: Driver NEVER knows about SSH, only connects to localhost tunnel.

## Coding Guidelines

### 1. Swift Concurrency

**Use async/await for all asynchronous operations**:

```swift
// GOOD
func fetchTables() async throws -> [TableInfo] {
    try await driver.fetchTables()
}

// BAD: Completion handlers
func fetchTables(completion: @escaping (Result<[TableInfo], Error>) -> Void) {
    // Don't do this
}
```

**Use @MainActor for UI-related classes**:

```swift
@MainActor
final class DatabaseManager: ObservableObject {
    @Published var activeSessions: [UUID: ConnectionSession] = [:]
    // All methods run on main thread automatically
}
```

**Use Task for background work**:

```swift
Task {
    do {
        let tables = try await DatabaseManager.shared.fetchTables()
        // Update UI
    } catch {
        // Handle error
    }
}
```

### 2. Error Handling

**Use typed errors with clear messages**:

```swift
enum DatabaseError: LocalizedError {
    case notConnected
    case queryFailed(String)
    case connectionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to database"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}
```

**Always propagate errors with context**:

```swift
// GOOD
throw DatabaseError.queryFailed("Invalid SQL: \(query)")

// BAD
throw NSError(domain: "Error", code: -1)
```

### 3. SwiftUI Best Practices

**Use @StateObject for owned objects**:

```swift
@StateObject private var coordinator = MainContentCoordinator()
```

**Use @ObservedObject for passed objects**:

```swift
@ObservedObject var session: ConnectionSession
```

**Use @EnvironmentObject for shared state**:

```swift
@EnvironmentObject var databaseManager: DatabaseManager
```

**Prefer bindings over callbacks**:

```swift
// GOOD
TextField("Name", text: $connection.name)

// BAD
TextField("Name", text: connection.name, onChange: { newValue in
    connection.name = newValue
})
```

### 4. File Organization

**Group related files in folders**:

```
Views/Editor/
├── QueryEditorView.swift       # Main editor view
├── SQLEditorView.swift         # NSTextView wrapper
├── EditorCoordinator.swift     # NSTextView coordinator
├── SyntaxHighlighter.swift     # Syntax highlighting
└── LineNumberView.swift        # Line numbers gutter
```

**One type per file** (except small related types):

```swift
// DatabaseConnection.swift - GOOD
struct DatabaseConnection {
    // ...
}

enum DatabaseType {
    case mysql, postgresql, sqlite
}

struct SSHConfiguration {
    // ...
}

// MainView.swift - BAD (too many types)
struct MainView {}
class MainViewModel {}
struct MainState {}
enum MainAction {}
```

### 5. Naming Conventions

**Types**: PascalCase

```swift
struct DatabaseConnection { }
class MySQLDriver { }
enum QueryResult { }
```

**Properties/Methods**: camelCase

```swift
var isConnected: Bool
func fetchTables() async throws -> [TableInfo]
```

**Constants**: camelCase or PascalCase for types

```swift
let defaultPort = 3306
static let shared = DatabaseManager()
```

**Protocol methods**: Descriptive, action-oriented

```swift
protocol DatabaseDriver {
    func connect() async throws          // GOOD
    func doConnect() async throws        // BAD
    func performConnectionOperation()    // BAD (too verbose)
}
```

### 6. Comments and Documentation

**Use doc comments for public APIs**:

```swift
/// Connects to the database using the provided configuration.
///
/// This method establishes a connection to the database server and
/// authenticates using the credentials stored in the connection object.
///
/// - Throws: `DatabaseError.connectionFailed` if connection fails
func connect() async throws
```

**Use inline comments sparingly**:

```swift
// GOOD: Explain WHY, not WHAT
// Use tunnel port instead of direct connection when SSH is enabled
let port = sshEnabled ? tunnelPort : connection.port

// BAD: Obvious comment
// Set the port variable
let port = connection.port
```

**No commented-out code**:

```swift
// BAD
// let oldDriver = MySQLDriver()
// driver.connect()

// GOOD: Delete it and use git history if needed
```

### 7. Testing Patterns

**Test database operations with real connections** (integration tests):

```swift
func testMySQLConnection() async throws {
    let connection = DatabaseConnection(
        host: "localhost",
        port: 3306,
        database: "test",
        username: "root",
        type: .mysql
    )
    let driver = MySQLDriver(connection: connection)
    try await driver.connect()
    XCTAssertEqual(driver.status, .connected)
    driver.disconnect()
}
```

**Mock only external dependencies**:

```swift
// GOOD: Mock SSH tunnel
class MockSSHTunnelManager: SSHTunnelManager {
    override func createTunnel(...) async throws -> Int {
        return 12345  // Mock port
    }
}

// BAD: Mock database driver (test with real database instead)
```

## Common Patterns

### 1. Session-Based State Management

**Each connection maintains its own session**:

```swift
// Get current session
guard let session = DatabaseManager.shared.currentSession else { return }

// Update session state
DatabaseManager.shared.updateSession(session.id) { session in
    session.selectedTable = "users"
    session.currentFilter = FilterState(...)
}

// Access session data
let tabs = session.tabs
let selectedTable = session.selectedTable
```

### 2. SwiftUI Binding Pattern

**Views update session state via bindings**:

```swift
struct QueryEditorView: View {
    @Binding var tab: QueryTab
    
    var body: some View {
        TextEditor(text: $tab.query)  // Directly binds to session state
    }
}

// In parent view
if let binding = Binding(
    get: { DatabaseManager.shared.currentSession?.tabs[index] },
    set: { newValue in
        DatabaseManager.shared.updateSession(sessionId) { session in
            session.tabs[index] = newValue
        }
    }
) {
    QueryEditorView(tab: binding)
}
```

### 3. Async Data Loading

**Load data asynchronously with Task**:

```swift
@MainActor
func loadTableData() {
    isLoading = true
    errorMessage = nil
    
    Task {
        do {
            let result = try await DatabaseManager.shared.execute(query: query)
            self.queryResult = result
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
```

### 4. NotificationCenter Integration

**Post notifications for cross-component events**:

```swift
// Sender
NotificationCenter.default.post(
    name: .executeQuery,
    object: nil,
    userInfo: ["query": queryText]
)

// Receiver (SwiftUI)
.onReceive(NotificationCenter.default.publisher(for: .executeQuery)) { notification in
    if let query = notification.userInfo?["query"] as? String {
        executeQuery(query)
    }
}
```

### 5. Factory Pattern for Drivers

**Always use factory to create drivers**:

```swift
// GOOD
let driver = DatabaseDriverFactory.createDriver(for: connection)

// BAD: Direct instantiation
let driver = MySQLDriver(connection: connection)  // Tight coupling
```

## Keyboard Shortcuts Implementation

**Use native command handling**:

```swift
.commands {
    CommandGroup(after: .newItem) {
        Button("Execute Query") {
            NotificationCenter.default.post(name: .executeQuery, object: nil)
        }
        .keyboardShortcut(.return, modifiers: .command)
        
        Button("Save Changes") {
            NotificationCenter.default.post(name: .saveChanges, object: nil)
        }
        .keyboardShortcut("s", modifiers: .command)
        
        Button("Refresh Data") {
            NotificationCenter.default.post(name: .refreshData, object: nil)
        }
        .keyboardShortcut("r", modifiers: .command)
    }
}
```

**Standard shortcuts**:

- `Cmd+Enter` → Execute query
- `Cmd+S` → Save/commit changes
- `Cmd+R` → Refresh data
- `Cmd+W` → Close tab
- `Cmd+N` → New connection
- `Cmd+T` → New query tab
- `Ctrl+Space` → Trigger autocomplete

## Performance Considerations

### 1. Large Datasets

**Use pagination for large result sets**:

```swift
// Fetch total count
let totalRows = try await driver.fetchRowCount(query: baseQuery)

// Fetch page
let page = try await driver.fetchRows(
    query: baseQuery,
    offset: currentPage * pageSize,
    limit: pageSize
)
```

**NSTableView for grids** (handles virtualization natively):

```swift
// DataGridView uses NSTableView for performance
// SwiftUI List/Table too slow for 100k+ rows
```

### 2. Schema Caching

**Cache schema metadata per session**:

```swift
class SQLSchemaProvider {
    private var cachedTables: [TableInfo]?
    private var cachedColumns: [String: [ColumnInfo]] = [:]
    
    func getTables() async throws -> [TableInfo] {
        if let cached = cachedTables {
            return cached
        }
        let tables = try await driver.fetchTables()
        cachedTables = tables
        return tables
    }
    
    func invalidateCache() {
        cachedTables = nil
        cachedColumns.removeAll()
    }
}
```

### 3. Main Thread Usage

**Keep main thread free**:

```swift
// GOOD: Heavy work in Task
Task.detached {
    let result = try await expensiveOperation()
    await MainActor.run {
        self.updateUI(with: result)
    }
}

// BAD: Blocking main thread
let result = expensiveOperation()  // UI freezes
```

## Security Best Practices

### 1. Credential Storage

**Always use Keychain for sensitive data**:

```swift
// GOOD
ConnectionStorage.shared.savePassword(password, for: connectionId)

// BAD
UserDefaults.standard.set(password, forKey: "password")  // NEVER!
```

### 2. SQL Injection Prevention

**Use parameterized queries when possible**:

```swift
// GOOD (when driver supports)
let result = try await driver.execute(
    query: "SELECT * FROM users WHERE id = ?",
    parameters: [userId]
)

// ACCEPTABLE (when no parameters supported)
// Validate and escape inputs manually
let escapedName = name.replacingOccurrences(of: "'", with: "''")
let query = "SELECT * FROM users WHERE name = '\(escapedName)'"
```

**Note**: Current drivers use direct string queries. Consider adding parameter support.

### 3. Connection Strings

**Never log connection strings with credentials**:

```swift
// GOOD
logger.debug("Connecting to \(connection.host):\(connection.port)")

// BAD
logger.debug("Connection: mysql://\(username):\(password)@\(host)")  // NEVER!
```

## Debugging Tips

### 1. Logging

**Use os.log for structured logging**:

```swift
import os.log

let logger = Logger(subsystem: "com.tablepro", category: "database")

logger.debug("Connecting to database: \(connection.host)")
logger.error("Connection failed: \(error.localizedDescription)")
```

### 2. Breakpoint Strategies

**Break on error throws**:

```
(lldb) breakpoint set -E swift
```

**Break on specific notifications**:

```swift
NotificationCenter.default.addObserver(
    forName: .executeQuery,
    object: nil,
    queue: nil
) { _ in
    print("Query execution triggered")  // Set breakpoint here
}
```

### 3. View Debugging

**Use Xcode's View Debugger** (Cmd+Shift+D during runtime)

**Add visual debug helpers**:

```swift
#if DEBUG
.border(Color.red)  // Show view bounds
.background(Color.yellow.opacity(0.3))  // Highlight area
#endif
```

## Common Pitfalls to Avoid

### 1. Don't Reinvent the Wheel

```swift
// BAD: Custom date formatting
func formatDate(_ date: Date) -> String {
    let year = Calendar.current.component(.year, from: date)
    let month = Calendar.current.component(.month, from: date)
    // ...manual formatting
}

// GOOD: Use Foundation
let formatter = DateFormatter()
formatter.dateStyle = .medium
return formatter.string(from: date)
```

### 2. Don't Block Main Thread

```swift
// BAD
func loadData() {
    let data = try! fetchDataFromDatabase()  // Blocks UI
    self.data = data
}

// GOOD
func loadData() {
    Task {
        let data = try await fetchDataFromDatabase()
        await MainActor.run {
            self.data = data
        }
    }
}
```

### 3. Don't Mix UI and Business Logic

```swift
// BAD: UI logic in model
struct QueryTab {
    var backgroundColor: Color {  // NO!
        isModified ? .yellow : .clear
    }
}

// GOOD: Keep models pure
struct QueryTab {
    var isModified: Bool
}

// Put UI logic in view
.background(tab.isModified ? Color.yellow : Color.clear)
```

### 4. Don't Create Singleton Overload

```swift
// BAD: Too many singletons
class ConnectionManager: ObservableObject { static let shared = ... }
class QueryManager: ObservableObject { static let shared = ... }
class TableManager: ObservableObject { static let shared = ... }
// etc...

// GOOD: Use dependency injection or consolidate
class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    // Contains connection, query, table management
}
```

### 5. Don't Ignore Memory Management

```swift
// BAD: Retain cycle
class MyView {
    var onComplete: (() -> Void)?
    
    func setup() {
        onComplete = {
            self.handleComplete()  // Captures self strongly
        }
    }
}

// GOOD: Use [weak self]
onComplete = { [weak self] in
    self?.handleComplete()
}
```

## Migration Guidelines

### Adding a New Database Type

1. **Create driver** implementing `DatabaseDriver` protocol
2. **Add case** to `DatabaseType` enum
3. **Update factory** in `DatabaseDriverFactory`
4. **Add UI option** in `ConnectionFormView`
5. **Test thoroughly** with real database

### Adding New Features

1. **Check native APIs first** - Can Foundation/SwiftUI handle this?
2. **Design protocol** if abstracting multiple implementations
3. **Use async/await** for all I/O operations
4. **Add to appropriate layer** (Core/Models/Views)
5. **Follow existing patterns** in codebase

## Summary: The TablePro Way

> **If macOS or Swift provides a solution, use it.**
> 
> Build custom code only to connect, adapt, or unify native functionality — never to replace it.

### Decision Framework

When adding code, ask these questions in order:

1. **Does a native API exist?** → Use it
2. **Can I compose native APIs?** → Compose them
3. **Is a thin wrapper needed?** → Wrap minimally
4. **Do I need custom logic?** → Keep it focused and justified

### Code Review Questions

Before committing code, verify:

- [ ] Am I using native APIs where available?
- [ ] Is this the simplest solution?
- [ ] Does this follow existing patterns?
- [ ] Is async/await used for I/O?
- [ ] Are errors properly typed and propagated?
- [ ] Is the code in the right layer (Core/Models/Views)?
- [ ] Is memory management correct (no retain cycles)?
- [ ] Does this work with session-based architecture?

### Remember

**TablePro's strength** comes from embracing the native macOS ecosystem, not fighting it. When in doubt, choose the native, well-established solution over a custom implementation.
