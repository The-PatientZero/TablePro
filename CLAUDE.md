# TablePro - Agent Development Guide

## Project Overview

TablePro is a native macOS database client built with SwiftUI and AppKit. It's designed as a fast, lightweight alternative to TablePlus, prioritizing Apple-native frameworks and modern Swift idioms for optimal performance and maintainability.

## Build & Development Commands

### Building

```bash
# Build for current architecture (development)
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build

# Build for specific architecture (release)
scripts/build-release.sh arm64       # Apple Silicon only
scripts/build-release.sh x86_64      # Intel only
scripts/build-release.sh both        # Universal binary

# Clean build
xcodebuild -project TablePro.xcodeproj -scheme TablePro clean

# Build and run
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build && open build/Debug/TablePro.app
```

### Linting & Formatting

```bash
# Run SwiftLint (check for code issues)
swiftlint lint

# Auto-fix SwiftLint issues
swiftlint --fix

# Run SwiftFormat (format code)
swiftformat .

# Check formatting without applying
swiftformat --lint .
```

### Testing

```bash
# Run all tests
xcodebuild -project TablePro.xcodeproj -scheme TablePro test

# Run specific test class
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -only-testing:TableProTests/TestClassName

# Run specific test method
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -only-testing:TableProTests/TestClassName/testMethodName
```

### Creating DMG

```bash
# Create distributable DMG (after building)
scripts/create-dmg.sh
```

## Code Style Guidelines

### Architecture Principles

- **Separation of Concerns**: Keep business logic in models/view models, not in views
- **Value Types First**: Prefer `struct` over `class` unless reference semantics are needed
- **Composition**: Use protocols and extensions for shared behavior instead of inheritance
- **Immutability**: Use `let` by default; only use `var` when mutation is required
- **Actor Isolation**: Use `@MainActor` for UI-bound types, custom actors for concurrent operations

### File Structure

- **Models**: `TablePro/Models/` - Data structures, domain entities (prefer `struct`, `enum`)
- **Views**: `TablePro/Views/` - SwiftUI views only, no business logic
- **ViewModels**: `TablePro/ViewModels/` - `@Observable` classes (Swift 5.9+) or `ObservableObject`
- **Core**: `TablePro/Core/` - Business logic, database drivers, services
- **Extensions**: `TablePro/Extensions/` - Type extensions, protocol conformances
- **Resources**: `TablePro/Resources/` - Assets, localized strings, asset catalogs

### Imports

- **Order**: System frameworks (alphabetically), then third-party, then local
- **Specificity**: Import only what you need (`import struct Foundation.URL`)
- **TestableImport**: Use `@testable import` only in test targets
- **Blank line**: Required after imports before code begins

```swift
import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
struct ContentView: View {
```

### Formatting (Apple Style Guide)

- **Indentation**: 4 spaces (never tabs except Makefile/pbxproj)
- **Line length**: 120 characters (hard limit from Swift.org style guide)
- **Braces**: K&R style - opening brace on same line, closing brace on new line
- **Wrapping**: Break before first argument when wrapping function calls/declarations
- **Semicolons**: Never use (not idiomatic Swift)
- **Trailing commas**: Omit in collections (SwiftFormat enforces)
- **Line endings**: LF only (Unix-style), never CRLF
- **File endings**: Single newline at EOF
- **Vertical whitespace**: Maximum 2 consecutive empty lines between declarations

### Naming Conventions (Apple API Design Guidelines)

- **Types**: UpperCamelCase (`DatabaseConnection`, `QueryResultSet`)
- **Functions/Variables**: lowerCamelCase (`executeQuery()`, `connectionString`)
- **Constants**: lowerCamelCase (`maxRetryAttempts`, `defaultTimeout`)
- **Enums**: UpperCamelCase type, lowerCamelCase cases (`DatabaseType.postgresql`)
- **Protocols**: Noun for capability (`DatabaseDriver`), `-able`/`-ible` for behavior (`Connectable`)
- **Boolean properties**: Use `is`/`has`/`can` prefix (`isConnected`, `hasValidCredentials`)
- **Factory methods**: Use `make` prefix (`makeConnection()`)
- **Acronyms**: Treat as words (`JsonEncoder`, not `JSONEncoder` - except SDK types)

### Type Inference & Explicit Types

- **Use inference**: When type is obvious from context
    ```swift
    let connection = DatabaseConnection(host: "localhost") // Good
    let connections: [DatabaseConnection] = [] // Explicit needed for empty collection
    ```
- **Be explicit**: For empty collections, complex generics, or when clarity helps
- **Avoid redundancy**: Don't repeat type in initialization (`var name: String = String()` → `var name = ""`)
- **Self**: Omit `self.` unless required for closure capture or property/parameter disambiguation

### Access Control

- Always specify access modifiers explicitly (`private`, `fileprivate`, `internal`, `public`)
- Prefer `private` over `fileprivate` unless cross-type access needed
- Use `private(set)` for read-only public properties
- IBOutlets should be `private` or `fileprivate`
- **Extension access modifiers**: Always specify access level on the extension itself, not individual members
    ```swift
    // Bad
    extension NSEvent {
        public var semanticKeyCode: KeyCode? { ... }
    }

    // Good
    public extension NSEvent {
        var semanticKeyCode: KeyCode? { ... }
    }
    ```

### Optionals & Error Handling

- Avoid force unwrapping (`!`) and force casting (`as!`) - use SwiftLint warnings as guide
- Prefer `if let` or `guard let` for unwrapping
- Use `guard` for early returns to reduce nesting
- Fatal errors must include descriptive messages
- Don't use force try (`try!`) except in tests or guaranteed scenarios
- **Safe casting**: Never use force cast (`as!`), always use conditional casting
    ```swift
    // Bad
    let value = param as! SQLFunctionLiteral

    // Good
    if let value = param as? SQLFunctionLiteral {
        return value.property
    }

    // Better (with optional chaining)
    return (param as? SQLFunctionLiteral)?.property ?? defaultValue
    ```

### Property Declarations

- Stored properties: attributes on same line unless long
- Computed properties: attributes on same line
- Function attributes: Place on previous line (`@MainActor`, `@discardableResult`)

```swift
@Published var isConnected: Bool = false
private var connectionPool: [Connection] = []

@MainActor
func updateUI() {
```

### Closures & Functions

- Implicit returns preferred for single-expression closures/computed properties
- Strip unused closure arguments (use `_` for unused)
- Remove `self` in closures unless required for capture semantics
- Prefer trailing closure syntax when last parameter
- **Avoid unused optional bindings**: Use `!= nil` instead of `let _ =` for existence checks
    ```swift
    // Bad
    guard let _ = textContainer else { return nil }

    // Good
    guard textContainer != nil else { return nil }
    ```

### Collections

- Use `isEmpty` instead of `count == 0`
- Use `contains(_:)` over `filter { }.count > 0`
- Use `first(where:)` over `filter { }.first`
- Use `allSatisfy(_:)` when checking all elements
- **Remove unused enumeration**: Don't use `.enumerated()` when index is not needed
    ```swift
    // Bad
    items.enumerated().map { _, item in item.value }

    // Good
    items.map { item in item.value }
    // Or with key path:
    items.map(\.value)
    ```

### Operators & Spacing

- Space around binary operators: `a + b`, `x = y`
- No space for ranges: `0..<10`, `0...9`
- Type delimiter space after colon: `var name: String`
- Guard/else on same line: `guard condition else {`

### Code Organization

- Maximum function body: 160 lines (warning), 250 (error)
- Maximum type body: 1100 lines (warning), 1500 (error)
- Maximum file length: 1200 lines (warning), 1800 (error)
- Cyclomatic complexity: 40 (warning), 60 (error)
- Organize declarations within types: properties → init → methods

### Refactoring Large Files

When files approach or exceed SwiftLint limits, follow these strategies:

#### 1. Extension Pattern for Large Types

Extract logical sections into separate extension files:

- Place extensions in `Extensions/` subfolder within the same directory
- Naming: `TypeName+Category.swift` (e.g., `MainContentCoordinator+RowOperations.swift`)
- Group related functionality (pagination, filtering, row operations, etc.)
- Keep the main file focused on core type definition and primary responsibilities

**Example structure:**
```
TablePro/Views/Main/
├── MainContentCoordinator.swift          # Core class definition
└── Extensions/
    ├── MainContentCoordinator+RowOperations.swift
    ├── MainContentCoordinator+Pagination.swift
    ├── MainContentCoordinator+Filtering.swift
    └── MainContentCoordinator+Alerts.swift
```

**Extension file template:**
```swift
//
//  MainContentCoordinator+RowOperations.swift
//  TablePro
//
//  Row manipulation operations for MainContentCoordinator
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Row Operations

    func addNewRow(...) {
        // Implementation
    }
}
```

#### 2. Helper Method Extraction for Long Functions

When functions exceed 160 lines:

- Extract logical blocks into private helper methods
- Use descriptive names that explain the helper's purpose
- Place helper methods near their calling function
- Consider creating helper structs for complex parameter groups

**Example:**
```swift
// Before: 200-line function
private func executeQuery(_ query: String, parameters: [Any?]) throws -> Result {
    // 200 lines of code...
}

// After: Main function + helpers
private func executeQuery(_ query: String, parameters: [Any?]) throws -> Result {
    let stmt = try prepareStatement(query)
    defer { cleanupStatement(stmt) }

    let bindings = try bindParameters(parameters, to: stmt)
    defer { bindings.cleanup() }

    try executeStatement(stmt)
    return try fetchResults(from: stmt)
}

private func bindParameters(_ parameters: [Any?], to stmt: Statement) throws -> Bindings {
    // Focused binding logic
}

private func fetchResults(from stmt: Statement) throws -> Result {
    // Focused result fetching logic
}
```

#### 3. When to Refactor

- **Proactive**: When adding features that would push limits
- **Reactive**: When SwiftLint warnings appear (before errors)
- **Strategic**: Group by domain logic, not arbitrary line counts

### Disabled SwiftLint Rules (Allowed)

These are explicitly allowed in this codebase:

- Trailing commas in collections
- TODO/FIXME comments
- Force try (`try!`) when appropriate
- Static over final class
- Multiple trailing closures
- Opening brace on same line (enforced by SwiftFormat)

## Common Patterns

### Logger Usage

Use OSLog for debugging:

```swift
import os

private static let logger = Logger(subsystem: "com.TablePro", category: "ComponentName")
logger.debug("Connection established")
logger.error("Failed to connect: \(error.localizedDescription)")
```

### SwiftUI View Models

```swift
@StateObject private var viewModel = MyViewModel()
@EnvironmentObject private var appState: AppState
@Published var items: [Item] = []
```

### Database Connections

Follow existing driver patterns in `TablePro/Core/Database/`

### Error Propagation

Prefer throwing errors over returning optionals for failure cases

## Documentation

The documentation site is located in a separate repository at `tablepro.app/docs/` (Mintlify-powered).

### When to Update Documentation

**IMPORTANT**: When adding features or making significant changes, always update the corresponding documentation.

| Change Type | Documentation to Update |
|-------------|------------------------|
| New feature | Add to relevant feature page in `docs/features/` |
| New setting/preference | Update `docs/customization/settings.mdx` or related page |
| UI changes | Update relevant page + add screenshot placeholder |
| Keyboard shortcut changes | Update `docs/features/keyboard-shortcuts.mdx` |
| Database driver changes | Update `docs/databases/` pages |
| Connection options | Update `docs/databases/overview.mdx` |
| Import/Export changes | Update `docs/features/import-export.mdx` |
| Build process changes | Update `docs/development/building.mdx` |
| Architecture changes | Update `docs/development/architecture.mdx` |

### Documentation Structure

```
tablepro.app/docs/
├── index.mdx                    # Introduction
├── quickstart.mdx               # Getting started guide
├── installation.mdx             # Installation instructions
├── databases/                   # Database connection guides
│   ├── overview.mdx
│   ├── mysql.mdx
│   ├── postgresql.mdx
│   ├── sqlite.mdx
│   └── ssh-tunneling.mdx
├── features/                    # Feature documentation
│   ├── sql-editor.mdx
│   ├── data-grid.mdx
│   ├── autocomplete.mdx
│   ├── table-structure.mdx
│   ├── import-export.mdx
│   ├── query-history.mdx
│   └── keyboard-shortcuts.mdx
├── customization/               # Settings and customization
│   ├── settings.mdx
│   ├── appearance.mdx
│   └── editor-settings.mdx
└── development/                 # Developer documentation
    ├── setup.mdx
    ├── architecture.mdx
    ├── code-style.mdx
    └── building.mdx
```

### Documentation Guidelines

- Use Mintlify MDX components (`<Tip>`, `<Warning>`, `<Note>`, `<CardGroup>`, etc.)
- Add screenshot placeholders: `{/* Screenshot: description */}`
- Use Mermaid for diagrams (use `<br>` for line breaks, not `\n`)
- Keep content accurate and up-to-date with code changes
- The docs repo is separate: `git@github.com:datlechin/tablepro.app.git`

### Preview Documentation Locally

```bash
cd tablepro.app/docs
npm i -g mint
mint dev
# Open http://localhost:3000
```

## Notes for AI Agents

- **Never** use tabs for indentation (except Makefile/pbxproj)
- **Always** run `swiftlint lint --strict` after making changes to verify compliance
- **Always** update documentation when adding or changing features — this is a **mandatory** step, not optional. After implementing a feature, check the "When to Update Documentation" table above and update both English (`docs/`) and Vietnamese (`docs/vi/`) pages. Key docs to check:
  - New keyboard shortcuts → `features/keyboard-shortcuts.mdx`
  - Tab behavior changes → `features/tabs.mdx`
  - UI changes → relevant feature page + screenshot placeholder
  - New features → add to relevant page or create new page
- Check .swiftformat and .swiftlint.yml for authoritative rules
- Preserve existing architecture: SwiftUI + AppKit, native frameworks only
- This is macOS-only; no iOS/watchOS/tvOS code needed
- Keep line length under 120 characters when possible
- All new view controllers should use SwiftUI unless AppKit is required
- When refactoring for SwiftLint compliance:
  - Extract extensions before splitting classes
  - Maintain logical grouping of related functionality
  - Preserve all existing functionality and behavior
  - Update imports in extension files as needed
  - Test that build succeeds after refactoring
- Documentation is in a separate repo (`tablepro.app/`) - commit docs changes there
