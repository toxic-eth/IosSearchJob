import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Темна"
        case .light: return "Світла"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

func resolvedTheme(from rawValue: String) -> AppTheme {
    AppTheme(rawValue: rawValue) ?? .dark
}

struct AppPalette {
    let bgStart: Color
    let bgMid: Color
    let bgEnd: Color
    let textPrimary: Color
    let textSecondary: Color
    let strokeSoft: Color
    let strokeStrong: Color
    let accent: Color
    let accentSoft: Color

    static func forTheme(_ theme: AppTheme) -> AppPalette {
        switch theme {
        case .dark:
            return AppPalette(
                bgStart: Color(red: 0.04, green: 0.03, blue: 0.09),
                bgMid: Color(red: 0.13, green: 0.08, blue: 0.24),
                bgEnd: Color(red: 0.02, green: 0.02, blue: 0.05),
                textPrimary: Color(red: 0.95, green: 0.96, blue: 0.99),
                textSecondary: Color(red: 0.70, green: 0.73, blue: 0.83),
                strokeSoft: Color.white.opacity(0.18),
                strokeStrong: Color.white.opacity(0.28),
                accent: Color(red: 0.78, green: 0.42, blue: 1.00),
                accentSoft: Color(red: 0.78, green: 0.42, blue: 1.00).opacity(0.22)
            )
        case .light:
            return AppPalette(
                bgStart: Color.white,
                bgMid: Color(red: 0.95, green: 0.96, blue: 0.99),
                bgEnd: Color(red: 0.89, green: 0.90, blue: 0.95),
                textPrimary: Color(red: 0.08, green: 0.08, blue: 0.11),
                textSecondary: Color(red: 0.33, green: 0.35, blue: 0.42),
                strokeSoft: Color.black.opacity(0.10),
                strokeStrong: Color.black.opacity(0.16),
                accent: Color(red: 0.70, green: 0.30, blue: 0.96),
                accentSoft: Color(red: 0.70, green: 0.30, blue: 0.96).opacity(0.16)
            )
        }
    }
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

enum AppRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let panel: CGFloat = 18
}

struct AppBackgroundView: View {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    var body: some View {
        let palette = AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
        LinearGradient(
            colors: [palette.bgStart, palette.bgMid, palette.bgEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    func body(content: Content) -> some View {
        let palette = AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
        content
            .padding(14)
            .background(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(palette.strokeSoft, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [palette.strokeStrong, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: resolvedTheme(from: appThemeRawValue) == .dark ? .black.opacity(0.25) : .black.opacity(0.1),
                radius: 14,
                y: 8
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

struct FrostedPanelModifier: ViewModifier {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    func body(content: Content) -> some View {
        let palette = AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
        content
            .padding(14)
            .background(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .stroke(palette.strokeSoft, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [palette.strokeStrong, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: resolvedTheme(from: appThemeRawValue) == .dark ? .black.opacity(0.34) : .black.opacity(0.12),
                radius: 16,
                y: 10
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
    }
}

struct FrostedButtonStyle: ButtonStyle {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    func makeBody(configuration: Configuration) -> some View {
        let palette = AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
        return configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(palette.strokeSoft, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [palette.strokeStrong, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AppSearchField: View {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue
    @Binding var text: String
    let placeholder: String

    var body: some View {
        let palette = AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: $text)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(palette.strokeSoft, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }
}

struct AppIconSquareButton<Content: View>: View {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue
    var size: CGFloat = 48
    var foreground: Color? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let palette = AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
        Button(action: action) {
            content()
                .foregroundStyle(foreground ?? palette.textPrimary)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control + 2, style: .continuous)
                        .stroke(palette.strokeSoft, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control + 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

enum AppPillTone {
    case neutral
    case info
    case warning
    case success
    case danger
    case accent

    var fg: Color {
        switch self {
        case .neutral: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .success: return .green
        case .danger: return .red
        case .accent: return .purple
        }
    }

    var bg: Color {
        switch self {
        case .neutral: return Color.gray.opacity(0.18)
        case .info: return Color.blue.opacity(0.18)
        case .warning: return Color.orange.opacity(0.18)
        case .success: return Color.green.opacity(0.18)
        case .danger: return Color.red.opacity(0.18)
        case .accent: return Color.purple.opacity(0.18)
        }
    }
}

struct AppStatusPill: View {
    let title: String
    let tone: AppPillTone

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tone.bg)
            .foregroundStyle(tone.fg)
            .clipShape(Capsule())
    }
}

struct AppStateBanner: View {
    let title: String
    let message: String
    let tone: AppPillTone
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tone.fg.opacity(0.22))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(tone.fg)
            }
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }

    func frostedPanel() -> some View {
        modifier(FrostedPanelModifier())
    }
}
