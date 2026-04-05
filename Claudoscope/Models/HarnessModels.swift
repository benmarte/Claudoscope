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
