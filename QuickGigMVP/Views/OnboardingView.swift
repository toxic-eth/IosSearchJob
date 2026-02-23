import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
}

struct OnboardingView: View {
    let onSkip: () -> Void
    let onSelectRole: (UserRole) -> Void
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.uk.rawValue

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "onb.quick_title",
            subtitle: "onb.quick_sub",
            icon: "briefcase.fill",
            gradient: [Color.indigo, Color.purple]
        ),
        OnboardingPage(
            title: "onb.clear_title",
            subtitle: "onb.clear_sub",
            icon: "checkmark.shield.fill",
            gradient: [Color.purple, Color.indigo]
        ),
        OnboardingPage(
            title: "onb.safe_title",
            subtitle: "onb.safe_sub",
            icon: "lock.shield.fill",
            gradient: [Color.purple, Color.black]
        ),
    ]

    private var language: AppLanguage { resolvedLanguage(from: appLanguageRawValue) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.95), Color.purple.opacity(0.72), Color.indigo.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button(I18n.t("onb.skip", language)) {
                        onSkip()
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 20)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageCard(page: page)
                            .padding(.horizontal, 20)
                            .tag(index)
                    }

                    roleSelectionSlide
                        .padding(.horizontal, 20)
                        .tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: 540)
                .animation(.easeInOut(duration: 0.4), value: currentPage)

                HStack(spacing: 8) {
                    ForEach(0..<(pages.count + 1), id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.35))
                            .frame(width: index == currentPage ? 22 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.top, 2)

                Group {
                    if currentPage < pages.count {
                        Button(I18n.t("onb.next", language)) {
                            withAnimation(.easeInOut(duration: 0.38)) {
                                currentPage += 1
                            }
                        }
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text(I18n.t("onb.pick_role", language))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(height: 70)
                .animation(.easeInOut(duration: 0.35), value: currentPage)
            }
        }
    }

    private func pageCard(page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: page.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 260)
                .overlay {
                    Image(systemName: page.icon)
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(.white)
                }

            Text(I18n.t(page.title, language))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(I18n.t(page.subtitle, language))
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var roleSelectionSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color.purple, Color.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 220)
                .overlay {
                    Image(systemName: "person.2.badge.key.fill")
                        .font(.system(size: 68, weight: .bold))
                        .foregroundStyle(.white)
                }

            Text(I18n.t("onb.role_title", language))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(I18n.t("onb.role_sub", language))
                .font(.system(size: 19, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.9))

            roleActionButton(
                title: I18n.t("onb.worker", language),
                gradient: [Color.purple.opacity(0.98), Color.indigo.opacity(0.88)]
            ) {
                onSelectRole(.worker)
            }

            roleActionButton(
                title: I18n.t("onb.employer", language),
                gradient: [Color.indigo.opacity(0.98), Color.purple.opacity(0.84)]
            ) {
                onSelectRole(.employer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func roleActionButton(title: String, gradient: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
