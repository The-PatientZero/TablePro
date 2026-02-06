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

### Optionals & Error Handling

- Avoid force unwrapping (`!`) and force casting (`as!`) - use SwiftLint warnings as guide
- Prefer `if let` or `guard let` for unwrapping
- Use `guard` for early returns to reduce nesting
- Fatal errors must include descriptive messages
- Don't use force try (`try!`) except in tests or guaranteed scenarios

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

### Collections

- Use `isEmpty` instead of `count == 0`
- Use `contains(_:)` over `filter { }.count > 0`
- Use `first(where:)` over `filter { }.first`
- Use `allSatisfy(_:)` when checking all elements

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

## Notes for AI Agents

- **Never** use tabs for indentation (except Makefile/pbxproj)
- Run SwiftLint after making changes to verify compliance
- Check .swiftformat and .swiftlint.yml for authoritative rules
- Preserve existing architecture: SwiftUI + AppKit, native frameworks only
- This is macOS-only; no iOS/watchOS/tvOS code needed
- Keep line length under 120 characters when possible
- All new view controllers should use SwiftUI unless AppKit is required
