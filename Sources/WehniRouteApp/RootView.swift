import Foundation
import SwiftUI
import WehniRouteCore

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Sidebar()
                ZStack {
                    AppBackground()
                    VStack(spacing: 0) {
                        TopBar()
                        DividerLine().opacity(0.55)
                        if store.section == .traces {
                            sectionContent
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(.horizontal, Theme.pagePadding)
                                .padding(.bottom, 16)
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView(.vertical, showsIndicators: false) {
                                    sectionContent
                                        .id("section-top")
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                        .padding(.horizontal, Theme.pagePadding)
                                        .padding(.bottom, 24)
                                }
                                .onChange(of: store.section) { _, _ in
                                    proxy.scrollTo("section-top", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DividerLine().opacity(0.7)
            AppStatusStrip()
        }
        .frame(minWidth: Theme.minWindowWidth, minHeight: Theme.minWindowHeight)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let toast = store.toastMessage {
                ToastBanner(toast: toast)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .sheet(isPresented: $store.showAddProvider) {
            AddProviderSheet()
        }
        .sheet(isPresented: $store.showAddModel) {
            AddModelSheet()
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch store.section {
        case .overview:
            OverviewView()
        case .providers:
            ProvidersView()
        case .models:
            ModelsView()
        case .routing:
            RoutingView()
        case .harnesses:
            HarnessesView()
        case .traces:
            TracesView()
        case .settings:
            SettingsView()
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                WehniMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("WehniRoute")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("model router")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 36)
            .padding(.bottom, 20)

            Text("WORKSPACE")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 3) {
                ForEach(AppSection.allCases) { section in
                    SidebarButton(section: section)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 18)

            GatewayMiniCard()
                .padding(.horizontal, 12)

            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.green)
                    .frame(width: 4, height: 4)
                Text("LOCAL ONLY")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(Theme.faint)
                Spacer()
                Text("v\(AppVersion.short)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 19)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(width: 228)
        .background(Color(hex: 0x060B14).opacity(0.86))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)
        }
    }
}

private struct SidebarButton: View {
    @EnvironmentObject private var store: AppStore
    let section: AppSection
    @State private var hovering = false

    private var selected: Bool {
        store.section == section
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.20)) {
                store.section = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 17)
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
                Text(section.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
                Spacer()
                if selected {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 4, height: 4)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        selected
                            ? Theme.accent.opacity(0.09)
                            : (hovering ? Color.white.opacity(0.035) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Theme.accent.opacity(0.18) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct GatewayMiniCard: View {
    @EnvironmentObject private var store: AppStore

    private var statusColor: Color {
        if case .running = store.gatewayStatus { return Theme.green }
        if case .failed = store.gatewayStatus { return Theme.rose }
        return Theme.faint
    }

    private var statusLabel: String {
        switch store.gatewayStatus {
        case .running: return "ONLINE"
        case .stopped: return "OFFLINE"
        case .failed: return "ERROR"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: statusColor.opacity(0.7), radius: 3)
                Text("GATEWAY")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            Text(verbatim: "127.0.0.1:\(store.config.gatewayPort)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)

            HStack(spacing: 5) {
                Button("Copy") { store.copyGatewayURL() }
                    .buttonStyle(GhostButtonStyle())
                if store.gatewayStatus.isRunning {
                    Button("Stop") { store.stopGateway() }
                        .buttonStyle(GhostButtonStyle())
                } else {
                    Button("Start") { store.startGateway() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

private struct TopBar: View {
    @EnvironmentObject private var store: AppStore

    private var gatewayTint: Color {
        if case .running = store.gatewayStatus { return Theme.green }
        if case .failed = store.gatewayStatus { return Theme.rose }
        return Theme.faint
    }

    private var gatewayLabel: String {
        switch store.gatewayStatus {
        case .running: return "online"
        case .stopped: return "offline"
        case .failed: return "error"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("WEHNI / \(store.section.title.uppercased())")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.faint)
                Text(store.section.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                TextField("Search routes", text: $store.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text)
                if !store.search.isEmpty {
                    Button {
                        store.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 180, height: 27)
            .background(Capsule().fill(Color.black.opacity(0.18)))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.8))

            Button {
                store.copyGatewayURL()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(gatewayTint)
                        .frame(width: 5, height: 5)
                        .shadow(color: gatewayTint.opacity(0.8), radius: 3)
                    Text("Gateway \(gatewayLabel)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Text(verbatim: ":\(store.config.gatewayPort)")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(Capsule().fill(Color.white.opacity(0.035)))
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.8))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                store.showAddProvider = true
            } label: {
                Label("Connect", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.topBarHeight)
    }
}

private struct AppStatusStrip: View {
    @EnvironmentObject private var store: AppStore

    private var gatewayTint: Color {
        if case .running = store.gatewayStatus { return Theme.green }
        if case .failed = store.gatewayStatus { return Theme.rose }
        return Theme.faint
    }

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(gatewayTint)
                    .frame(width: 4, height: 4)
                    .shadow(color: gatewayTint.opacity(0.8), radius: 2)
                Text("LOCAL GATEWAY")
                Text(verbatim: "127.0.0.1:\(store.config.gatewayPort)")
            }

            Spacer(minLength: 10)

            Text("macOS \(macOSVersion)")
            Text("·")
            Text("Apache 2.0")
            Text("·")
            Text("v\(AppVersion.short) (\(AppVersion.build))")
            Text("·")
            Text("© 2026 wehnnit")
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(Theme.faint)
        .padding(.horizontal, 18)
        .frame(height: 26)
        .background(Color.black.opacity(0.16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gateway on port \(store.config.gatewayPort), macOS \(macOSVersion), Apache 2.0 license, version \(AppVersion.short) build \(AppVersion.build), copyright 2026 wehnnit")
    }
}
