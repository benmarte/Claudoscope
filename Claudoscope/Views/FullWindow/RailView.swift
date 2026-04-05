import SwiftUI

struct RailView: View {
    @Binding var selected: RailItem
    @Environment(SessionStore.self) private var store

    private var capabilities: HarnessCapabilities {
        store.activeWorkspace.capabilities
    }

    var body: some View {
        VStack(spacing: 4) {
            // Primary items — analytics and sessions always shown
            RailButton(item: .analytics, isSelected: selected == .analytics) { selected = .analytics }
            RailButton(item: .sessions,  isSelected: selected == .sessions)  { selected = .sessions  }
            RailButton(item: .tools,     isSelected: selected == .tools)     { selected = .tools     }
            if capabilities.hasPlans {
                RailButton(item: .plans, isSelected: selected == .plans) { selected = .plans }
            }
            if capabilities.hasTimeline {
                RailButton(item: .timeline, isSelected: selected == .timeline) { selected = .timeline }
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            // Config items
            RailButton(item: .hooks,    isSelected: selected == .hooks)    { selected = .hooks    }
            RailButton(item: .commands, isSelected: selected == .commands) { selected = .commands }
            RailButton(item: .mcps,     isSelected: selected == .mcps)     { selected = .mcps     }
            RailButton(item: .skills,   isSelected: selected == .skills)   { selected = .skills   }
            if capabilities.memoryFileName != nil {
                RailButton(item: .memory, isSelected: selected == .memory) { selected = .memory }
            }
            if capabilities.hasLinting {
                RailButton(item: .configHealth, isSelected: selected == .configHealth) { selected = .configHealth }
            }

            Spacer()

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            // Settings — always shown
            RailButton(item: .settings, isSelected: selected == .settings) {
                selected = .settings
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .frame(width: 68)
        .background(.bar)
    }
}

private struct RailButton: View {
    let item: RailItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(width: 28, height: 22)
                Text(item.label)
                    .font(Typography.caption)
                    .lineLimit(1)
            }
            .frame(width: 60, height: 40)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.label == "MCPs" ? "MCP Servers (Model Context Protocol)" : item.label)
    }
}
