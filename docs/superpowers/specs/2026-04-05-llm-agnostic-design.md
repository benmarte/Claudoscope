# Claudoscope — LLM & CLI Harness Agnostic Design

**Date:** 2026-04-05  
**Status:** Approved  
**Replaces:** `feature/claude-profiles` branch (ClaudeProfile / ProfileManager)

---

## Overview

Claudoscope is currently hardcoded to Claude Code's config directory (`~/.claude`), file conventions (`CLAUDE.md`, `claude.json`, `history.jsonl`), and protocol names (`PreToolUse`, `PostToolUse`, etc.). This design makes it support any CLI coding harness that follows the same `projects/<encoded-path>/*.jsonl` convention — initially Claude Code, Qwen, Codex, and OpenCode — with a clean extension path for future harnesses.

The unit of switching is a **Workspace**: a named slot combining a harness type and a root config directory. This replaces the `ClaudeProfile` / `ProfileManager` concept from the unmerged profiles branch.

---

## Data Model

### `HarnessType`

```swift
enum HarnessType: String, Codable, CaseIterable {
    case claudeCode = "claudeCode"
    case qwen       = "qwen"
    case codex      = "codex"
    case openCode   = "openCode"
    case custom     = "custom"

    var displayName: String       // "Claude Code", "Qwen", "Codex", "OpenCode", "Custom"
    var defaultRootDir: String    // "~/.claude", "~/.qwen", "~/.codex"(*), "~/.opencode"(*), ""
    // (*) Codex and OpenCode default dirs to be verified against their actual CLI installs before Phase 1
    var defaultCapabilities: HarnessCapabilities
}
```

### `HarnessCapabilities`

```swift
struct HarnessCapabilities: Codable {
    var memoryFileName: String?    // "CLAUDE.md" (Claude Code), nil for others
    var hasTimeline: Bool          // history.jsonl present
    var hasPlans: Bool             // plans/ directory
    var hasLinting: Bool           // config linter supported
    var hasProfileData: Bool       // .claude.json account info
    var hookEventNames: [String]   // ["PreToolUse","PostToolUse","SessionStart","Stop","UserPromptSubmit","Notification"] or []
    var mcpConfigFileName: String? // "claude.json" (Claude Code only), nil for others
}
```

Built-in defaults per harness type:

| HarnessType | memoryFileName | timeline | plans | linting | profileData | hooks | mcpConfigFile |
|---|---|---|---|---|---|---|---|
| claudeCode | `CLAUDE.md` | ✓ | ✓ | ✓ | ✓ | 6 events | `claude.json` |
| qwen | nil | ✗ | ✗ | ✗ | ✗ | [] | nil |
| codex | nil | ✗ | ✗ | ✗ | ✗ | [] | nil |
| openCode | nil | ✗ | ✗ | ✗ | ✗ | [] | nil |
| custom | user-configured | user-configured | … | … | … | … | … |

### `Workspace`

```swift
struct Workspace: Codable, Identifiable {
    let id: UUID
    var name: String                          // "Work Claude", "Qwen Local"
    var harnessType: HarnessType
    var rootDir: String                       // "~/.claude", "~/.qwen", etc.
    var customCapabilities: HarnessCapabilities?  // only used for .custom type

    // Computed
    var capabilities: HarnessCapabilities {
        customCapabilities ?? harnessType.defaultCapabilities
    }
    var rootDirURL: URL {
        URL(fileURLWithPath: NSString(string: rootDir).expandingTildeInPath)
    }
}
```

**First-launch seeding:** If `"workspaces"` key is absent or empty in `UserDefaults`, create:
```
Workspace(name: "Default", harnessType: .claudeCode, rootDir: "~/.claude")
```

**Migration:** On first launch after update, if `"claudeProfiles"` key exists in `UserDefaults`, convert each `ClaudeProfile` to a `Workspace` with `harnessType: .claudeCode`, then delete `"claudeProfiles"`.

---

## WorkspaceManager

Replaces `ProfileManager`.

```swift
@MainActor
final class WorkspaceManager: ObservableObject {
    @Published private(set) var workspaces: [Workspace]
    @Published private(set) var activeWorkspace: Workspace

    func activate(_ workspace: Workspace) -> Bool  // false if rootDir doesn't exist on disk
    func add(_ workspace: Workspace)
    func update(_ workspace: Workspace)
    func delete(_ workspace: Workspace)
}
```

Persists `workspaces` and `activeWorkspaceId` to `UserDefaults`. Injected into the SwiftUI environment and into `SessionStore` at app startup.

---

## SessionStore Changes

- `init(workspaceManager: WorkspaceManager)` replaces `init(profileManager: ProfileManager)`
- Subscribes to `workspaceManager.$activeWorkspace`
- On change, calls `reloadForWorkspace(_:)`:
  1. Stops `HarnessFileWatcher`
  2. Rebuilds all services with new workspace
  3. Conditionally instantiates capability-gated services:
     - `PlansService` only if `capabilities.hasPlans`
     - `TimelineService` only if `capabilities.hasTimeline`
     - `ConfigLinterService` only if `capabilities.hasLinting`
  4. Restarts `HarnessFileWatcher`
  5. Reloads sessions

Data flow:
```
WorkspaceManager.activeWorkspace  (@Published)
        │
        ▼
SessionStore.reloadForWorkspace(_:)
        ├── HarnessFileWatcher(workspace:)
        ├── ConfigService(workspace:)
        ├── ProjectScanner(workspace:)
        ├── PlansService(workspace:)        ← only if capabilities.hasPlans
        ├── TimelineService(workspace:)     ← only if capabilities.hasTimeline
        └── ConfigLinterService(workspace:) ← only if capabilities.hasLinting
```

No hardcoded `~/.claude` path remains in `SessionStore` after this change.

---

## Service Layer Changes

All services currently taking `claudeDir: URL` are updated to take `workspace: Workspace`. They derive the root path from `workspace.rootDirURL` and conditionally read files based on `workspace.capabilities`.

Renamed: `ClaudeFileWatcher` → `HarnessFileWatcher`.

Variable and type renames (mechanical, no behavior change):
- `claudeDir` → `rootDir` / `harnessRootDir`
- `ClaudeProfile` (ConfigModels) → removed / replaced by `Workspace`
- `claudeProfiles` UserDefaults key → `workspaces`

User-facing strings that currently hardcode "Claude", "CLAUDE.md", or ".claude/" become dynamic — pulled from `workspace.capabilities.memoryFileName` or `workspace.harnessType.displayName` as appropriate. Lint rule message strings mentioning "Claude Code" use the harness display name instead.

---

## Views & UI

### Adaptive Sidebar

Sections shown based on `activeWorkspace.capabilities`:

| Sidebar section | Shown when |
|---|---|
| Sessions | always |
| Memory | `capabilities.memoryFileName != nil` |
| Plans | `capabilities.hasPlans` |
| Timeline | `capabilities.hasTimeline` |
| Config / Linter | `capabilities.hasLinting` |
| Profile | `capabilities.hasProfileData` |
| Settings | always (`settings.json` exists for all harnesses) |

### Menu Bar Popover Layout

```
┌─────────────────────────┐
│  Claudoscope            │  ← title (unchanged)
│  ▾ Work Claude          │  ← workspace switcher (between title and chart)
│  ▓▓▒▒░░  $0.42 today   │  ← today usage chart (unchanged)
│  ─────────────────────  │
│  Sessions...            │
└─────────────────────────┘
```

The workspace switcher dropdown shows all workspaces with the active one checked. "Manage Workspaces" in the dropdown deep-links directly to the Workspaces settings panel (not just opens the app window).

### Settings — Workspaces Section

Replaces the "Profiles" section. Fields per workspace:
- **Name** — text field
- **Harness type** — picker (Claude Code, Qwen, Codex, OpenCode, Custom)
- **Root directory** — folder picker; validated on activate (error shown inline if dir doesn't exist)
- **Custom capabilities** — shown only for `.custom` type: memory file name text field, checkboxes for timeline / plans / linting / profile data

"Manage Workspaces" from the menu bar popover navigates directly to this section. This requires a shared navigation signal (e.g. `pendingSettingsNavigation` published on `SessionStore` or a dedicated router) that the settings sidebar observes to auto-select the Workspaces entry.

---

## Implementation Phases

### Phase 1 — Core model + WorkspaceManager
- Add `HarnessType`, `HarnessCapabilities`, `Workspace` types
- Add `WorkspaceManager` (replaces `ProfileManager`)
- Migrate `UserDefaults` from `ClaudeProfile` → `Workspace` on first launch
- Seed default Claude Code workspace
- No UI or behavior changes yet — app is functionally identical

### Phase 2 — Wire SessionStore + services
- Replace all `claudeDir: URL` parameters with `workspace: Workspace`
- Rename `ClaudeFileWatcher` → `HarnessFileWatcher`
- `SessionStore` hot-swaps on `activeWorkspace` change
- Capability-gated service instantiation
- All `~/.claude` hardcodings removed

### Phase 3 — Adaptive sidebar
- Sidebar sections conditioned on `capabilities`
- Dynamic strings (memory file name, harness name) throughout views and lint messages

### Phase 4 — Workspaces settings UI
- Replace "Profiles" section with "Workspaces"
- Harness type picker, custom capability toggles
- "Manage Workspaces" deep-link navigation

### Phase 5 — Menu bar workspace switcher
- Workspace switcher row between title and today chart
- Harness type icon next to workspace name

---

## Out of Scope

- Renaming the app from "Claudoscope" (branding decision, separate conversation)
- Supporting harnesses with fundamentally different session JSONL formats (today all supported harnesses share Claude Code's format)
- Cloud sync or export of workspaces
