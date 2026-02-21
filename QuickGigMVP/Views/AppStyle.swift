import SwiftUI

struct AppBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.09, blue: 0.22), Color(red: 0.06, green: 0.34, blue: 0.47), Color(red: 0.11, green: 0.55, blue: 0.66)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.thinMaterial.opacity(0.55))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
