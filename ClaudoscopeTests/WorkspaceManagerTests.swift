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
