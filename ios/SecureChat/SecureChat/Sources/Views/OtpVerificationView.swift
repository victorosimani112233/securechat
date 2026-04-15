import SwiftUI

/// OTP doğrulama ekranı
/// Telefona gönderilen doğrulama kodunu girmesini sağlar
public struct OtpVerificationView: View {

    let phoneNumber: String

    @StateObject private var viewModel: OtpVerificationViewModel
    @EnvironmentObject private var navigationManager: NavigationManager
    @FocusState private var isOtpFieldFocused: Bool

    public init(phoneNumber: String) {
        self.phoneNumber = phoneNumber
        self._viewModel = StateObject(wrappedValue: OtpVerificationViewModel(phoneNumber: phoneNumber))
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    // Başlık ve açıklama
                    VStack(spacing: 16) {
                        Image(systemName: "message.badge.filled.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)

                        Text("Doğrulama Kodu")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        VStack(spacing: 8) {
                            Text("Şu numaraya gönderilen 6 haneli kodu girin:")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Text(formatPhoneNumber(phoneNumber))
                                .font(.headline)
                                .foregroundColor(.primary)

                            Button("Numarayı değiştir") {
                                navigationManager.goBack()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 32)

                    // OTP giriş alanları
                    VStack(spacing: 24) {
                        OtpInputView(
                            otpText: $viewModel.otpCode,
                            isFirstResponder: $isOtpFieldFocused
                        )

                        // Doğrulama butonu
                        Button {
                            viewModel.verifyOTP()
                        } label: {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Text("Doğrula")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                viewModel.isFormValid ?
                                Color.blue : Color.gray
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!viewModel.isFormValid || viewModel.isLoading)

                        // Hata mesajı
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 32)

                    // Yeniden gönder bölümü
                    VStack(spacing: 16) {
                        if viewModel.resendCountdown > 0 {
                            Text("Yeniden gönder (\(viewModel.resendCountdown)s)")
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else {
                            Button("Doğrulama kodunu yeniden gönder") {
                                viewModel.resendOTP()
                            }
                            .font(.body)
                            .foregroundColor(.blue)
                        }
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .onTapGesture {
                isOtpFieldFocused = false
            }
        }
        .onReceive(viewModel.$shouldNavigateToMainFlow) { shouldNavigate in
            if shouldNavigate {
                navigationManager.startMainFlow()
                viewModel.shouldNavigateToMainFlow = false
            }
        }
        .onAppear {
            isOtpFieldFocused = true
        }
    }

    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Basit telefon numarası formatlaması
        if phoneNumber.hasPrefix("+90") && phoneNumber.count == 13 {
            let number = String(phoneNumber.dropFirst(3))
            return "+90 \(number.prefix(3)) \(number.dropFirst(3).prefix(3)) \(number.suffix(4))"
        }
        return phoneNumber
    }
}

// MARK: - OTP Input View

/// 6 haneli OTP giriş alanı
struct OtpInputView: View {
    @Binding var otpText: String
    @Binding var isFirstResponder: Bool

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    OtpDigitView(
                        digit: otpText.count > index ?
                            String(Array(otpText)[index]) : "",
                        isActive: otpText.count == index && isFirstResponder
                    )
                }
            }

            // Gizli TextField
            TextField("", text: $otpText)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFirstResponder)
                .opacity(0)
                .frame(height: 1)
                .onChange(of: otpText) { newValue in
                    // Sadece rakam giriş
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered.count <= 6 {
                        otpText = filtered
                    } else {
                        otpText = String(filtered.prefix(6))
                    }
                }
        }
        .onTapGesture {
            isFirstResponder = true
        }
    }
}

// MARK: - OTP Digit View

/// Tek bir OTP rakamı görünümü
struct OtpDigitView: View {
    let digit: String
    let isActive: Bool

    var body: some View {
        Text(digit)
            .font(.title)
            .fontWeight(.semibold)
            .frame(width: 45, height: 55)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive ? Color.blue : Color(.systemGray4),
                        lineWidth: isActive ? 2 : 1
                    )
                    .background(
                        Color(.systemGray6)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - OTP Verification ViewModel

@MainActor
class OtpVerificationViewModel: ObservableObject {
    @Published var otpCode = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var shouldNavigateToMainFlow = false
    @Published var resendCountdown = 60

    private let phoneNumber: String
    private var resendTimer: Timer?

    init(phoneNumber: String) {
        self.phoneNumber = phoneNumber
        startResendTimer()
    }

    var isFormValid: Bool {
        otpCode.count == 6
    }

    func verifyOTP() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        // Simüle edilmiş API çağrısı
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isLoading = false

            // Demo için her zaman başarılı
            if self.otpCode == "123456" || self.otpCode.count == 6 {
                self.shouldNavigateToMainFlow = true
            } else {
                self.errorMessage = "Geçersiz doğrulama kodu. Lütfen tekrar deneyin."
            }
        }
    }

    func resendOTP() {
        guard resendCountdown == 0 else { return }

        resendCountdown = 60
        startResendTimer()

        // Simüle edilmiş yeniden gönder işlemi
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // TODO: API çağrısı
            print("OTP yeniden gönderildi: \(self.phoneNumber)")
        }
    }

    private func startResendTimer() {
        resendTimer?.invalidate()

        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.resendCountdown > 0 {
                self.resendCountdown -= 1
            } else {
                self.resendTimer?.invalidate()
            }
        }
    }

    deinit {
        resendTimer?.invalidate()
    }
}

// MARK: - Preview

#Preview {
    OtpVerificationView(phoneNumber: "+90 555 123 4567")
        .environmentObject(NavigationManager())
}