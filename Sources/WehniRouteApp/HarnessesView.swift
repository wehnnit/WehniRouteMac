import AppKit
import SwiftUI

struct HarnessesView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var launcher = HarnessLauncher()
    @State private var guideHarness: HarnessKind?

    private let columns = [
        GridItem(.adaptive(minimum: 246, maximum: 340), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                eyebrow: "Launch pads",
                title: "Harnesses",
                subtitle: "Launch a terminal coding agent against WehniRoute's local inference. Each harness gets an isolated, generated configuration; your own CLI setup is left alone."
            ) {
                HStack(spacing: 8) {
                    Button {
                        launcher.installCommands(store: store)
                    } label: {
                        Label(
                            launcher.installedCommands.isEmpty ? "Install commands" : "Reinstall commands",
                            systemImage: "terminal"
                        )
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help("Install <agent>-wehniroute commands in ~/.local/bin")

                    HarnessHeaderStatus(launcher: launcher)
                }
            }

            gatewayBanner
                .padding(.bottom, 14)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(HarnessKind.allCases) { harness in
                    HarnessCard(harness: harness, launcher: launcher) {
                        guideHarness = harness
                    }
                }
            }

            footer
                .padding(.top, 16)
        }
        .onAppear {
            Task { await launcher.refresh() }
        }
        .sheet(item: $guideHarness) { harness in
            HarnessGuideSheet(harness: harness, launcher: launcher)
                .environmentObject(store)
        }
    }

    private var gatewayBanner: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(store.gatewayStatus.isRunning ? Theme.green.opacity(0.10) : Theme.amber.opacity(0.10))
                    Image(systemName: store.gatewayStatus.isRunning ? "bolt.horizontal.fill" : "bolt.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.gatewayStatus.isRunning ? Theme.green : Theme.amber)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.gatewayStatus.isRunning ? "WehniRoute is ready for a harness" : "Start the gateway before launching")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Launching reuses the local gateway at \(store.gatewayURL), so provider keys never move into the harness config.")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if !store.gatewayStatus.isRunning {
                    Button("Start gateway") {
                        store.startGateway()
                    }
                    .buttonStyle(GhostButtonStyle())
                } else {
                    Pill(text: "LOOPBACK ONLY", tint: Theme.green, icon: "lock.fill")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.faint)
            Text("Configs stay in Application Support · commands install to ~/.local/bin")
                .font(.system(size: 9))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("Provider secrets stay in WehniRoute")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.faint)
        }
    }
}

private struct HarnessHeaderStatus: View {
    @ObservedObject var launcher: HarnessLauncher

    var body: some View {
        HStack(spacing: 8) {
            Pill(text: "\(HarnessKind.allCases.count) LAUNCHERS", tint: Theme.accent)
            Button {
                Task { await launcher.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(IconButtonStyle())
            .disabled(launcher.refreshing)
            .help("Refresh installed harnesses")
        }
    }
}

private struct HarnessCard: View {
    @EnvironmentObject private var store: AppStore
    let harness: HarnessKind
    @ObservedObject var launcher: HarnessLauncher
    let onGuide: () -> Void
    @State private var hovering = false

    private var installed: Bool {
        launcher.isInstalled(harness)
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(harness.accent.opacity(0.12))
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(harness.accent.opacity(0.22), lineWidth: 1)
                        Image(systemName: harness.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(harness.accent)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(harness.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(harness.tagline)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Circle()
                        .fill(installed ? Theme.green : Theme.amber)
                        .frame(width: 5, height: 5)
                        .shadow(color: (installed ? Theme.green : Theme.amber).opacity(0.75), radius: 3)
                        .padding(.top, 5)
                }

                HStack(spacing: 5) {
                    Pill(text: harness.protocolLabel, tint: harness.accent)
                    if harness == .codex {
                        Pill(text: "CONFIG", tint: Theme.violet)
                    }
                    Spacer(minLength: 0)
                    Text(installed ? "DETECTED" : "INSTALL")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(installed ? Theme.green : Theme.amber)
                }

                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                    Text(harness.command)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    if !installed {
                        Text("not in PATH")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.faint)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.18)))

                if !installed {
                    Text(harness.installCommand)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack(spacing: 6) {
                    Button {
                        launcher.launch(harness, store: store)
                    } label: {
                        Label("Launch", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: harness.accent))
                    .disabled(!installed)
                    .opacity(installed ? 1 : 0.42)

                    Spacer(minLength: 0)

                    Button {
                        launcher.copyLaunchCommand(harness, store: store)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Copy launch command")

                    Button(action: onGuide) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Setup details")
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(hovering ? harness.accent.opacity(0.34) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct HarnessGuideSheet: View {
    let harness: HarnessKind
    @ObservedObject var launcher: HarnessLauncher
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(harness.accent.opacity(0.13))
                    Image(systemName: harness.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(harness.accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(harness.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("\(harness.protocolLabel) · \(harness.command)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(harness.setupNote)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    guideSection("01 · INSTALL", note: "Run this once in Terminal if the harness is not detected.") {
                        commandRow(harness.installCommand)
                    }

                    guideSection("02 · WEHNIROUTE CONFIG", note: "WehniRoute generates and owns this configuration at launch.") {
                        VStack(alignment: .leading, spacing: 6) {
                            KeyValueRow(label: "Gateway", value: store.gatewayURL, mono: true)
                            KeyValueRow(label: "API key", value: "Local gateway key", mono: false)
                            Text(launcher.scriptPath(for: harness))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }

                    guideSection("03 · LAUNCH", note: "Install commands to run this from any Terminal window, or use the generated launcher path below.") {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text(verbatim: launcher.terminalCommand(for: harness))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.20)))
                        if !harness.launchArguments.isEmpty {
                            Text("Default arguments: \(harness.launchArguments.joined(separator: " "))")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            DividerLine()

            HStack(spacing: 8) {
                Button("Open docs") {
                    NSWorkspace.shared.open(harness.docsURL)
                }
                .buttonStyle(GhostButtonStyle())

                Spacer()

                Button("Copy launch command") {
                    launcher.copyLaunchCommand(harness, store: store)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(!launcher.isInstalled(harness))

                Button("Launch in Terminal") {
                    launcher.launch(harness, store: store)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(tint: harness.accent))
                .disabled(!launcher.isInstalled(harness))
            }
        }
        .padding(22)
        .frame(width: 620, height: 570)
        .background(Theme.backgroundTop)
        .preferredColorScheme(.dark)
    }

    private var launchArguments: String {
        harness.launchArguments.joined(separator: " ")
    }

    private func guideSection<Content: View>(
        _ title: String,
        note: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.faint)
            Text(note)
                .font(.system(size: 9))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private func commandRow(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                store.showToast("Command copied", kind: .success)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .buttonStyle(.plain)
            .help("Copy command")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.20)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 0.8))
    }
}
