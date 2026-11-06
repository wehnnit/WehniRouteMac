import SwiftUI
import WehniRouteCore

struct SetupWizardView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var updates: UpdateManager

    @State private var step = 0
    @State private var portText = "20128"
    @State private var requireAPIKey = false
    @State private var includeSimulation = true
    @State private var isFinishing = false
    @State private var errorMessage: String?

    private let steps = [
        SetupStepInfo(title: "Welcome", detail: "Start here", symbol: "sparkles"),
        SetupStepInfo(title: "Gateway", detail: "Port and access", symbol: "network"),
        SetupStepInfo(title: "Provider", detail: "First model", symbol: "flask.fill"),
        SetupStepInfo(title: "Ready", detail: "Review and launch", symbol: "checkmark.circle.fill")
    ]

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                DividerLine()

                HStack(spacing: 0) {
                    setupRail

                    VStack(spacing: 0) {
                        ScrollView(.vertical, showsIndicators: false) {
                            stepContent
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 24)
                        }

                        DividerLine()
                        footer
                    }
                }
            }
        }
        .frame(minWidth: Theme.minWindowWidth, minHeight: Theme.minWindowHeight)
        .preferredColorScheme(.dark)
        .onAppear {
            portText = String(store.config.gatewayPort)
            requireAPIKey = store.config.requireAPIKey
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            WehniMark(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("WehniRoute")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("FIRST RUN · LOCAL CONTROL PLANE")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Theme.faint)
            }

            Spacer()

            Text("Your data stays on this Mac.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)

            Pill(text: "v\(AppVersion.short)", tint: Theme.accent, icon: "sparkles")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var setupRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETUP")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, info in
                    Button {
                        guard index <= step else { return }
                        errorMessage = nil
                        withAnimation(.snappy(duration: 0.18)) {
                            step = index
                        }
                    } label: {
                        stepRow(index: index, info: info)
                    }
                    .buttonStyle(.plain)
                    .disabled(index > step)
                    .accessibilityLabel("\(info.title): \(info.detail)")
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.green)
                    Text("LOCAL ONLY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Theme.green)
                }

                Text("No account, cloud sync, or telemetry. Provider keys stay in the macOS Keychain.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)

                Text("~/Library/Application Support/WehniRoute")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.08))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)
        }
    }

    private func stepRow(index: Int, info: SetupStepInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(index == step ? Theme.accent : Color.white.opacity(0.045))
                    .frame(width: 25, height: 25)
                if index < step {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: 0x061014))
                } else {
                    Image(systemName: info.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(index == step ? Color(hex: 0x061014) : Theme.faint)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 11, weight: index == step ? .semibold : .medium))
                    .foregroundStyle(index == step ? Theme.text : (index < step ? Theme.muted : Theme.faint))
                Text(info.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(index == step ? Theme.accent.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(index == step ? Theme.accent.opacity(0.20) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            welcomeStep
        case 1:
            gatewayStep
        case 2:
            providerStep
        default:
            readyStep
        }
    }

    private var welcomeStep: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                stepEyebrow("01 · WELCOME")

                Text("Route with intent.")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.text, Color(hex: 0xBFE9E2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)

                Text("One local endpoint for the models you already trust. Every request gets an explainable decision and a trace you can inspect.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    setupFeature(
                        symbol: "network",
                        title: "One gateway",
                        detail: "OpenAI and Anthropic compatible. Bound to loopback."
                    )
                    setupFeature(
                        symbol: "eye.fill",
                        title: "Explainable",
                        detail: "Candidates, attempts, latency, and cost recorded."
                    )
                    setupFeature(
                        symbol: "lock.shield.fill",
                        title: "Local only",
                        detail: "No account, telemetry, or cloud sync."
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Creates ~/Library/Application Support/WehniRoute")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(spacing: 12) {
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AT A GLANCE")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Theme.faint)

                        setupFact(symbol: "folder.fill", label: "Data folder", value: "Application Support")
                        setupFact(symbol: "network", label: "Gateway", value: "127.0.0.1:\(validPort ?? 20128)")
                        setupFact(symbol: "flask.fill", label: "First provider", value: "Simulation · sim-echo")

                        DividerLine().opacity(0.7)

                        HStack(spacing: 7) {
                            Image(systemName: "clock")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text("About 2 minutes")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                    Text("Future app updates migrate the data folder automatically, so your traces and providers stay in place.")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.violet.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.violet.opacity(0.12), lineWidth: 1))
            }
            .frame(width: 268)
        }
    }

    private var gatewayStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                stepEyebrow("02 · GATEWAY")
                Text("Listen locally.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Choose the local port and access policy. The gateway only listens on 127.0.0.1.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            FormLabel(title: "Port", hint: "1024–65535. Default is 20128.")
                            Spacer()
                            FieldShell {
                                TextField("20128", text: $portText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 92)
                                    .onSubmit(advance)
                            }
                        }

                        DividerLine().opacity(0.7)

                        Toggle(isOn: $requireAPIKey) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Require the local API key")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                Text("Clients send the generated key as Bearer or x-api-key. You can change this later.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        .scaleEffect(0.9, anchor: .leading)

                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(validPort == nil ? Theme.amber : Theme.green)
                            Text(
                                validPort == nil
                                    ? "Enter a port between 1024 and 65535."
                                    : "Ready on http://127.0.0.1:\(validPort ?? 20128)/v1"
                            )
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(validPort == nil ? Theme.amber : Theme.faint)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("ENDPOINT PREVIEW")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundStyle(Theme.faint)
                                Spacer()
                                Circle()
                                    .fill(validPort == nil ? Theme.amber : Theme.green)
                                    .frame(width: 5, height: 5)
                            }

                            Text(verbatim: "http://127.0.0.1:\(validPort ?? 20128)/v1")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)

                            DividerLine().opacity(0.7)

                            endpointLine(method: "POST", path: "/v1/chat/completions")
                            endpointLine(method: "POST", path: "/v1/messages")
                            endpointLine(method: "GET", path: "/v1/models")
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("The socket is loopback-only. Other devices on your network cannot reach this port.")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.accent.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.accent.opacity(0.12), lineWidth: 1))
                }
                .frame(width: 276)
            }
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                stepEyebrow("03 · PROVIDER")
                Text("Start with a model.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("The offline Simulation provider makes the gateway usable immediately. Real providers can be connected after setup.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $includeSimulation) {
                            HStack(spacing: 12) {
                                Image(systemName: "flask.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.amber)
                                    .frame(width: 30, height: 30)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber.opacity(0.12)))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Add the Simulation provider")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    Text("Offline, no key, no network. Includes sim-echo so you can test the gateway immediately.")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.faint)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        .scaleEffect(0.9, anchor: .leading)

                        DividerLine().opacity(0.7)

                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.accent)
                            Text("Anthropic, OpenAI, Groq, Google, OpenRouter, Ollama, and custom OpenAI-compatible endpoints are available from Providers after setup.")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 11) {
                            Text("FIRST ROUTE")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(Theme.faint)

                            if includeSimulation {
                                HStack(spacing: 10) {
                                    ProviderGlyph(kind: .simulation, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Simulation")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Theme.text)
                                        Text("sim-echo · no key")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Theme.faint)
                                    }
                                    Spacer()
                                    Pill(text: "OFFLINE", tint: Theme.green)
                                }
                            } else {
                                Text("No provider will be added. You can connect one after setup from the Providers screen.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            DividerLine().opacity(0.7)

                            VStack(alignment: .leading, spacing: 9) {
                                setupFact(symbol: "1.circle.fill", label: "Model registered", value: "sim-echo")
                                setupFact(symbol: "2.circle.fill", label: "Policy scores", value: "Auto · balanced")
                                setupFact(symbol: "3.circle.fill", label: "Trace recorded", value: "Every request")
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                        Text("Real provider keys never appear in the config file. They are stored in the macOS Keychain.")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.violet.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.violet.opacity(0.12), lineWidth: 1))
                }
                .frame(width: 276)
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                stepEyebrow("04 · READY")
                Text("Ready to route.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Review the generated setup. Finishing creates the data folder, writes the local key, and starts the gateway.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SettingsLikeHeading(symbol: "checkmark.seal.fill", title: "Setup summary")
                            Spacer()
                            Pill(text: "READY", tint: Theme.green)
                        }

                        DividerLine().opacity(0.7)

                        KeyValueRow(label: "Data folder", value: "~/Library/Application Support/WehniRoute", mono: true)
                        KeyValueRow(label: "Gateway", value: "http://127.0.0.1:\(validPort ?? 20128)/v1", mono: true)
                        KeyValueRow(label: "API key", value: requireAPIKey ? "Required" : "Open for local clients", mono: false)
                        KeyValueRow(label: "Provider", value: includeSimulation ? "Simulation · sim-echo" : "None yet", mono: false)
                    }
                }
                .frame(maxWidth: .infinity)

                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("ON FINISH")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(Theme.faint)

                        finishRow(symbol: "folder.badge.plus", text: "Create or migrate the latest support folder")
                        finishRow(symbol: "key.fill", text: "Generate a local gateway key with mode 0600")
                        finishRow(symbol: "network", text: "Start listening on \(validPort ?? 20128)")
                        finishRow(symbol: "eye.fill", text: "Open the router with tracing enabled")

                        DividerLine().opacity(0.7)

                        Text("You can change the port, access policy, and providers later in Settings. After setup, open Harnesses to launch Claude Code, OpenCode, Codex, Hermes, Pi, or DeepSeek through WehniRoute.")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 300)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("STEP \(step + 1) OF \(steps.count)")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.faint)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.rose)
                    .lineLimit(1)
            }

            Spacer()

            if step > 0 {
                Button("Back") {
                    errorMessage = nil
                    withAnimation(.snappy(duration: 0.18)) {
                        step -= 1
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(isFinishing)
            }

            if step < steps.count - 1 {
                Button("Continue") {
                    advance()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    finish()
                } label: {
                    if isFinishing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(hex: 0x061014))
                    } else {
                        Label("Set up WehniRoute", systemImage: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(isFinishing || validPort == nil)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var validPort: Int? {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)), (1_024...65_535).contains(port) else {
            return nil
        }
        return port
    }

    private func stepEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Theme.accent)
    }

    private func setupFeature(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private func setupFact(symbol: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                Text(value)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func endpointLine(method: String, path: String) -> some View {
        HStack(spacing: 7) {
            Text(method)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, alignment: .leading)
            Text(path)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func finishRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 13)
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func advance() {
        guard step != 1 || validPort != nil else {
            errorMessage = "Enter a port between 1024 and 65535."
            return
        }
        errorMessage = nil
        withAnimation(.snappy(duration: 0.18)) {
            step += 1
        }
    }

    private func finish() {
        guard let port = validPort else {
            errorMessage = "Enter a port between 1024 and 65535."
            return
        }
        errorMessage = nil
        isFinishing = true
        do {
            try store.completeSetup(
                port: port,
                requireAPIKey: requireAPIKey,
                includeSimulation: includeSimulation
            )
            updates.startAutomaticChecks()
        } catch {
            errorMessage = error.localizedDescription
            isFinishing = false
        }
    }
}

private struct SetupStepInfo {
    let title: String
    let detail: String
    let symbol: String
}

private struct SettingsLikeHeading: View {
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
