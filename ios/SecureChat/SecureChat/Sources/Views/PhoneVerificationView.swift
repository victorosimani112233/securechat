import SwiftUI

/// Telefon numarası doğrulama ekranı
/// Kullanıcının telefon numarasını girmesini ve doğrulamasını sağlar
public struct PhoneVerificationView: View {

    @StateObject private var viewModel = PhoneVerificationViewModel()
    @EnvironmentObject private var navigationManager: NavigationManager
    @FocusState private var isPhoneFieldFocused: Bool

    public init() {}

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    // Logo ve başlık
                    VStack(spacing: 16) {
                        Image(systemName: "message.and.waveform.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)

                        Text("SecureChat'e Hoş Geldiniz")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Güvenli mesajlaşma için telefon numaranızı doğrulayın")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Form
                    VStack(spacing: 24) {
                        // İsim girişi
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Adınız")
                                .font(.headline)
                                .foregroundColor(.primary)

                            TextField("Ad Soyad", text: $viewModel.fullName)
                                .textFieldStyle(RoundedTextFieldStyle())
                                .textContentType(.name)
                                .autocapitalization(.words)
                        }

                        // Ülke seçimi ve telefon girişi
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Telefon Numarası")
                                .font(.headline)
                                .foregroundColor(.primary)

                            HStack(spacing: 12) {
                                // Ülke kodu seçici
                                Button {
                                    viewModel.showCountryPicker = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(viewModel.selectedCountry.flag)
                                        Text(viewModel.selectedCountry.dialCode)
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .foregroundColor(.primary)

                                // Telefon numarası girişi
                                TextField("5XX XXX XX XX", text: $viewModel.phoneNumber)
                                    .textFieldStyle(RoundedTextFieldStyle())
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                                    .focused($isPhoneFieldFocused)
                            }
                        }

                        // Doğrulama butonu
                        Button {
                            viewModel.sendVerificationCode()
                        } label: {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Text("Doğrulama Kodu Gönder")
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

                    Spacer()

                    // Gizlilik metni
                    VStack(spacing: 8) {
                        Text("Devam ederek Kullanım Koşulları ve Gizlilik Politikası'nı kabul etmiş olursunuz.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Button("Kullanım Koşulları") {
                                // TODO: Kullanım koşulları
                            }

                            Button("Gizlilik Politikası") {
                                // TODO: Gizlilik politikası
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .navigationBarHidden(true)
            .onTapGesture {
                isPhoneFieldFocused = false
            }
        }
        .sheet(isPresented: $viewModel.showCountryPicker) {
            CountryPickerView(
                selectedCountry: $viewModel.selectedCountry,
                isPresented: $viewModel.showCountryPicker
            )
        }
        .onReceive(viewModel.$shouldNavigateToOTP) { shouldNavigate in
            if shouldNavigate {
                let fullPhoneNumber = viewModel.selectedCountry.dialCode + viewModel.phoneNumber
                navigationManager.navigate(to: .otpVerification(phoneNumber: fullPhoneNumber))
                viewModel.shouldNavigateToOTP = false
            }
        }
    }
}

// MARK: - Rounded TextField Style

struct RoundedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Phone Verification ViewModel

@MainActor
class PhoneVerificationViewModel: ObservableObject {
    @Published var fullName = ""
    @Published var phoneNumber = ""
    @Published var selectedCountry = Country.turkey
    @Published var showCountryPicker = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var shouldNavigateToOTP = false

    var isFormValid: Bool {
        !fullName.isEmpty && phoneNumber.count >= 10
    }

    func sendVerificationCode() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        // Simüle edilmiş API çağrısı
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isLoading = false

            // Başarılı doğrulama
            self.shouldNavigateToOTP = true
        }
    }
}

// MARK: - Country Model

struct Country {
    let name: String
    let dialCode: String
    let code: String
    let flag: String

    static let turkey = Country(name: "Turkey", dialCode: "+90", code: "TR", flag: "🇹🇷")
    static let usa = Country(name: "United States", dialCode: "+1", code: "US", flag: "🇺🇸")
    static let germany = Country(name: "Germany", dialCode: "+49", code: "DE", flag: "🇩🇪")

    static let all = [turkey, usa, germany]
}

// MARK: - Country Picker

struct CountryPickerView: View {
    @Binding var selectedCountry: Country
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List(Country.all, id: \.code) { country in
                Button {
                    selectedCountry = country
                    isPresented = false
                } label: {
                    HStack {
                        Text(country.flag)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text(country.name)
                                .font(.body)
                            Text(country.dialCode)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if selectedCountry.code == country.code {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Ülke Seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("İptal") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhoneVerificationView()
        .environmentObject(NavigationManager())
}