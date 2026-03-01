---
name: xcode-mcp
description: >
  Guidelines for using the Xcode MCP server tools effectively in this project.
  Auto-triggers when working with Xcode builds, previews, tests, or project
  file management. Covers all 20 Xcode MCP tools: project discovery,
  file management, building, testing, previews, and documentation search.
---

# Xcode MCP Server Usage Guide

The Xcode MCP server (introduced in Xcode 26.3) exposes Xcode capabilities
via the Model Context Protocol. The `mcpbridge` binary translates between
MCP and Xcode's internal XPC layer. All tools require a `tabIdentifier`
from an open Xcode workspace window.

## Getting Started

### 1. Discover the Workspace

Always start by listing open Xcode windows to get the `tabIdentifier`:

```
XcodeListWindows
```

This returns workspace info for each open window. Use the `tabIdentifier`
from the relevant workspace in all subsequent tool calls.

### 2. Explore the Project

Use `XcodeLS` to browse the project navigator structure (NOT the filesystem):

```
XcodeLS(tabIdentifier, path: "TablePro/")
XcodeLS(tabIdentifier, path: "TablePro/Views/", recursive: true)
```

Use `XcodeGlob` to find files by pattern:

```
XcodeGlob(tabIdentifier, pattern: "**/*.swift")
XcodeGlob(tabIdentifier, pattern: "*.swift", path: "TablePro/Views/")
```

Use `XcodeGrep` to search file contents:

```
XcodeGrep(tabIdentifier, pattern: "class DatabaseManager")
XcodeGrep(tabIdentifier, pattern: "TODO", outputMode: "content", linesContext: 2)
```

## Tool Reference

### Project Discovery

| Tool | Purpose |
|------|---------|
| `XcodeListWindows` | List open Xcode windows and get `tabIdentifier` |
| `XcodeLS` | Browse project navigator structure (not filesystem) |
| `XcodeGlob` | Find files by wildcard pattern |
| `XcodeGrep` | Search file contents with regex |

### File Operations

| Tool | Purpose |
|------|---------|
| `XcodeRead` | Read file contents (cat -n format, 600 lines default) |
| `XcodeWrite` | Create or overwrite files (auto-adds to project) |
| `XcodeUpdate` | Edit files via string replacement (like Edit tool) |
| `XcodeRM` | Remove files from project (optionally delete from disk) |
| `XcodeMV` | Move, rename, or copy files in project |
| `XcodeMakeDir` | Create directories/groups in project |

### Build & Run

| Tool | Purpose |
|------|---------|
| `BuildProject` | Build the active scheme and wait for completion |
| `GetBuildLog` | Get build log entries, filterable by severity/pattern/glob |
| `ExecuteSnippet` | Run a code snippet in the context of a source file |

### Testing

| Tool | Purpose |
|------|---------|
| `GetTestList` | List all tests from active scheme's test plan |
| `RunAllTests` | Run all tests |
| `RunSomeTests` | Run specific tests by target and identifier |

### Previews & Diagnostics

| Tool | Purpose |
|------|---------|
| `RenderPreview` | Build and snapshot a SwiftUI `#Preview` |
| `XcodeRefreshCodeIssuesInFile` | Get compiler diagnostics for a specific file |
| `XcodeListNavigatorIssues` | List all issues in Xcode's Issue Navigator |
| `DocumentationSearch` | Search Apple Developer Documentation semantically |

## Key Rules

### Paths are project-relative, NOT filesystem paths

All `XcodeRead`, `XcodeWrite`, `XcodeUpdate`, `XcodeRM`, `XcodeMV`, `XcodeLS`,
`XcodeGlob`, `XcodeGrep` use **Xcode project navigator paths**, not absolute
filesystem paths.

```
# Correct
XcodeRead(tabIdentifier, filePath: "TablePro/Views/MainContentView.swift")

# Wrong — do NOT use filesystem paths
XcodeRead(tabIdentifier, filePath: "/Users/ngoquocdat/Projects/TablePro/TablePro/Views/MainContentView.swift")
```

### Prefer Xcode tools over filesystem tools when Xcode is open

When an Xcode workspace is open, prefer Xcode MCP tools over filesystem
equivalents (`Read`, `Write`, `Edit`, `Glob`, `Grep`). Benefits:

- `XcodeWrite` automatically adds new files to the Xcode project structure
- `XcodeRM` properly removes files from the project navigator
- `XcodeMV` updates project references when moving files
- `XcodeGrep`/`XcodeGlob` search within the project scope, not the whole filesystem

**Exception**: Use filesystem tools (`Read`, `Edit`, `Write`) for files outside
the Xcode project (e.g., scripts, CI configs, root-level dotfiles, `CLAUDE.md`).

### Build workflow

1. Make changes with `XcodeWrite` or `XcodeUpdate`
2. Build with `BuildProject` to verify compilation
3. If build fails, check errors with `GetBuildLog(tabIdentifier, severity: "error")`
4. Check specific file diagnostics with `XcodeRefreshCodeIssuesInFile`
5. Fix issues and rebuild

### Test workflow

1. Get available tests: `GetTestList`
2. Run specific tests: `RunSomeTests` with `targetName` and `testIdentifier`
3. Run all tests: `RunAllTests` (slower, use sparingly)

To run a specific test:

```json
RunSomeTests(tabIdentifier, tests: [
  { "targetName": "TableProTests", "testIdentifier": "SidebarViewModelTests/testLoadTables" }
])
```

### Preview workflow

Render a SwiftUI preview to verify UI changes:

```
RenderPreview(tabIdentifier, sourceFilePath: "TablePro/Views/Sidebar/SidebarView.swift")
```

Use `previewDefinitionIndexInFile` (0-based) if the file has multiple `#Preview` blocks.

### ExecuteSnippet — run code in context

Run arbitrary Swift code in the context of a source file. The snippet has
access to all declarations visible from that file (including `fileprivate`).
Output is captured from `print` statements.

```
ExecuteSnippet(
  tabIdentifier,
  sourceFilePath: "TablePro/Core/Database/DatabaseManager.swift",
  codeSnippet: "print(DatabaseManager.shared)"
)
```

### Documentation search

Search Apple's developer docs semantically. Optionally filter by framework:

```
DocumentationSearch(query: "NSTableView drag and drop")
DocumentationSearch(query: "SwiftUI sheet presentation", frameworks: ["SwiftUI"])
```

## Common Patterns for This Project

### Adding a new Swift file

```
XcodeWrite(tabIdentifier,
  filePath: "TablePro/Views/NewFeature/NewFeatureView.swift",
  content: "import SwiftUI\n\nstruct NewFeatureView: View { ... }")
```

This creates the file AND adds it to the Xcode project navigator automatically.

### Checking build errors after changes

```
BuildProject(tabIdentifier)
# Then if errors:
GetBuildLog(tabIdentifier, severity: "error")
# Or for a specific file:
XcodeRefreshCodeIssuesInFile(tabIdentifier, filePath: "TablePro/Views/SomeView.swift")
```

### Finding all issues in the project

```
XcodeListNavigatorIssues(tabIdentifier, severity: "warning")
```

### Running tests for a specific file

```
GetTestList(tabIdentifier)
# Find the test identifiers, then:
RunSomeTests(tabIdentifier, tests: [
  { "targetName": "TableProTests", "testIdentifier": "SidebarViewModelTests" }
])
```

## Troubleshooting

- **"No windows found"**: Ensure Xcode is open with the TablePro project.
  The MCP server communicates with Xcode via XPC — Xcode must be running.
- **Build fails with package errors**: The project uses `-skipPackagePluginValidation`
  for CLI builds, but Xcode MCP builds use the scheme's settings directly.
  If SPM packages haven't resolved, open Xcode and let it resolve first.
- **SourceKit false positives**: SourceKit diagnostics from `XcodeRefreshCodeIssuesInFile`
  may show "Cannot find type X in scope" for types defined in other files.
  Always verify with `BuildProject` for real errors.
- **Large file reads**: `XcodeRead` defaults to 600 lines. Use `offset` and
  `limit` parameters for files larger than that.
