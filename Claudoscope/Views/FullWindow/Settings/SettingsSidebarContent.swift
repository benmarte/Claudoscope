import SwiftUI

// MARK: - Settings Sidebar Content

struct SettingsSidebarContent: View {
    let filterText: String
    @Binding var selectedSection: String?
    @Environment(SessionStore.self) private var sessionStore

    private var capabilities: HarnessCapabilities {
        sessionStore.activeWorkspace.capabilities
    }

    // All possible sections; capability-gated ones carry a flag name
    private var allSections: [(id: String, icon: String, label: String)] {
        var result: [(id: String, icon: String, label: String)] = []
        result.append(("appearance", "paintbrush", "Appearance"))
        if capabilities.hasLinting {
            result.append(("model", "cpu", "Model"))
            result.append(("permissions", "shield", "Permissions"))
        }
        result.append(("security", "lock.shield", "Security"))
        if capabilities.hasProfileData {
            result.append(("attribution", "signature", "Attribution"))
        }
        if capabilities.mcpConfigFileName != nil {
            result.append(("plugins", "puzzlepiece", "Plugins"))
        }
        result.append(("workspaces", "rectangle.stack.badge.person.crop", "Workspaces"))
        result.append(("account", "person.crop.circle", "Account"))
        result.append(("general", "gear", "General"))
        if capabilities.hasLinting {
            result.append(("environment", "terminal", "Environment"))
        }
        result.append(("pricing", "dollarsign.circle", "Pricing"))
        result.append(("updates", "arrow.triangle.2.circlepath", "Updates"))
        return result
    }

    private var filteredSections: [(id: String, icon: String, label: String)] {
        if filterText.isEmpty { return allSections }
        return allSections.filter { $0.label.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(filteredSections, id: \.id) { section in
                Button {
                    selectedSection = section.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon)
                            .font(Typography.body)
                            .frame(width: 16)
                            .foregroundStyle(selectedSection == section.id ? .white : .secondary)

                        Text(section.label)
                            .font(Typography.body)
                            .foregroundStyle(selectedSection == section.id ? .white : .primary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedSection == section.id ? Color.accentColor : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: sessionStore.pendingSettingsNavigation) { _, destination in
            guard let destination else { return }
            switch destination {
            case .workspaces:
                selectedSection = "workspaces"
            }
            sessionStore.pendingSettingsNavigation = nil
        }
    }
}
