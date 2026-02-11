import SwiftUI

struct ContentView: View {
    @Environment(SidebarViewModel.self) var sidebarVM
    @Environment(SettingsViewModel.self) var settingsVM
    @State private var isShowingSettings: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(onOpenSettings: {
                isShowingSettings = true
            })
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } detail: {
            if let conversationID = sidebarVM.selectedConversationID {
                ChatView(conversationID: conversationID)
                    .environment(settingsVM)
            } else {
                EmptyStateView()
            }
        }
        .background(Color.dsBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environment(settingsVM)
                #if os(macOS)
                .frame(width: 500, height: 500)
                #endif
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.dsIndigo.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.dsIndigo)
            }

            VStack(spacing: 8) {
                Text("No Research Selected")
                    .font(.dsTitle2)
                    .foregroundStyle(.dsNavy)

                Text("Select an existing conversation or start a new one.")
                    .font(.dsBody)
                    .foregroundStyle(.dsSlate)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground)
    }
}
