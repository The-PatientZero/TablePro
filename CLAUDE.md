# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TablePro is a native macOS database client (SwiftUI + AppKit) — a fast, lightweight alternative to TablePlus. macOS 14.0+, Swift 5.9, Universal Binary (arm64 + x86_64).

- **Source**: `TablePro/` — `Core/` (business logic, drivers, services), `Views/` (UI), `Models/` (data structures), `ViewModels/`, `Extensions/`, `Theme/`
- **C bridges**: `CMariaDB/` and `CLibPQ/` in `Core/Database/` — bridging headers for MariaDB and PostgreSQL C connectors
- **Static libs**: `Libs/` — pre-built `libmariadb*.a` (Git LFS tracked)
- **SPM deps**: CodeEditSourceEditor (`main` branch, tree-sitter editor), Sparkle (2.8.1, auto-update). Managed via Xcode, no `Package.swift`.

## Build & Development Commands

```bash
# Build (development) — -skipPackagePluginValidation required for SwiftLint plugin in CodeEditSourceEditor
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation

# Clean build
xcodebuild -project TablePro.xcodeproj -scheme TablePro clean

# Build and run
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation && open build/Debug/TablePro.app

# Release builds
scripts/build-release.sh arm64|x86_64|both

# Lint & format
swiftlint lint                    # Check issues
swiftlint --fix                   # Auto-fix
swiftformat .                     # Format code

# Tests
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -skipPackagePluginValidation
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -skipPackagePluginValidation -only-testing:TableProTests/TestClassName
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -skipPackagePluginValidation -only-testing:TableProTests/TestClassName/testMethodName

# DMG
scripts/create-dmg.sh
```

## Architecture

### Database Drivers

All database operations go through the `DatabaseDriver` protocol (`Core/Database/DatabaseDriver.swift`):

- **MySQLDriver** → `MariaDBConnection` (C connector via CMariaDB)
- **PostgreSQLDriver** → `LibPQConnection` (C connector via CLibPQ)
- **SQLiteDriver** → Foundation's `sqlite3` directly
- **DatabaseManager** — connection pool, lifecycle, primary interface for views/coordinators
- **ConnectionHealthMonitor** — 30s ping, auto-reconnect with exponential backoff

When adding a new driver method: add to `DatabaseDriver` protocol, then implement in all three drivers.

### Editor Architecture (CodeEditSourceEditor)

- **`SQLEditorTheme`** — single source of truth for editor colors/fonts
- **`TableProEditorTheme`** — adapter to CodeEdit's `EditorTheme` protocol
- **`CompletionEngine`** — framework-agnostic; **`SQLCompletionAdapter`** bridges to CodeEdit's `CodeSuggestionDelegate`
- **`EditorTabBar`** — pure SwiftUI tab bar
- Cursor model: `cursorPositions: [CursorPosition]` (multi-cursor via CodeEditSourceEditor)

### Change Tracking Flow

1. User edits cell → `DataChangeManager` records change
2. User clicks Save → `SQLStatementGenerator` produces INSERT/UPDATE/DELETE
3. `DataChangeUndoManager` provides undo/redo
4. `AnyChangeManager` abstracts over concrete manager for protocol-based usage

### Main Coordinator Pattern

`MainContentCoordinator` is the central coordinator, split across 7+ extension files in `Views/Main/Extensions/` (e.g., `+Alerts`, `+Filtering`, `+Pagination`, `+RowOperations`). When adding coordinator functionality, add a new extension file rather than growing the main file.

### Storage Patterns

| What | How | Where |
|------|-----|-------|
| Connection passwords | Keychain | `ConnectionStorage` |
| User preferences | UserDefaults | `AppSettingsStorage` / `AppSettingsManager` |
| Query history | SQLite FTS5 | `QueryHistoryStorage` |
| Tab state | JSON persistence | `TabPersistenceService` / `TabStateStorage` |
| Filter presets | — | `FilterSettingsStorage` |

### Logging

Use OSLog, never `print()`:

```swift
import os
private static let logger = Logger(subsystem: "com.TablePro", category: "ComponentName")
```

## Code Style

**Authoritative sources**: `.swiftlint.yml` and `.swiftformat` — check those files for the full rule set. Key points that aren't obvious from config:

- **4 spaces** indentation (never tabs except Makefile/pbxproj)
- **120 char** target line length (SwiftFormat); SwiftLint warns at 180, errors at 300
- **K&R braces**, LF line endings, no semicolons, no trailing commas
- **Imports**: system frameworks alphabetically → third-party → local, blank line after imports
- **Access control**: always explicit (`private`, `internal`, `public`). Specify on extension, not individual members.
- **No force unwrapping/casting** — use `guard let`, `if let`, `as?`
- **Acronyms as words**: `JsonEncoder` not `JSONEncoder` (except SDK types)
- **No unnecessary comments**: Don't add comments that restate what the code already says. Only comment to explain non-obvious "why" reasoning or clarify genuinely complex logic.
- **Extension access modifiers on the extension itself**:
    ```swift
    // Good
    public extension NSEvent {
        var semanticKeyCode: KeyCode? { ... }
    }
    ```

### SwiftLint Limits

| Metric | Warning | Error |
|--------|---------|-------|
| File length | 1200 | 1800 |
| Type body | 1100 | 1500 |
| Function body | 160 | 250 |
| Cyclomatic complexity | 40 | 60 |

When approaching limits: extract into `TypeName+Category.swift` extension files in an `Extensions/` subfolder. Group by domain logic, not arbitrary line counts.

## Mandatory Rules

These are **non-negotiable** — never skip them:

1. **CHANGELOG.md**: Update under `[Unreleased]` section (Added/Fixed/Changed) for new features and notable changes. But do **not** add a "Fixed" entry for fixing something that is itself still unreleased — if a feature under `[Unreleased]` has a bug, just fix it without adding another CHANGELOG entry. "Fixed" entries are only for bugs in already-released features. Documentation-only changes (`docs/`) do **not** need a CHANGELOG entry.

2. **Localization**: Use `String(localized:)` for new user-facing strings in computed properties, AppKit code, alerts, and error descriptions. SwiftUI view literals (`Text("literal")`, `Button("literal")`) auto-localize. Do NOT localize technical terms (font names, database types, SQL keywords, encoding names).

3. **Documentation**: Update docs in `docs/` (Mintlify-based) when adding/changing features. Key mappings:
   - New keyboard shortcuts → `docs/features/keyboard-shortcuts.mdx`
   - UI/feature changes → relevant `docs/features/*.mdx` page
   - Settings changes → `docs/customization/settings.mdx`
   - Database driver changes → `docs/databases/*.mdx`
   - Update both English (`docs/`) and Vietnamese (`docs/vi/`) pages

4. **Test-first correctness**: When tests fail, fix the **source code** — never adjust tests to match incorrect output. Tests define expected behavior.

5. **Lint after changes**: Run `swiftlint lint --strict` to verify compliance.

6. **Commit messages**: Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). Single line only, no description body. Examples: `docs: fix installation instructions for unsigned app`, `fix: prevent crash on empty query result`, `feat: add CSV export`.

## Agent Execution Strategy

- **Always use subagents** for implementation work. Delegate coding tasks to Task subagents to preserve main context tokens.
- **Always parallelize** independent tasks. Launch all subagents in a single message with multiple Task tool calls.
- **Main context = orchestrator only.** Read files, launch subagents, summarize results, update tracking. Never do heavy implementation directly.
- **Subagent prompts must be self-contained.** Include file paths, the specific problem, and clear instructions.
- **Every implementation must run in a separate worktree.** Use `isolation: "worktree"` when spawning Task subagents for any code changes. This keeps the main branch clean and allows parallel work without conflicts.

## Performance Pitfalls

These have caused real production bugs — be aware when working in editor/autocomplete/persistence code:

- **Never use `string.count`** on large strings — O(n) in Swift. Use `(string as NSString).length` for O(1).
- **Never use `string.index(string.startIndex, offsetBy:)` in loops** on bridged NSStrings — O(n) per call. Use `(string as NSString).character(at:)` for O(1) random access.
- **Never call `ensureLayout(forCharacterRange:)`** — defeats `allowsNonContiguousLayout`. Let layout manager queries trigger lazy local layout.
- **SQL dumps can have single lines with millions of characters** — cap regex/highlight ranges at 10k chars.
- **Tab persistence**: `QueryTab.toPersistedTab()` truncates queries >500KB to prevent JSON freeze. `TabStateStorage.saveLastQuery()` skips writes >500KB.

## CI/CD

GitHub Actions (`.github/workflows/build.yml`) triggered by `v*` tags: lint → build arm64 → build x86_64 → release (DMG/ZIP + Sparkle signatures). Release notes auto-extracted from `CHANGELOG.md`.
