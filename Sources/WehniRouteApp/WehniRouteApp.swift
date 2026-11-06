import SwiftUI

@main
struct WehniRouteApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var updates = UpdateManager()

    var body: some Scene {
        WindowGroup("WehniRoute") {
            Group {
                if store.needsSetup {
                    SetupWizardView()
                } else {
                    RootView()
                }
            }
            .environmentObject(store)
            .environmentObject(updates)
            .task {
                if !store.needsSetup {
                    updates.startAutomaticChecks()
                }
            }
        }
        .defaultSize(width: 1280, height: 830)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.checkForUpdates(userInitiated: true) }
                }
            }

            CommandMenu("Gateway") {
                Button("Copy Gateway URL") {
                    store.copyGatewayURL()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Restart Gateway") {
                    store.restartGateway()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Connect Provider…") {
                    store.showAddProvider = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Navigate") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        store.section = section
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                }
            }
        }
    }
}
