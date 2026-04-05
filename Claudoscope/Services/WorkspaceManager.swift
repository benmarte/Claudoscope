import Foundation
import Combine

@MainActor
final class WorkspaceManager: ObservableObject {
    private static let workspacesKey = "workspaces"
    private static let activeWorkspaceIdKey = "activeWorkspaceId"
    private let defaults: UserDefaults

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var activeWorkspace: Workspace

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateIfNeeded(defaults: defaults)
        let loaded = Self.load(from: defaults)
        if loaded.isEmpty {
            let seed = Workspace(
                id: UUID(), name: "Default",
                harnessType: .claudeCode, rootDir: "~/.claude"
            )
            workspaces = [seed]
            activeWorkspace = seed
            Self.persist(items: [seed], defaults: defaults)
        } else {
            workspaces = loaded
            let savedId = defaults.string(forKey: Self.activeWorkspaceIdKey)
                .flatMap { UUID(uuidString: $0) }
            activeWorkspace = loaded.first(where: { $0.id == savedId }) ?? loaded[0]
        }
    }

    @discardableResult
    func activate(_ workspace: Workspace) -> Bool {
        guard workspaces.contains(where: { $0.id == workspace.id }) else { return false }
        guard FileManager.default.fileExists(atPath: workspace.rootDirURL.path) else { return false }
        activeWorkspace = workspace
        defaults.set(workspace.id.uuidString, forKey: Self.activeWorkspaceIdKey)
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
        if workspaces.isEmpty {
            let seed = Workspace(id: UUID(), name: "Default", harnessType: .claudeCode, rootDir: "~/.claude")
            workspaces = [seed]
            activeWorkspace = seed
            defaults.set(seed.id.uuidString, forKey: Self.activeWorkspaceIdKey)
        } else if activeWorkspace.id == workspace.id {
            activeWorkspace = workspaces[0]
            defaults.set(workspaces[0].id.uuidString, forKey: Self.activeWorkspaceIdKey)
        }
        persist(workspaces)
    }

    // MARK: - Private

    private func persist(_ items: [Workspace]) {
        Self.persist(items: items, defaults: defaults)
    }

    private static func persist(items: [Workspace], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.workspacesKey)
    }

    private static func load(from defaults: UserDefaults) -> [Workspace] {
        guard let data = defaults.data(forKey: Self.workspacesKey),
              let items = try? JSONDecoder().decode([Workspace].self, from: data)
        else { return [] }
        return items
    }

    private static func migrateIfNeeded(defaults: UserDefaults) {
        guard defaults.data(forKey: "claudeProfiles") != nil,
              defaults.data(forKey: Self.workspacesKey) == nil else { return }
        struct LegacyProfile: Codable { let id: UUID; let name: String; let path: String }
        guard let data = defaults.data(forKey: "claudeProfiles"),
              let profiles = try? JSONDecoder().decode([LegacyProfile].self, from: data)
        else { return }
        let migrated = profiles.map {
            Workspace(id: $0.id, name: $0.name, harnessType: .claudeCode, rootDir: $0.path)
        }
        persist(items: migrated, defaults: defaults)
        defaults.removeObject(forKey: "claudeProfiles")
    }
}
