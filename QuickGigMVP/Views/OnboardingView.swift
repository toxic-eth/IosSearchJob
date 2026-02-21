import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
}

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Швидкий старт у зміні",
            subtitle: "Знаходьте підробіток поруч, відгукуйтесь за хвилину та виходьте вже сьогодні або завтра.",
            icon: "briefcase.fill",
            gradient: [Color.blue, Color.cyan]
        ),
        OnboardingPage(
            title: "Прозорі умови",
            subtitle: "Оплата, час, адреса та опис задачі видно до відгуку. Жодних сюрпризів на місці.",
            icon: "checkmark.shield.fill",
            gradient: [Color.green, Color.mint]
        ),
        OnboardingPage(
            title: "Рейтинг і довіра",
            subtitle: "Працівники та роботодавці оцінюють одне одного після зміни, формуючи чесну репутацію.",
            icon: "star.circle.fill",
            gradient: [Color.orange, Color.red]
        ),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.95), Color.blue.opacity(0.65), Color.cyan.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button("Пропустити") {
                        onFinish()
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
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxHeight: 540)

                Button(currentPage == pages.count - 1 ? "Почати" : "Далі") {
                    if currentPage == pages.count - 1 {
                        onFinish()
                    } else {
                        currentPage += 1
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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

            Text(page.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            Text(page.subtitle)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
