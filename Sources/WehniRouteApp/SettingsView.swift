import SwiftUI
import WehniRouteCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var updates: UpdateManager
    @StateObject private var harnessLauncher = HarnessLauncher()
    @State private var portText = ""
    @State private var revealKey = false
    @State private var confirmClear = false

    private var maskedKey: String {
        "wrk_" + String(repeating: "•", count: 22)
    }

    private var gatewayTint: Color {
        if case .running = store.gatewayStatus { return Theme.green }
        if case .failed = store.gatewayStatus { return Theme.rose }
        return Theme.amber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                eyebrow: "Controls",
                title: "Settings",
                subtitle: "The gateway, credentials, and local data all live on this Mac. There is no account, cloud sync, or telemetry."
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                gatewayCard
                keyCard
                dataCard
                aboutCard
            }

            harnessesCard
                .padding(.top, 12)

            updatesCard
                .padding(.top, 12)
        }
        .onAppear {
            portText = String(store.config.gatewayPort)
            Task { await harnessLauncher.refresh() }
        }
        .confirmationDialog(
            "Clear all decision records?",
            isPresented: $confirmClear
        ) {
            Button("Clear traces", role: .destructive) {
                store.clearTraces()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the local trace log. Provider configuration and Keychain entries are unaffected.")
        }
    }

    private var gatewayCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    SettingsHeading(symbol: "network", title: "Gateway")
                    Spacer()
                    Pill(text: store.gatewayStatus.label.uppercased(), tint: gatewayTint)
                }

                KeyValueRow(label: "Bind address", value: "127.0.0.1", mono: true)
                KeyValueRow(label: "Endpoint", value: store.gatewayURL, mono: true)

                HStack(spacing: 8) {
                    Text("Port")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    FieldShell {
                        TextField("20128", text: $portText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .frame(width: 58)
                            .onSubmit(applyPort)
                    }
                    Button("Apply", action: applyPort)
                        .buttonStyle(GhostButtonStyle())
                }

                HStack(spacing: 7) {
                    Button("Restart") { store.restartGateway() }
                        .buttonStyle(GhostButtonStyle())
                    Button("Copy URL") { store.copyGatewayURL() }
                        .buttonStyle(GhostButtonStyle())
                    if store.gatewayStatus.isRunning {
                        Button("Stop") { store.stopGateway() }
                            .buttonStyle(GhostButtonStyle())
                    } else {
                        Button("Start") { store.startGateway() }
                            .buttonStyle(GhostButtonStyle())
                    }
                }

                Text("Loopback only. Other devices on your network cannot reach this port.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private var keyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SettingsHeading(symbol: "key.horizontal.fill", title: "Access key")

                Toggle(isOn: store.binding(\.requireAPIKey)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Require API key")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("Reject gateway calls without the local key.")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .scaleEffect(0.88, anchor: .leading)

                FieldShell {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                        Text(revealKey ? store.gatewayAPIKey : maskedKey)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.faint)
                        }
                        .buttonStyle(.plain)
                        Button {
                            store.copyGatewayKey()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.faint)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 7) {
                    Button("Copy key") { store.copyGatewayKey() }
                        .buttonStyle(GhostButtonStyle())
                    Button("Rotate") { store.regenerateGatewayKey() }
                        .buttonStyle(GhostButtonStyle())
                    Spacer()
                    Text(store.config.requireAPIKey ? "ENFORCED" : "OPEN")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.config.requireAPIKey ? Theme.green : Theme.amber)
                }

                Text("Local key · mode 0600 · send as Bearer or x-api-key.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private var dataCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SettingsHeading(symbol: "externaldrive.fill", title: "Local data")

                KeyValueRow(label: "Config", value: "native-config.json", mono: true)
                KeyValueRow(label: "Traces", value: "\(store.traces.count) records", mono: true)
                KeyValueRow(label: "Provider keys", value: "macOS Keychain", mono: true)

                HStack(spacing: 7) {
                    Button("Reveal folder") { store.revealHome() }
                        .buttonStyle(GhostButtonStyle())
                    Button("Export config") { store.exportConfig() }
                        .buttonStyle(GhostButtonStyle())
                }

                DividerLine().opacity(0.7)

                HStack(spacing: 7) {
                    Button {
                        confirmClear = true
                    } label: {
                        Text("Clear traces")
                            .foregroundStyle(Theme.rose)
                    }
                    .buttonStyle(GhostButtonStyle())

                    Button("Reset circuit state") { store.resetHealth() }
                        .buttonStyle(GhostButtonStyle())
                }

                Text("~/Library/Application Support/WehniRoute")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    WehniMark(size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("WehniRoute")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text("Native macOS router · \(AppVersion.short)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                    Spacer()
                }

                Text("A local OpenAI- and Anthropic-compatible gateway with deterministic, explainable routing across the providers you connect.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                DividerLine().opacity(0.7)

                AboutFeature(symbol: "lock.shield.fill", text: "Provider keys in Keychain, never in config")
                AboutFeature(symbol: "eye.fill", text: "Every route leaves a decision record")
                AboutFeature(symbol: "wifi.slash", text: "No telemetry, accounts, or cloud sync")

                HStack(spacing: 5) {
                    Pill(text: "LOCAL ONLY", tint: Theme.green)
                    Pill(text: "SWIFTUI", tint: Theme.violet)
                    Spacer()
                    Button("Open Harnesses") { store.section = .harnesses }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private var harnessesCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        SettingsHeading(symbol: "terminal.fill", title: "Harness commands")
                        Pill(text: "6 AGENTS", tint: Theme.accent)
                    }

                    Text("Install short commands such as claude-wehniroute and codex-wehniroute in ~/.local/bin. Each one opens the real CLI with this gateway's generated config.")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(HarnessKind.allCases.map(\.launcherCommand).joined(separator: "  ·  "))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    Button("Open Harnesses") { store.section = .harnesses }
                        .buttonStyle(GhostButtonStyle())
                    Button(harnessLauncher.installedCommands.isEmpty ? "Install commands" : "Reinstall commands") {
                        harnessLauncher.installCommands(store: store)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(harnessLauncher.detected.isEmpty)
                    Text("Needs at least one installed harness CLI.")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.faint)
                }
                .frame(width: 180, alignment: .trailing)
            }
        }
    }

    private var updatesCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        SettingsHeading(symbol: "arrow.triangle.2.circlepath", title: "Updates")
                        Pill(text: "v\(AppVersion.short)", tint: Theme.accent)
                    }

                    Toggle(isOn: $updates.autoUpdateEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Install updates automatically")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Text("Checks GitHub Releases on launch and daily. Downloads are checksum- and signature-verified before installing in place.")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .scaleEffect(0.9, anchor: .leading)

                    Text(updates.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(updates.state.isBusy ? Theme.amber : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 7) {
                        if updates.availableRelease != nil {
                            Button("Install update") {
                                Task { await updates.installAvailableUpdate() }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(updates.state.isBusy)
                        }

                        Button("Check now") {
                            Task { await updates.checkForUpdates(userInitiated: true) }
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(updates.state.isBusy)
                    }

                    if let release = updates.availableRelease {
                        Button("Release notes") {
                            NSWorkspace.shared.open(release.pageURL)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }

                    Text("Updates replace this app bundle wherever it lives, preserve the local data folder, and remove the previous bundle after a successful install.")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 330, alignment: .trailing)
            }
        }
    }

    private func applyPort() {
        if let port = Int(portText.trimmingCharacters(in: .whitespaces)) {
            store.updatePort(port)
            portText = String(store.config.gatewayPort)
        } else {
            store.showToast("Enter a numeric port", kind: .error)
        }
    }
}

private struct SettingsHeading: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
    }
}

private struct AboutFeature: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.9))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(Theme.muted)
        }
    }
}
