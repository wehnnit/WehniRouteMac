import SwiftUI
import WehniRouteCore

struct FormLabel: View {
    let title: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(Theme.muted)
            if let hint {
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

struct FieldShell<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.24))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

struct AddProviderSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ProviderKind = .anthropic
    @State private var apiKey = ""
    @State private var baseURL = ProviderKind.anthropic.defaultBaseURL
    @State private var displayName = ""
    @State private var showKey = false

    private var canAdd: Bool {
        if kind == .custom {
            return !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if kind.requiresKey {
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            DividerLine()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    presetSection
                    detailsSection
                    securityNote
                }
                .padding(24)
            }
            DividerLine()
            footer
        }
        .frame(width: 680, height: 650)
        .background(Theme.backgroundTop)
        .overlay(
            LinearGradient(
                colors: [Theme.accent.opacity(0.05), .clear, Theme.violet.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        )
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW CONNECTION")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Text("Connect a provider")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Choose a preset, then add the credentials. WehniRoute validates the connection before routing to it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(24)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            FormLabel(title: "Provider", hint: "Presets set the base URL, API format, and starter model.")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(ProviderKind.addable) { preset in
                    Button {
                        kind = preset
                        baseURL = preset.defaultBaseURL
                        if !preset.requiresKey { apiKey = "" }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: preset.accentHex))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.displayName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text(preset.tagline)
                                    .font(.system(size: 8))
                                    .foregroundStyle(Theme.faint)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(kind == preset ? Color(hex: preset.accentHex).opacity(0.12) : Color.white.opacity(0.025))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    kind == preset ? Color(hex: preset.accentHex).opacity(0.45) : Theme.stroke,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            FormLabel(title: "Credentials")

            if kind.requiresKey {
                VStack(alignment: .leading, spacing: 5) {
                    Text("API KEY")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.faint)
                    FieldShell {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.faint)
                            if showKey {
                                TextField("sk-…", text: $apiKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                            } else {
                                SecureField("sk-…", text: $apiKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                            }
                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.faint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Theme.green)
                    Text(kind == .simulation
                         ? "The simulation provider runs entirely offline. No key or network access is needed."
                         : "Ollama runs on this Mac. No API key is needed.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.green.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.green.opacity(0.14), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("BASE URL")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.faint)
                FieldShell {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                        TextField(kind.defaultBaseURL, text: $baseURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.text)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("DISPLAY NAME (OPTIONAL)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.faint)
                FieldShell {
                    TextField(kind.displayName, text: $displayName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            Text("Keys are stored in the macOS Keychain under com.wehnnit.WehniRoute. They never enter the JSON config, the gateway response, or application logs.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.12), lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("The connection is tested immediately.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(GhostButtonStyle())
            Button {
                add()
            } label: {
                Label("Add & test", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdd)
            .opacity(canAdd ? 1 : 0.45)
        }
        .padding(18)
    }

    private func add() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let provider = store.addProvider(
            kind: kind,
            apiKey: key,
            baseURL: url.isEmpty ? nil : url,
            name: name.isEmpty ? nil : name
        ) else {
            return
        }
        dismiss()
        Task {
            await store.testProvider(provider)
        }
    }
}

struct AddModelSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var providerID = ""
    @State private var modelID = ""
    @State private var displayName = ""
    @State private var contextWindow = "128000"
    @State private var inputPrice = ""
    @State private var outputPrice = ""
    @State private var isFree = false

    private var canAdd: Bool {
        !providerID.isEmpty && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MODEL CATALOG")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text("Add a model")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Configure the exact model IDs that this router may use.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(24)

            DividerLine()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if store.config.providers.isEmpty {
                        Text("Connect a provider before adding models.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.amber)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            FormLabel(title: "Provider")
                            Picker("Provider", selection: $providerID) {
                                ForEach(store.config.providers) { provider in
                                    Text(provider.name).tag(provider.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        formField("MODEL ID", placeholder: "claude-sonnet-4-5", text: $modelID, mono: true)
                        formField("DISPLAY NAME", placeholder: "Claude Sonnet", text: $displayName)
                        formField("CONTEXT WINDOW", placeholder: "128000", text: $contextWindow, mono: true)

                        HStack(spacing: 12) {
                            formField("INPUT $ / 1M", placeholder: "3.00", text: $inputPrice, mono: true)
                            formField("OUTPUT $ / 1M", placeholder: "15.00", text: $outputPrice, mono: true)
                        }

                        Toggle(isOn: $isFree) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Free tier model")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                Text("Free models score higher in cost-aware routing.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                    }
                }
                .padding(24)
            }

            DividerLine()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Button {
                    add()
                } label: {
                    Label("Add model", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.45)
            }
            .padding(18)
        }
        .frame(width: 520, height: 610)
        .background(Theme.backgroundTop)
        .preferredColorScheme(.dark)
        .onAppear {
            if providerID.isEmpty {
                providerID = store.config.providers.first?.id ?? ""
            }
        }
    }

    private func formField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        mono: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FormLabel(title: label)
            FieldShell {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: mono ? .monospaced : .default))
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private func add() {
        let context = Int(contextWindow.trimmingCharacters(in: .whitespaces)) ?? 128_000
        let input = Double(inputPrice.trimmingCharacters(in: .whitespaces))
        let output = Double(outputPrice.trimmingCharacters(in: .whitespaces))
        store.addModel(
            providerID: providerID,
            modelID: modelID,
            displayName: displayName,
            contextWindow: max(1_000, context),
            inputPrice: input,
            outputPrice: output,
            isFree: isFree
        )
        dismiss()
    }
}
