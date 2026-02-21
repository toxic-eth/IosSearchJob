import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark:
            return "Темна"
        case .light:
            return "Світла"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

func resolvedTheme(from rawValue: String) -> AppTheme {
    AppTheme(rawValue: rawValue) ?? .dark
}

struct AppBackgroundView: View {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    var body: some View {
        let theme = resolvedTheme(from: appThemeRawValue)

        LinearGradient(colors: backgroundColors(for: theme), startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
    }

    private func backgroundColors(for theme: AppTheme) -> [Color] {
        switch theme {
        case .dark:
            return [Color(red: 0.04, green: 0.03, blue: 0.12), Color(red: 0.18, green: 0.07, blue: 0.34), Color.black]
        case .light:
            return [Color.white, Color(white: 0.96), Color(white: 0.82)]
        }
    }
}

struct GlassCardModifier: ViewModifier {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    func body(content: Content) -> some View {
        let isDark = resolvedTheme(from: appThemeRawValue) == .dark

        content
            .padding(14)
            .background(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDark ? .white.opacity(0.22) : .black.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [isDark ? .white.opacity(0.32) : .white.opacity(0.7), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: isDark ? .black.opacity(0.25) : .black.opacity(0.1), radius: 14, y: 8)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FrostedPanelModifier: ViewModifier {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    func body(content: Content) -> some View {
        let isDark = resolvedTheme(from: appThemeRawValue) == .dark

        content
            .padding(14)
            .background(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isDark ? .white.opacity(0.3) : .black.opacity(0.14), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [isDark ? .white.opacity(0.45) : .white.opacity(0.9), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.12), radius: 18, y: 10)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct FrostedButtonStyle: ButtonStyle {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    func makeBody(configuration: Configuration) -> some View {
        let isDark = resolvedTheme(from: appThemeRawValue) == .dark

        return configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDark ? .white.opacity(0.28) : .black.opacity(0.14), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [isDark ? .white.opacity(0.45) : .white.opacity(0.95), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
