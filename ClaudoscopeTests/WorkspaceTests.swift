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
        XCTAssertTrue(caps.hookEventNames.isEmpty)
    }

    func test_openCode_defaultCapabilities_areAllFalse() {
        let caps = HarnessType.openCode.defaultCapabilities
        XCTAssertNil(caps.memoryFileName)
        XCTAssertFalse(caps.hasTimeline)
        XCTAssertFalse(caps.hasPlans)
        XCTAssertFalse(caps.hasLinting)
        XCTAssertFalse(caps.hasProfileData)
        XCTAssertNil(caps.mcpConfigFileName)
        XCTAssertTrue(caps.hookEventNames.isEmpty)
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

    func test_workspace_rootDirURL_absolutePath_isUnchanged() {
        let ws = Workspace(id: UUID(), name: "T", harnessType: .custom, rootDir: "/tmp/proj")
        XCTAssertEqual(ws.rootDirURL.path, "/tmp/proj")
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
