import SwiftUI

struct PhoneVerificationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var code = ""
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(spacing: 14) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.purple)

                    Text("Підтвердження телефону")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("Ми надіслали код на номер \(appState.phoneVerificationMaskedPhone)")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    TextField("Код із SMS", text: $code)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 4)

                    if !appState.phoneVerificationDemoCode.isEmpty {
                        Text("Демо-код: \(appState.phoneVerificationDemoCode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = appState.authErrorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Підтвердити") {
                        _ = appState.submitPhoneVerification(code: code)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .frame(maxWidth: .infinity)

                    let remaining = appState.phoneVerificationSecondsRemaining(now: now)
                    Button(remaining == 0 ? "Надіслати код повторно" : "Повторно через \(remaining) с") {
                        _ = appState.resendPhoneVerificationCode(now: now)
                    }
                    .buttonStyle(.bordered)
                    .disabled(remaining != 0)

                    Spacer(minLength: 0)
                }
                .padding(20)
                .glassCard()
                .padding(.horizontal, 16)
            }
            .navigationBarHidden(true)
            .onAppear {
                appState.ensurePhoneVerificationSession()
            }
            .onReceive(timer) { date in
                now = date
            }
        }
    }
}
