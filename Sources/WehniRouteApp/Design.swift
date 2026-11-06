import SwiftUI
import WehniRouteCore

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    static let backgroundTop = Color(hex: 0x060A12)
    static let backgroundBottom = Color(hex: 0x0A1120)
    static let surface = Color.white.opacity(0.045)
    static let surfaceStrong = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.14)
    static let text = Color(hex: 0xEAF2FF)
    static let muted = Color(hex: 0x8FA0BA)
    static let faint = Color(hex: 0x5E6E88)
    static let accent = Color(hex: 0x5EEAD4)
    static let violet = Color(hex: 0xA78BFA)
    static let blue = Color(hex: 0x60A5FA)
    static let green = Color(hex: 0x34D399)
    static let amber = Color(hex: 0xFBBF24)
    static let rose = Color(hex: 0xFB7185)

    static let cardRadius: CGFloat = 18
    static let pagePadding: CGFloat = 24
    static let minWindowWidth: CGFloat = 1120
    static let minWindowHeight: CGFloat = 720
    static let topBarHeight: CGFloat = 56
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom, Color(hex: 0x07131A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.13), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 780
            )
            RadialGradient(
                colors: [Theme.violet.opacity(0.11), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 720
            )
            GridTexture()
                .stroke(Color.white.opacity(0.028), lineWidth: 0.7)
        }
        .ignoresSafeArea()
    }
}

private struct GridTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 36
        var x: CGFloat = 0
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += step
        }
        var y: CGFloat = 0
        while y < rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        return path
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat
    var content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 12)
    }
}

struct WehniMark: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x0F2A2E), Color(hex: 0x12162B)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                        .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
                )
            RoutingGlyph()
                .padding(size * 0.19)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.22), radius: 12, x: 0, y: 5)
    }
}

private struct RoutingGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.22, y: height * 0.22))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.50))
                    path.addLine(to: CGPoint(x: width * 0.78, y: height * 0.22))
                    path.move(to: CGPoint(x: width * 0.50, y: height * 0.50))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.82))
                }
                .stroke(
                    LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: max(1.4, width * 0.055), lineCap: .round, lineJoin: .round)
                )

                node(x: 0.22, y: 0.22, width: width, height: height, tint: Theme.accent, size: 0.15)
                node(x: 0.78, y: 0.22, width: width, height: height, tint: Theme.violet, size: 0.15)
                node(x: 0.50, y: 0.50, width: width, height: height, tint: .white, size: 0.20)
                node(x: 0.50, y: 0.82, width: width, height: height, tint: Theme.accent, size: 0.15)
            }
        }
    }

    private func node(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, tint: Color, size: CGFloat) -> some View {
        Circle()
            .fill(tint)
            .frame(width: width * size, height: width * size)
            .position(x: width * x, y: height * y)
            .shadow(color: tint.opacity(0.8), radius: width * 0.05)
    }
}

struct ScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.7)
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                Spacer(minLength: 12)
                trailing
            }
            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct Pill: View {
    var text: String
    var tint: Color = Theme.accent
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 0.8))
    }
}

struct StatusDot: View {
    var state: HealthState
    var size: CGFloat = 7

    var color: Color {
        switch state {
        case .healthy: return Theme.green
        case .degraded: return Theme.amber
        case .down: return Theme.rose
        case .unknown: return Theme.faint
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: 4)
    }
}

struct ProviderGlyph: View {
    let kind: ProviderKind
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(hex: kind.accentHex).opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Color(hex: kind.accentHex).opacity(0.25), lineWidth: 1)
            )
            .overlay(
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundStyle(Color(hex: kind.accentHex))
            )
            .frame(width: size, height: size)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    var values: [Double] = []

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Theme.faint)
                    Spacer()
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Sparkline(values: values, tint: tint)
                    .frame(height: 22)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maxValue = max(values.max() ?? 1, 1)
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * step,
                    y: size.height - (CGFloat(value / maxValue) * (size.height - 3)) - 1
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.35), tint]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

struct ScoreBar: View {
    var value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, proxy.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: 0x061014))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
            .shadow(color: tint.opacity(0.28), radius: 10, x: 0, y: 5)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.045)))
            .overlay(Circle().stroke(Theme.stroke, lineWidth: 0.8))
    }
}

struct HoverLift: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.006 : 1)
            .brightness(hovering ? 0.02 : 0)
            .animation(.snappy(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift() -> some View {
        modifier(HoverLift())
    }

    func cardBorder(_ color: Color = Theme.stroke) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(color, lineWidth: 1)
        )
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.08)).frame(width: 56, height: 56)
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
    }
}

struct ToastBanner: View {
    let toast: Toast

    var tint: Color {
        switch toast.kind {
        case .info: return Theme.blue
        case .success: return Theme.green
        case .error: return Theme.rose
        }
    }

    var symbol: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(toast.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color(hex: 0x0B1420).opacity(0.96))
        )
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
}

struct KeyValueRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
    }
}
