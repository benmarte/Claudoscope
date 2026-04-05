# LLM & CLI Harness Agnostic — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all Claude Code-specific hardcoding with a `Workspace` abstraction (harness type + root dir + capabilities), making Claudoscope work with Claude Code, Qwen, Codex, OpenCode, and any future harness sharing the `projects/<encoded-path>/*.jsonl` convention.

**Architecture:** A `HarnessConfig` value type (`HarnessType` enum + `HarnessCapabilities` struct + `Workspace` model) replaces `ClaudeProfile`. `WorkspaceManager` replaces `ProfileManager`. All services receive `workspace: Workspace` instead of `claudeDir: URL`. Views consult `workspace.capabilities` to show/hide sidebar sections adaptively.

**Tech Stack:** Swift 5.9+, SwiftUI, Combine, XCTest, UserDefaults (persistence), FileManager

---

## Preflight

Before starting, check the state of the modified file on master:

```bash
git diff Claudoscope/Views/FullWindow/Settings/SettingsMainPanelView.swift
```

If it contains partial Profiles work from the `feature/claude-profiles` branch, discard it — the workspace design supersedes it:

```bash
git checkout -- Claudoscope/Views/FullWindow/Settings/SettingsMainPanelView.swift
```

The `feature/claude-profiles` branch and worktree are superseded by this plan. Do not merge them.

---

## File Map

### New Files
| File | Responsibility |
|---|---|
| `Claudoscope/Models/HarnessModels.swift` | `HarnessType`, `HarnessCapabilities`, `Workspace` types |
| `Claudoscope/Services/WorkspaceManager.swift` | CRUD + persistence + migration for workspaces |
| `Claudoscope/Services/HarnessFileWatcher.swift` | File watcher (replaces `ClaudeFileWatcher.swift`) |
| `ClaudoscopeTests/WorkspaceTests.swift` | Unit tests for `Workspace`, `HarnessCapabilities`, `HarnessType` |
| `ClaudoscopeTests/WorkspaceManagerTests.swift` | Unit tests for `WorkspaceManager` |

### Modified Files
| File | Change |
|---|---|
| `Claudoscope/Models/ConfigModels.swift` | Remove `ClaudeProfile` struct |
| `Claudoscope/ClaudoscopeApp.swift` | Inject `WorkspaceManager` instead of `ProfileManager` |
| `Claudoscope/Store/SessionStore.swift` | Take `WorkspaceManager`, remove hardcoded `~/.claude`, capability-gate services |
| `Claudoscope/Services/ConfigService.swift` | `init(workspace:)` replaces `init(claudeDir:)` |
| `Claudoscope/Services/ConfigService+Memory.swift` | Use `workspace.capabilities.memoryFileName`, gate profile on `hasProfileData` |
| `Claudoscope/Services/ConfigService+MCPs.swift` | Gate `claude.json` and `.claude.json` sources on capabilities |
| `Claudoscope/Services/ConfigService+Skills.swift` | No string changes — path flows from `claudeDir` computed var |
| `Claudoscope/Services/ConfigService+Commands.swift` | No string changes — path flows from `claudeDir` computed var |
| `Claudoscope/Services/PlansService.swift` | `init(workspace:)` |
| `Claudoscope/Services/TimelineService.swift` | `init(workspace:)` |
| `Claudoscope/Services/ProjectScanner.swift` | `init(workspace:)` |
| `Claudoscope/Services/ConfigLinterService.swift` | `init(workspace:)`, adds `harness` computed var for dynamic messages |
| `Claudoscope/Services/ConfigLinterService+ClaudeMd.swift` | Dynamic `memoryFileName` and harness name throughout |
| `Claudoscope/Services/ConfigLinterService+CrossCutting.swift` | Use `workspace.rootDirURL` instead of `.appendingPathComponent(".claude")` |
| `Claudoscope/Services/ConfigLinterService+Sessions.swift` | Dynamic harness name; gate `/compact`/`/clear` hints on `.claudeCode` |
| `Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift` | Adaptive sidebar (capability-driven) + Workspaces entry |
| `Claudoscope/Views/FullWindow/Settings/SettingsMainPanelView.swift` | Workspaces section (add/edit/delete/activate) |
| `Claudoscope/Views/FullWindow/Config/MemoryViews.swift` | Dynamic harness name in empty-state strings |
| `Claudoscope/Views/FullWindow/Settings/SettingsSections.swift` | Dynamic harness name, gate profile-specific strings on capability |
| *(menu bar popover view — find path in Task 13)* | Workspace switcher between title and today chart |

### Deleted Files
| File | Reason |
|---|---|
| `Claudoscope/Services/ClaudeFileWatcher.swift` | Replaced by `HarnessFileWatcher.swift` |

---

## Phase 1 — Core Model

### Task 1: Define HarnessType, HarnessCapabilities, Workspace

**Files:**
- Create: `Claudoscope/Models/HarnessModels.swift`
- Create: `ClaudoscopeTests/WorkspaceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ClaudoscopeTests/WorkspaceTests.swift`:

```swift
import XCTest
@testable import Claudoscope

final class WorkspaceTests: XCTestCase {

    func test_claudeCode_defaultCapabilities() {
        let caps = HarnessType.claudeCode.defaultCapabilities
        XCTAssertEqual(caps.memoryFileName, "CLAUDE.md")
        XCTAssertTrue(caps.hasTimeline)
        XCTAssertTrue(caps.hasPlans)
        XCTAssertTrue(caps.hasLinting)
        XCTAssertTrue(caps.hasProfileData)
        XCTAssertEqual(caps.mcpConfigFileName, "claude.json")
        XCTAssertEqual(caps.hookEventNames, [
            "PreToolUse", "PostToolUse", "SessionStart",
            "Stop", "UserPromptSubmit", "Notification"
        ])
    }

    func test_qwen_defaultCapabilities_areAllFalse() {
        let caps = HarnessType.qwen.defaultCapabilities
        XCTAssertNil(caps.memoryFileName)
        XCTAssertFalse(caps.hasTimeline)
        XCTAssertFalse(caps.hasPlans)
        XCTAssertFalse(caps.hasLinting)
        XCTAssertFalse(caps.hasProfileData)
        XCTAssertNil(caps.mcpConfigFileName)
        XCTAssertTrue(caps.hookEventNames.isEmpty)
    }

    func test_codex_defaultCapabilities_areAllFalse() {
        let caps = HarnessType.codex.defaultCapabilities
        XCTAssertNil(caps.memoryFileName)
        XCTAssertFalse(caps.hasTimeline)
        XCTAssertFalse(caps.hasPlans)
        XCTAssertFalse(caps.hasLinting)
        XCTAssertFalse(caps.hasProfileData)
        XCTAssertNil(caps.mcpConfigFileName)
    }

    func test_openCode_defaultCapabilities_areAllFalse() {
        let caps = HarnessType.openCode.defaultCapabilities
        XCTAssertNil(caps.memoryFileName)
        XCTAssertFalse(caps.hasTimeline)
        XCTAssertFalse(caps.hasPlans)
        XCTAssertFalse(caps.hasLinting)
        XCTAssertFalse(caps.hasProfileData)
        XCTAssertNil(caps.mcpConfigFileName)
    }

    func test_workspace_capabilitiesUsesHarnessDefaults_whenNoCustom() {
        let ws = Workspace(id: UUID(), name: "Test", harnessType: .claudeCode, rootDir: "~/.claude")
        XCTAssertEqual(ws.capabilities, HarnessType.claudeCode.defaultCapabilities)
    }

    func test_workspace_capabilitiesUsesCustom_whenSet() {
        let custom = HarnessCapabilities(
            memoryFileName: "AGENTS.md",
            hasTimeline: false, hasPlans: false, hasLinting: false,
            hasProfileData: false, hookEventNames: [], mcpConfigFileName: nil
        )
        let ws = Workspace(
            id: UUID(), name: "Custom", harnessType: .custom,
            rootDir: "/tmp", customCapabilities: custom
        )
        XCTAssertEqual(ws.capabilities.memoryFileName, "AGENTS.md")
    }

    func test_workspace_rootDirURL_expandsTilde() {
        let ws = Workspace(id: UUID(), name: "Test", harnessType: .claudeCode, rootDir: "~/.claude")
        XCTAssertFalse(ws.rootDirURL.path.hasPrefix("~"))
        XCTAssertTrue(ws.rootDirURL.path.hasSuffix("/.claude"))
    }

    func test_workspace_isCodable() throws {
        let ws = Workspace(id: UUID(), name: "Work", harnessType: .qwen, rootDir: "~/.qwen")
        let data = try JSONEncoder().encode(ws)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(decoded.id, ws.id)
        XCTAssertEqual(decoded.name, ws.name)
        XCTAssertEqual(decoded.harnessType, ws.harnessType)
        XCTAssertEqual(decoded.rootDir, ws.rootDir)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Claudoscope -destination 'platform=macOS' \
  -only-testing:ClaudoscopeTests/WorkspaceTests 2>&1 | grep -E "error:|FAILED|PASSED|BUILD"
```

Expected: `BUILD FAILED` — `HarnessType`, `HarnessCapabilities`, `Workspace` not defined yet.

- [ ] **Step 3: Create `HarnessModels.swift`**

Create `Claudoscope/Models/HarnessModels.swift`:

```swift
import Foundation

// MARK: - HarnessType

enum HarnessType: String, Codable, CaseIterable, Identifiable {
    case claudeCode = "claudeCode"
    case qwen       = "qwen"
    case codex      = "codex"
    case openCode   = "openCode"
    case custom     = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .qwen:       return "Qwen"
        case .codex:      return "Codex"
        case .openCode:   return "OpenCode"
        case .custom:     return "Custom"
        }
    }

    // NOTE: Verify ~/.codex and ~/.opencode against actual CLI installs before shipping
    var defaultRootDir: String {
        switch self {
        case .claudeCode: return "~/.claude"
        case .qwen:       return "~/.qwen"
        case .codex:      return "~/.codex"
        case .openCode:   return "~/.opencode"
        case .custom:     return ""
        }
    }

    var defaultCapabilities: HarnessCapabilities {
        switch self {
        case .claudeCode:
            return HarnessCapabilities(
                memoryFileName: "CLAUDE.md",
                hasTimeline: true,
                hasPlans: true,
                hasLinting: true,
                hasProfileData: true,
                hookEventNames: ["PreToolUse", "PostToolUse", "SessionStart",
                                 "Stop", "UserPromptSubmit", "Notification"],
                mcpConfigFileName: "claude.json"
            )
        case .qwen, .codex, .openCode, .custom:
            return HarnessCapabilities(
                memoryFileName: nil,
                hasTimeline: false,
                hasPlans: false,
                hasLinting: false,
                hasProfileData: false,
                hookEventNames: [],
                mcpConfigFileName: nil
            )
        }
    }
}

// MARK: - HarnessCapabilities

struct HarnessCapabilities: Codable, Equatable {
    var memoryFileName: String?
    var hasTimeline: Bool
    var hasPlans: Bool
    var hasLinting: Bool
    var hasProfileData: Bool
    var hookEventNames: [String]
    var mcpConfigFileName: String?
}

// MARK: - Workspace

struct Workspace: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var harnessType: HarnessType
    var rootDir: String
    var customCapabilities: HarnessCapabilities?

    var capabilities: HarnessCapabilities {
        customCapabilities ?? harnessType.defaultCapabilities
    }

    var rootDirURL: URL {
        URL(fileURLWithPath: NSString(string: rootDir).expandingTildeInPath)
    }

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Claudoscope -destination 'platform=macOS' \
  -only-testing:ClaudoscopeTests/WorkspaceTests 2>&1 | grep -E "error:|FAILED|PASSED|BUILD"
```

Expected: All 8 tests PASSED.

- [ ] **Step 5: Commit**

```bash
git add Claudoscope/Models/HarnessModels.swift ClaudoscopeTests/WorkspaceTests.swift
git commit -m "feat: add HarnessType, HarnessCapabilities, Workspace models"
```

---

### Task 2: WorkspaceManager

**Files:**
- Create: `Claudoscope/Services/WorkspaceManager.swift`
- Create: `ClaudoscopeTests/WorkspaceManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ClaudoscopeTests/WorkspaceManagerTests.swift`:

```swift
import XCTest
@testable import Claudoscope

@MainActor
final class WorkspaceManagerTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WorkspaceManagerTests")
        defaults.removePersistentDomain(forName: "WorkspaceManagerTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "WorkspaceManagerTests")
        super.tearDown()
    }

    func test_init_seedsDefaultWorkspace_whenEmpty() {
        let mgr = WorkspaceManager(defaults: defaults)
        XCTAssertEqual(mgr.workspaces.count, 1)
        XCTAssertEqual(mgr.workspaces[0].name, "Default")
        XCTAssertEqual(mgr.workspaces[0].harnessType, .claudeCode)
        XCTAssertEqual(mgr.workspaces[0].rootDir, "~/.claude")
        XCTAssertEqual(mgr.activeWorkspace.id, mgr.workspaces[0].id)
    }

    func test_add_appendsWorkspace() {
        let mgr = WorkspaceManager(defaults: defaults)
        let ws = Workspace(id: UUID(), name: "Qwen Local", harnessType: .qwen, rootDir: "~/.qwen")
        mgr.add(ws)
        XCTAssertEqual(mgr.workspaces.count, 2)
        XCTAssertEqual(mgr.workspaces[1].name, "Qwen Local")
    }

    func test_update_updatesExistingWorkspace() {
        let mgr = WorkspaceManager(defaults: defaults)
        var ws = mgr.workspaces[0]
        ws.name = "Renamed"
        mgr.update(ws)
        XCTAssertEqual(mgr.workspaces[0].name, "Renamed")
    }

    func test_update_updatesActiveWorkspace_whenActive() {
        let mgr = WorkspaceManager(defaults: defaults)
        var ws = mgr.activeWorkspace
        ws.name = "Updated Active"
        mgr.update(ws)
        XCTAssertEqual(mgr.activeWorkspace.name, "Updated Active")
    }

    func test_delete_removesWorkspace() {
        let mgr = WorkspaceManager(defaults: defaults)
        let ws = Workspace(id: UUID(), name: "To Delete", harnessType: .qwen, rootDir: "~/.qwen")
        mgr.add(ws)
        XCTAssertEqual(mgr.workspaces.count, 2)
        mgr.delete(ws)
        XCTAssertEqual(mgr.workspaces.count, 1)
    }

    func test_activate_returnsFalse_whenDirDoesNotExist() {
        let mgr = WorkspaceManager(defaults: defaults)
        let ws = Workspace(id: UUID(), name: "Ghost", harnessType: .custom, rootDir: "/nonexistent/path/xyz")
        XCTAssertFalse(mgr.activate(ws))
    }

    func test_activate_returnsTrue_andSetsActive_whenDirExists() {
        let mgr = WorkspaceManager(defaults: defaults)
        let ws = Workspace(id: UUID(), name: "Tmp", harnessType: .custom, rootDir: "/tmp")
        mgr.add(ws)
        XCTAssertTrue(mgr.activate(ws))
        XCTAssertEqual(mgr.activeWorkspace.id, ws.id)
    }

    func test_persistsAndLoads() {
        let ws = Workspace(id: UUID(), name: "Persisted", harnessType: .qwen, rootDir: "~/.qwen")
        do {
            let mgr = WorkspaceManager(defaults: defaults)
            mgr.add(ws)
        }
        let mgr2 = WorkspaceManager(defaults: defaults)
        XCTAssertEqual(mgr2.workspaces.count, 2)
        XCTAssertEqual(mgr2.workspaces[1].name, "Persisted")
    }

    func test_migrate_convertsClaudeProfiles() {
        struct LegacyProfile: Codable { let id: UUID; let name: String; let path: String }
        let legacy = [LegacyProfile(id: UUID(), name: "Work", path: "~/.claude-work")]
        defaults.set(try! JSONEncoder().encode(legacy), forKey: "claudeProfiles")

        let mgr = WorkspaceManager(defaults: defaults)
        XCTAssertEqual(mgr.workspaces.count, 1)
        XCTAssertEqual(mgr.workspaces[0].name, "Work")
        XCTAssertEqual(mgr.workspaces[0].harnessType, .claudeCode)
        XCTAssertEqual(mgr.workspaces[0].rootDir, "~/.claude-work")
        XCTAssertNil(defaults.data(forKey: "claudeProfiles"), "Legacy key must be removed after migration")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Claudoscope -destination 'platform=macOS' \
  -only-testing:ClaudoscopeTests/WorkspaceManagerTests 2>&1 | grep -E "error:|FAILED|PASSED|BUILD"
```

Expected: `BUILD FAILED` — `WorkspaceManager` not defined yet.

- [ ] **Step 3: Create `WorkspaceManager.swift`**

Create `Claudoscope/Services/WorkspaceManager.swift`:

```swift
import Foundation
import Combine

@MainActor
final class WorkspaceManager: ObservableObject {
    private let workspacesKey = "workspaces"
    private let activeWorkspaceIdKey = "activeWorkspaceId"
    private let defaults: UserDefaults

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var activeWorkspace: Workspace

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateIfNeeded()
        let loaded = Self.load(from: defaults)
        if loaded.isEmpty {
            let seed = Workspace(
                id: UUID(), name: "Default",
                harnessType: .claudeCode, rootDir: "~/.claude"
            )
            workspaces = [seed]
            activeWorkspace = seed
            persist([seed])
        } else {
            workspaces = loaded
            let savedId = defaults.string(forKey: activeWorkspaceIdKey)
                .flatMap { UUID(uuidString: $0) }
            activeWorkspace = loaded.first(where: { $0.id == savedId }) ?? loaded[0]
        }
    }

    @discardableResult
    func activate(_ workspace: Workspace) -> Bool {
        guard FileManager.default.fileExists(atPath: workspace.rootDirURL.path) else {
            return false
        }
        activeWorkspace = workspace
        defaults.set(workspace.id.uuidString, forKey: activeWorkspaceIdKey)
        return true
    }

    func add(_ workspace: Workspace) {
        workspaces.append(workspace)
        persist(workspaces)
    }

    func update(_ workspace: Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[idx] = workspace
        if activeWorkspace.id == workspace.id { activeWorkspace = workspace }
        persist(workspaces)
    }

    func delete(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        if activeWorkspace.id == workspace.id, let first = workspaces.first {
            activeWorkspace = first
            defaults.set(first.id.uuidString, forKey: activeWorkspaceIdKey)
        }
        persist(workspaces)
    }

    // MARK: - Private

    private func persist(_ items: [Workspace]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: workspacesKey)
    }

    private static func load(from defaults: UserDefaults) -> [Workspace] {
        guard let data = defaults.data(forKey: "workspaces"),
              let items = try? JSONDecoder().decode([Workspace].self, from: data)
        else { return [] }
        return items
    }

    private func migrateIfNeeded() {
        guard defaults.data(forKey: "claudeProfiles") != nil,
              defaults.data(forKey: workspacesKey) == nil else { return }
        struct LegacyProfile: Codable { let id: UUID; let name: String; let path: String }
        guard let data = defaults.data(forKey: "claudeProfiles"),
              let profiles = try? JSONDecoder().decode([LegacyProfile].self, from: data)
        else { return }
        let migrated = profiles.map {
            Workspace(id: $0.id, name: $0.name, harnessType: .claudeCode, rootDir: $0.path)
        }
        persist(migrated)
        defaults.removeObject(forKey: "claudeProfiles")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Claudoscope -destination 'platform=macOS' \
  -only-testing:ClaudoscopeTests/WorkspaceManagerTests 2>&1 | grep -E "error:|FAILED|PASSED|BUILD"
```

Expected: All 9 tests PASSED.

- [ ] **Step 5: Commit**

```bash
git add Claudoscope/Services/WorkspaceManager.swift ClaudoscopeTests/WorkspaceManagerTests.swift
git commit -m "feat: add WorkspaceManager with CRUD, persistence, and ClaudeProfile migration"
```

---

### Task 3: Remove ClaudeProfile, wire WorkspaceManager at app startup

**Files:**
- Modify: `Claudoscope/Models/ConfigModels.swift`
- Modify: `Claudoscope/ClaudoscopeApp.swift`

- [ ] **Step 1: Remove `ClaudeProfile` from `ConfigModels.swift`**

Read `Claudoscope/Models/ConfigModels.swift`. Delete the `ClaudeProfile` struct and the `profile: ClaudeProfile?` field in `ExtendedConfig` (if present). These are replaced by `Workspace` in `HarnessModels.swift`.

- [ ] **Step 2: Update `ClaudoscopeApp.swift`**

Read `Claudoscope/ClaudoscopeApp.swift`. Replace any `ProfileManager` reference with `WorkspaceManager`. The init pattern should be:

```swift
@main
struct ClaudoscopeApp: App {
    @StateObject private var workspaceManager: WorkspaceManager
    @StateObject private var sessionStore: SessionStore

    init() {
        let wm = WorkspaceManager()
        _workspaceManager = StateObject(wrappedValue: wm)
        _sessionStore = StateObject(wrappedValue: SessionStore(workspaceManager: wm))
    }

    var body: some Scene {
        // Inject both into environment — keep existing window/scene structure
        // Add .environmentObject(workspaceManager) alongside .environmentObject(sessionStore)
    }
}
```

Note: `SessionStore(workspaceManager:)` is defined in Task 8. If `SessionStore` doesn't compile yet, keep its existing init temporarily and mark with `// TODO: Task 8`.

- [ ] **Step 3: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Fix any remaining `ClaudeProfile` or `ProfileManager` references until it builds.

- [ ] **Step 4: Commit**

```bash
git add Claudoscope/Models/ConfigModels.swift Claudoscope/ClaudoscopeApp.swift
git commit -m "refactor: remove ClaudeProfile, inject WorkspaceManager at app entry point"
```

---

## Phase 2 — Service Layer

### Task 4: HarnessFileWatcher (rename ClaudeFileWatcher)

**Files:**
- Create: `Claudoscope/Services/HarnessFileWatcher.swift`
- Delete: `Claudoscope/Services/ClaudeFileWatcher.swift`

- [ ] **Step 1: Copy, rename, update**

Read `Claudoscope/Services/ClaudeFileWatcher.swift`. Create `Claudoscope/Services/HarnessFileWatcher.swift` with its full content, then apply these changes:

1. Rename class: `ClaudeFileWatcher` → `HarnessFileWatcher`
2. Rename property: `private let claudeDir: URL` → `private let rootDir: URL`
3. Update init: `init(claudeDir: URL)` → `init(workspace: Workspace)` with body `rootDir = workspace.rootDirURL`
4. Replace every `claudeDir` usage in the body with `rootDir`

- [ ] **Step 2: Delete the old file**

```bash
git rm Claudoscope/Services/ClaudeFileWatcher.swift
```

- [ ] **Step 3: Fix `SessionStore.swift` type reference**

In `Claudoscope/Store/SessionStore.swift`, change:
- `private let watcher: ClaudeFileWatcher` → `private var watcher: HarnessFileWatcher?`
- Any `ClaudeFileWatcher(claudeDir:...)` call → `HarnessFileWatcher(workspace: ...)` (full SessionStore rewrite is Task 8)

- [ ] **Step 4: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
git add Claudoscope/Services/HarnessFileWatcher.swift
git commit -m "refactor: rename ClaudeFileWatcher → HarnessFileWatcher, init takes workspace"
```

---

### Task 5: Update ConfigService to accept Workspace

**Files:**
- Modify: `Claudoscope/Services/ConfigService.swift`
- Modify: `Claudoscope/Services/ConfigService+Memory.swift`
- Modify: `Claudoscope/Services/ConfigService+MCPs.swift`
- Modify: `Claudoscope/Services/ConfigService+Skills.swift`
- Modify: `Claudoscope/Services/ConfigService+Commands.swift`

- [ ] **Step 1: Update `ConfigService.swift` init**

Read `Claudoscope/Services/ConfigService.swift`. Change:

```swift
// Before
actor ConfigService {
    let claudeDir: URL
    init(claudeDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")) {
        self.claudeDir = claudeDir
    }
}

// After
actor ConfigService {
    let workspace: Workspace
    var claudeDir: URL { workspace.rootDirURL }  // computed alias — extensions keep working unchanged

    init(workspace: Workspace) {
        self.workspace = workspace
    }
}
```

- [ ] **Step 2: Update `ConfigService+Memory.swift`**

Every `"CLAUDE.md"` literal becomes capability-driven. Read the file, then apply:

```swift
// Replace every: claudeDir.appendingPathComponent("CLAUDE.md")
// With:
guard let memFileName = workspace.capabilities.memoryFileName else { return nil }
// ... then use: claudeDir.appendingPathComponent(memFileName)
```

Gate the `.claude.json` profile section on `hasProfileData`:

```swift
// Wrap the block that reads homeDir.appendingPathComponent(".claude.json"):
guard workspace.capabilities.hasProfileData else { return nil }
// ... existing profile-reading code
```

- [ ] **Step 3: Update `ConfigService+MCPs.swift`**

Gate the `claude.json` secondary source on the capability:

```swift
// Replace: let claudeJsonURL = claudeDir.appendingPathComponent("claude.json")
// With:
if let mcpConfigFileName = workspace.capabilities.mcpConfigFileName {
    let mcpConfigURL = claudeDir.appendingPathComponent(mcpConfigFileName)
    // ... existing loading code unchanged, using mcpConfigURL
}
```

Gate the legacy `~/.claude.json` source on `hasProfileData`:

```swift
if workspace.capabilities.hasProfileData {
    let legacyURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    // ... existing loading code
}
```

- [ ] **Step 4: Verify Skills and Commands extensions need no string changes**

```bash
grep -n '"\.claude\|CLAUDE\|claude\.json' \
  Claudoscope/Services/ConfigService+Skills.swift \
  Claudoscope/Services/ConfigService+Commands.swift
```

Expected: no matches (these files only use `claudeDir` as a base, which now flows from `workspace.rootDirURL`).

- [ ] **Step 5: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6: Commit**

```bash
git add Claudoscope/Services/ConfigService.swift \
        Claudoscope/Services/ConfigService+Memory.swift \
        Claudoscope/Services/ConfigService+MCPs.swift \
        Claudoscope/Services/ConfigService+Skills.swift \
        Claudoscope/Services/ConfigService+Commands.swift
git commit -m "refactor: ConfigService takes workspace, memory and MCP sources gated on capabilities"
```

---

### Task 6: Update PlansService, TimelineService, ProjectScanner

**Files:**
- Modify: `Claudoscope/Services/PlansService.swift`
- Modify: `Claudoscope/Services/TimelineService.swift`
- Modify: `Claudoscope/Services/ProjectScanner.swift`

- [ ] **Step 1: Update each service init — same pattern for all three**

Read each file. Apply this transformation:

```swift
// Before (example — PlansService)
struct PlansService {
    let claudeDir: URL
    init(claudeDir: URL = ...) { self.claudeDir = claudeDir }
}

// After
struct PlansService {
    let workspace: Workspace
    var claudeDir: URL { workspace.rootDirURL }
    init(workspace: Workspace) { self.workspace = workspace }
}
```

Apply the identical change to `TimelineService` and `ProjectScanner`.

- [ ] **Step 2: Verify no residual `.claude` string literals**

```bash
grep -n '"\.claude"' \
  Claudoscope/Services/PlansService.swift \
  Claudoscope/Services/TimelineService.swift \
  Claudoscope/Services/ProjectScanner.swift
```

Expected: no matches.

- [ ] **Step 3: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add Claudoscope/Services/PlansService.swift \
        Claudoscope/Services/TimelineService.swift \
        Claudoscope/Services/ProjectScanner.swift
git commit -m "refactor: PlansService, TimelineService, ProjectScanner take workspace instead of claudeDir"
```

---

### Task 7: Update ConfigLinterService

**Files:**
- Modify: `Claudoscope/Services/ConfigLinterService.swift`
- Modify: `Claudoscope/Services/ConfigLinterService+ClaudeMd.swift`
- Modify: `Claudoscope/Services/ConfigLinterService+CrossCutting.swift`
- Modify: `Claudoscope/Services/ConfigLinterService+Sessions.swift`

- [ ] **Step 1: Update `ConfigLinterService.swift` init**

Read the file. Add `workspace` property and a `harness` convenience var for message strings:

```swift
// After
actor ConfigLinterService {
    let workspace: Workspace
    var claudeDir: URL { workspace.rootDirURL }
    var harness: String { workspace.harnessType.displayName }

    init(workspace: Workspace) { self.workspace = workspace }
}
```

- [ ] **Step 2: Update `ConfigLinterService+ClaudeMd.swift`**

Read the file. Apply these substitutions throughout:

Replace every `"CLAUDE.md"` literal with a dynamic lookup:
```swift
let memFile = workspace.capabilities.memoryFileName ?? "instructions file"
// then use memFile wherever "CLAUDE.md" was hardcoded
```

Replace `"Claude"` in user-facing strings with `harness`:
```swift
// "can cause Claude to misparse" → "can cause \(harness) to misparse"
// "CLAUDE.md has \(n) lines" → "\(memFile) has \(n) lines"
```

Replace `.appendingPathComponent(".claude/rules")` etc. with `.appendingPathComponent("rules")` since `claudeDir` is now the harness root (not the parent of `.claude/`):
```swift
// Before: URL(fileURLWithPath: root).appendingPathComponent(".claude/rules")
// After:  claudeDir.appendingPathComponent("rules")
// (claudeDir == workspace.rootDirURL, which IS the .claude-equivalent dir)
```

- [ ] **Step 3: Update `ConfigLinterService+CrossCutting.swift`**

Read the file. Replace:
```swift
// Before
let claudeDir = URL(fileURLWithPath: root).appendingPathComponent(".claude")
// After
let harnessDir = workspace.rootDirURL
```

Replace user-facing string `"No .claude/ directory found..."`:
```swift
"No \(harness) config directory found at the project root."
```

Replace `"Create a .claude/ directory..."`:
```swift
"Create a config directory to organize rules, skills, and commands."
```

- [ ] **Step 4: Update `ConfigLinterService+Sessions.swift`**

Read the file. Gate `/compact` and `/clear` hints on harness type:

```swift
// Before (any string mentioning /compact or /clear):
"Use /compact proactively..."

// After:
workspace.harnessType == .claudeCode
    ? "Use /compact proactively to reduce context size."
    : "Begin a new session to reduce context size."
```

Replace `"Claude"` in session-context strings:
```swift
// "causing Claude to lose earlier decisions"
"causing \(harness) to lose earlier decisions"

// "Claude rebuilds context from a compressed summary"
"\(harness) rebuilds context from a compressed summary"
```

- [ ] **Step 5: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6: Commit**

```bash
git add Claudoscope/Services/ConfigLinterService.swift \
        Claudoscope/Services/ConfigLinterService+ClaudeMd.swift \
        Claudoscope/Services/ConfigLinterService+CrossCutting.swift \
        Claudoscope/Services/ConfigLinterService+Sessions.swift
git commit -m "refactor: ConfigLinterService takes workspace, lint messages use dynamic harness name"
```

---

### Task 8: Rewrite SessionStore to use WorkspaceManager

**Files:**
- Modify: `Claudoscope/Store/SessionStore.swift`

- [ ] **Step 1: Update properties and init**

Read `Claudoscope/Store/SessionStore.swift` in full. Then:

Replace the `claudeDir` property and any `ProfileManager` property with:
```swift
private let workspaceManager: WorkspaceManager
private var watcher: HarnessFileWatcher?
private var cancellables = Set<AnyCancellable>()

var activeWorkspace: Workspace { workspaceManager.activeWorkspace }
```

Replace `init(...)` with:
```swift
init(workspaceManager: WorkspaceManager) {
    self.workspaceManager = workspaceManager
    workspaceManager.$activeWorkspace
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] workspace in
            self?.reloadForWorkspace(workspace)
        }
        .store(in: &cancellables)
    reloadForWorkspace(workspaceManager.activeWorkspace)
}
```

- [ ] **Step 2: Add `reloadForWorkspace(_:)`**

```swift
private func reloadForWorkspace(_ workspace: Workspace) {
    watcher?.stop()
    configService = ConfigService(workspace: workspace)
    projectScanner = ProjectScanner(workspace: workspace)
    plansService = workspace.capabilities.hasPlans
        ? PlansService(workspace: workspace) : nil
    timelineService = workspace.capabilities.hasTimeline
        ? TimelineService(workspace: workspace) : nil
    linterService = workspace.capabilities.hasLinting
        ? ConfigLinterService(workspace: workspace) : nil
    watcher = HarnessFileWatcher(workspace: workspace)
    watcher?.start { [weak self] in self?.reloadSessions() }
    reloadSessions()
}
```

- [ ] **Step 3: Remove remaining hardcoded `~/.claude` paths**

```bash
grep -n '\.claude\b' Claudoscope/Store/SessionStore.swift
```

For each match that isn't in a comment, replace with `workspaceManager.activeWorkspace.rootDirURL`-relative construction. The most common patterns:

```swift
// Before: home.appendingPathComponent(".claude")
// After: workspaceManager.activeWorkspace.rootDirURL

// Before: .appendingPathComponent(".claude/projects")
// After: workspaceManager.activeWorkspace.rootDirURL.appendingPathComponent("projects")
```

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED|PASSED|BUILD"
```

- [ ] **Step 5: Commit**

```bash
git add Claudoscope/Store/SessionStore.swift
git commit -m "refactor: SessionStore uses WorkspaceManager, all paths derived from active workspace"
```

---

## Phase 3 — Adaptive Sidebar & Dynamic Strings

### Task 9: Capability-driven sidebar

**Files:**
- Modify: `Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift`

- [ ] **Step 1: Read the current sidebar file**

Read `Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift` to understand the entry structure.

- [ ] **Step 2: Add capabilities computed var**

Ensure the view has access to `sessionStore`:
```swift
@EnvironmentObject var sessionStore: SessionStore

private var capabilities: HarnessCapabilities {
    sessionStore.activeWorkspace.capabilities
}
```

- [ ] **Step 3: Wrap sections in capability guards**

Apply `if` guards around each capability-gated entry:

```swift
// Memory
if capabilities.memoryFileName != nil {
    // existing Memory sidebar entry
}

// Plans
if capabilities.hasPlans {
    // existing Plans sidebar entry
}

// Timeline
if capabilities.hasTimeline {
    // existing Timeline sidebar entry
}

// Config / Linter
if capabilities.hasLinting {
    // existing Config sidebar entry
}

// Profile
if capabilities.hasProfileData {
    // existing Profile sidebar entry
}

// Sessions and Settings are NOT gated — always shown
```

Also update the Memory section label to use the dynamic filename:
```swift
// Instead of hardcoded "CLAUDE.md" or "Memory":
capabilities.memoryFileName ?? "Memory"
```

- [ ] **Step 4: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
git add Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift
git commit -m "feat: sidebar sections are capability-driven, hidden when harness doesn't support them"
```

---

### Task 10: Dynamic strings in remaining views

**Files:**
- Modify: `Claudoscope/Views/FullWindow/Config/MemoryViews.swift`
- Modify: `Claudoscope/Views/FullWindow/Settings/SettingsSections.swift`

- [ ] **Step 1: Update `MemoryViews.swift`**

Read the file. Replace:
```swift
// "It will be created when Claude Code writes memory..."
"It will be created when \(sessionStore.activeWorkspace.harnessType.displayName) writes memory."
```

- [ ] **Step 2: Update `SettingsSections.swift`**

Read the file. Apply these replacements:

```swift
// "~/.claude.json may not exist yet."
// Gate entire block on hasProfileData and use workspace root:
if sessionStore.activeWorkspace.capabilities.hasProfileData {
    Text("~\(sessionStore.activeWorkspace.rootDir.dropFirst(1)).json may not exist yet.")
}

// "Claude Code defaults to 30 days."
"\(sessionStore.activeWorkspace.harnessType.displayName) defaults to 30 days."

// "Claude Code will prompt for each tool."
"\(sessionStore.activeWorkspace.harnessType.displayName) will prompt for each tool."

// "...inject variables into Claude Code's shell."
"...inject variables into \(sessionStore.activeWorkspace.harnessType.displayName)'s shell."
```

Hook event name picker: gate on `capabilities.hookEventNames` being non-empty:
```swift
if !sessionStore.activeWorkspace.capabilities.hookEventNames.isEmpty {
    // existing hook event type picker
    // Replace hardcoded event name array with:
    sessionStore.activeWorkspace.capabilities.hookEventNames
}
```

- [ ] **Step 3: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add Claudoscope/Views/FullWindow/Config/MemoryViews.swift \
        Claudoscope/Views/FullWindow/Settings/SettingsSections.swift
git commit -m "feat: view strings use active harness display name, profile and hook sections capability-gated"
```

---

## Phase 4 — Workspaces Settings UI

### Task 11: Workspaces settings section

**Files:**
- Modify: `Claudoscope/Views/FullWindow/Settings/SettingsMainPanelView.swift`
- Modify: `Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift`

- [ ] **Step 1: Add Workspaces entry to sidebar**

Read `SettingsSidebarContent.swift`. Add a "Workspaces" entry to the always-visible section (not capability-gated):

```swift
// Add alongside existing always-shown entries like Sessions, Settings
SidebarNavigationItem(label: "Workspaces", systemImage: "rectangle.stack.badge.person.crop", ...)
// Use whatever NavigationLink/button pattern the existing entries use
```

- [ ] **Step 2: Read `SettingsMainPanelView.swift` to understand section pattern**

Read the file to understand how existing sections (e.g., Profiles, General, etc.) are structured. Follow the same pattern for the Workspaces section.

- [ ] **Step 3: Add `WorkspacesSettingsView`**

Add inside `SettingsMainPanelView.swift` (or as a separate view in the same file):

```swift
struct WorkspacesSettingsView: View {
    @EnvironmentObject var workspaceManager: WorkspaceManager
    @State private var isAdding = false
    @State private var editingWorkspace: Workspace? = nil
    @State private var activationError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(workspaceManager.workspaces) { ws in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ws.name).fontWeight(.medium)
                        Text("\(ws.harnessType.displayName) · \(ws.rootDir)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if ws.id == workspaceManager.activeWorkspace.id {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                    } else {
                        Button("Activate") {
                            if !workspaceManager.activate(ws) {
                                activationError = "Directory not found: \(ws.rootDir)"
                            } else {
                                activationError = nil
                            }
                        }.buttonStyle(.borderless)
                    }
                    Button { editingWorkspace = ws } label: {
                        Image(systemName: "pencil")
                    }.buttonStyle(.borderless)
                    Button { workspaceManager.delete(ws) } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.borderless)
                }
                .padding(.vertical, 6)
                Divider()
            }
            if let err = activationError {
                Text(err).font(.caption).foregroundColor(.red).padding(.top, 4)
            }
            Button("Add Workspace") { isAdding = true }
                .padding(.top, 8)
        }
        .sheet(isPresented: $isAdding) {
            WorkspaceEditSheet(workspace: nil) { workspaceManager.add($0) }
        }
        .sheet(item: $editingWorkspace) { ws in
            WorkspaceEditSheet(workspace: ws) { workspaceManager.update($0) }
        }
    }
}
```

- [ ] **Step 4: Add `WorkspaceEditSheet`**

```swift
struct WorkspaceEditSheet: View {
    let workspace: Workspace?
    let onSave: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var harnessType: HarnessType
    @State private var rootDir: String
    @State private var showFolderPicker = false

    init(workspace: Workspace?, onSave: @escaping (Workspace) -> Void) {
        self.workspace = workspace
        self.onSave = onSave
        _name = State(initialValue: workspace?.name ?? "")
        _harnessType = State(initialValue: workspace?.harnessType ?? .claudeCode)
        _rootDir = State(initialValue: workspace?.rootDir ?? HarnessType.claudeCode.defaultRootDir)
    }

    var body: some View {
        VStack(spacing: 16) {
            Form {
                TextField("Name", text: $name)
                Picker("Harness", selection: $harnessType) {
                    ForEach(HarnessType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: harnessType) { newType in
                    // Auto-fill dir when harness changes (only if still at a default)
                    if HarnessType.allCases.map(\.defaultRootDir).contains(rootDir) {
                        rootDir = newType.defaultRootDir
                    }
                }
                HStack {
                    TextField("Config directory", text: $rootDir)
                    Button("Browse") { showFolderPicker = true }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(Workspace(
                        id: workspace?.id ?? UUID(),
                        name: name, harnessType: harnessType, rootDir: rootDir
                    ))
                    dismiss()
                }
                .disabled(name.isEmpty || rootDir.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(minWidth: 400)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if let url = try? result.get() { rootDir = url.path }
        }
    }
}
```

- [ ] **Step 5: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6: Commit**

```bash
git add Claudoscope/Views/FullWindow/Settings/SettingsMainPanelView.swift \
        Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift
git commit -m "feat: add Workspaces settings section with add/edit/delete/activate UI"
```

---

### Task 12: Deep-link "Manage Workspaces" navigation

**Files:**
- Modify: `Claudoscope/Store/SessionStore.swift`
- Modify: `Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift`

- [ ] **Step 1: Add navigation signal to `SessionStore`**

In `Claudoscope/Store/SessionStore.swift`, add:

```swift
enum SettingsDestination {
    case workspaces
}

@Published var pendingSettingsNavigation: SettingsDestination? = nil
```

- [ ] **Step 2: Observe signal in settings sidebar**

Read `SettingsSidebarContent.swift` to find how the selected sidebar item is tracked (likely a `@State` or `@Binding` var). Then add:

```swift
.onReceive(sessionStore.$pendingSettingsNavigation.compactMap { $0 }) { destination in
    switch destination {
    case .workspaces:
        selectedItem = .workspaces  // use whatever the sidebar item enum/value is
        sessionStore.pendingSettingsNavigation = nil
    }
}
```

- [ ] **Step 3: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add Claudoscope/Store/SessionStore.swift \
        Claudoscope/Views/FullWindow/Settings/SettingsSidebarContent.swift
git commit -m "feat: Manage Workspaces deep-links to workspaces settings panel"
```

---

## Phase 5 — Menu Bar Workspace Switcher

### Task 13: Workspace switcher in menu bar popover

**Files:**
- Modify: *(find the menu bar popover view)*

- [ ] **Step 1: Find the menu bar popover file**

```bash
grep -rl "today\|TodayChart\|popover\|StatusItem" Claudoscope/Views/ --include="*.swift"
```

Open the file containing the `Text("Claudoscope")` title and the today usage chart.

- [ ] **Step 2: Inject `WorkspaceManager`**

Add to the view:
```swift
@EnvironmentObject var workspaceManager: WorkspaceManager
```

- [ ] **Step 3: Insert workspace switcher between title and chart**

Find the `Text("Claudoscope")` and the today chart view. Insert between them:

```swift
Menu {
    ForEach(workspaceManager.workspaces) { ws in
        Button {
            _ = workspaceManager.activate(ws)
        } label: {
            if ws.id == workspaceManager.activeWorkspace.id {
                Label("\(ws.name) · \(ws.harnessType.displayName)", systemImage: "checkmark")
            } else {
                Text("\(ws.name) · \(ws.harnessType.displayName)")
            }
        }
    }
    Divider()
    Button("Manage Workspaces") {
        sessionStore.pendingSettingsNavigation = .workspaces
        NSApp.activate(ignoringOtherApps: true)
        // Open the settings window using the same mechanism as other "open settings" buttons in the codebase
    }
} label: {
    HStack(spacing: 4) {
        Text(workspaceManager.activeWorkspace.name)
            .font(.subheadline).fontWeight(.medium)
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption2)
    }
}
.menuStyle(.borderlessButton)
.fixedSize()
```

- [ ] **Step 4: Build check**

```bash
xcodebuild build -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Manual smoke test**

Run the app and verify:
- [ ] Workspace switcher appears between the Claudoscope title and the today usage chart
- [ ] Dropdown shows all workspaces with a checkmark on the active one
- [ ] "Manage Workspaces" opens the app and navigates directly to Workspaces settings
- [ ] Switching workspaces reloads sessions without a restart
- [ ] Switching to a non-Claude-Code workspace hides Memory, Plans, Timeline, Linter, Profile sidebar sections

- [ ] **Step 6: Final commit**

```bash
git add <the menu bar popover view file>
git commit -m "feat: workspace switcher in menu bar popover between title and today chart"
```

---

## Final Verification

- [ ] **Run full test suite:**

```bash
xcodebuild test -scheme Claudoscope -destination 'platform=macOS' 2>&1 | grep -E "FAILED|PASSED|BUILD"
```

- [ ] **Verify no hardcoded Claude paths remain (except in HarnessModels constants):**

```bash
grep -rn '"\.claude\|CLAUDE\.md\|claude\.json\|claudeDir\b' \
  Claudoscope/ --include="*.swift" \
  | grep -v "HarnessModels.swift\|WorkspaceManager.swift\|\.git"
```

Expected: no matches.

- [ ] **Verify switching to Qwen workspace shows only Sessions and Settings in sidebar.**

- [ ] **Verify switching back to Claude Code workspace shows all sidebar sections including Memory (labeled "CLAUDE.md"), Plans, Timeline, Linter, and Profile.**
