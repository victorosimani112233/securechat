import SwiftUI

/// Ayarlar ekranı
/// Kullanıcı profili, güvenlik ayarları, bildirimler ve uygulama tercihleri
public struct SettingsView: View {

    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var navigationManager: NavigationManager

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                // Profil bölümü
                profileSection

                // Güvenlik bölümü
                securitySection

                // Bildirimler bölümü
                notificationsSection

                // Görünüm bölümü
                appearanceSection

                // Hakkında bölümü
                aboutSection
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Bitti") {
                        navigationManager.goBack()
                    }
                }
            }
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                GradientAvatar(
                    name: viewModel.uiState.userProfile?.name ?? "Kullanıcı",
                    size: 60
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.uiState.userProfile?.name ?? "Ad bulunamadı")
                        .font(.headline)

                    Text(viewModel.uiState.userProfile?.phoneNumber ?? "Telefon bulunamadı")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("SecureChat kullanıcısı")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Spacer()

                Button {
                    // TODO: Profil düzenleme
                } label: {
                    Text("Düzenle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section("Güvenlik") {
            SettingsRow(
                icon: "key.fill",
                title: "Güvenlik Numarası",
                subtitle: "Kişilerle güvenlik numaralarını doğrulayın",
                iconColor: .green
            ) {
                // TODO: Güvenlik numarası ekranını aç
            }

            SettingsRow(
                icon: "faceid",
                title: "Biyometrik Kilidi",
                subtitle: "Face ID/Touch ID ile uygulamayı kilitleyin",
                iconColor: .blue
            ) {
                // Biyometrik ayar değiştir
                viewModel.toggleBiometrics()
            } trailingContent: {
                Toggle("", isOn: Binding(
                    get: { viewModel.uiState.isBiometricsEnabled },
                    set: { _ in viewModel.toggleBiometrics() }
                ))
            }

            SettingsRow(
                icon: "lock.shield.fill",
                title: "Otomatik Kilitleme",
                subtitle: "Uygulamayı otomatik olarak kilitleme süresi",
                iconColor: .orange
            ) {
                // TODO: Kilitleme süresi ayarları
            } trailingContent: {
                Text("5 dakika")
                    .foregroundColor(.secondary)
            }

            SettingsRow(
                icon: "eye.slash.fill",
                title: "Ekran Güvenliği",
                subtitle: "Ekran görüntüsü alınmasını engelle",
                iconColor: .red
            ) {
                // TODO: Ekran güvenliği ayarları
            } trailingContent: {
                Toggle("", isOn: .constant(true))
                    .disabled(true)
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section("Bildirimler") {
            SettingsRow(
                icon: "bell.fill",
                title: "Bildirimler",
                subtitle: "Mesaj bildirimleri",
                iconColor: .blue
            ) {
                viewModel.toggleNotifications()
            } trailingContent: {
                Toggle("", isOn: Binding(
                    get: { viewModel.uiState.isNotificationsEnabled },
                    set: { _ in viewModel.toggleNotifications() }
                ))
            }

            if viewModel.uiState.isNotificationsEnabled {
                SettingsRow(
                    icon: "speaker.wave.2.fill",
                    title: "Ses",
                    subtitle: "Bildirim sesini değiştir",
                    iconColor: .green
                ) {
                    // TODO: Ses ayarları
                } trailingContent: {
                    Text("Varsayılan")
                        .foregroundColor(.secondary)
                }

                SettingsRow(
                    icon: "moon.fill",
                    title: "Sessiz Saatler",
                    subtitle: "22:00 - 08:00",
                    iconColor: .indigo
                ) {
                    // TODO: Sessiz saatler ayarları
                }
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section("Görünüm") {
            SettingsRow(
                icon: "paintpalette.fill",
                title: "Tema",
                subtitle: "Uygulama temasını seçin",
                iconColor: .purple
            ) {
                // TODO: Tema seçici
            } trailingContent: {
                Text("Sistem")
                    .foregroundColor(.secondary)
            }

            SettingsRow(
                icon: "textformat.size",
                title: "Font Boyutu",
                subtitle: "Metin boyutunu ayarlayın",
                iconColor: .orange
            ) {
                // TODO: Font boyutu ayarları
            } trailingContent: {
                Text("Normal")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("Hakkında") {
            SettingsRow(
                icon: "info.circle.fill",
                title: "SecureChat",
                subtitle: "Sürüm 1.0.0",
                iconColor: .blue
            ) {
                // TODO: Uygulama hakkında
            }

            SettingsRow(
                icon: "doc.text.fill",
                title: "Gizlilik Politikası",
                subtitle: "Veri kullanım politikamızı okuyun",
                iconColor: .gray
            ) {
                // TODO: Gizlilik politikası
            }

            SettingsRow(
                icon: "questionmark.circle.fill",
                title: "Yardım ve Destek",
                subtitle: "SSS ve iletişim bilgileri",
                iconColor: .green
            ) {
                // TODO: Yardım ekranı
            }

            SettingsRow(
                icon: "square.and.arrow.up.fill",
                title: "Uygulamayı Paylaş",
                subtitle: "SecureChat'i arkadaşlarınla paylaş",
                iconColor: .blue
            ) {
                // TODO: Uygulama paylaş
            }
        }
    }
}

// MARK: - Settings Row

/// Ayarlar satırı component'i
struct SettingsRow<TrailingContent: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let iconColor: Color
    let action: () -> Void
    let trailingContent: () -> TrailingContent

    init(icon: String, title: String, subtitle: String? = nil,
         iconColor: Color, action: @escaping () -> Void,
         @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
        self.action = action
        self.trailingContent = trailingContent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // İkon
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // İçerik
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Trailing content
                trailingContent()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings ViewModel

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var uiState = SettingsUIState()

    init() {
        loadUserProfile()
    }

    func toggleNotifications() {
        uiState.isNotificationsEnabled.toggle()
        // TODO: Bildirim ayarlarını kaydet
    }

    func toggleBiometrics() {
        uiState.isBiometricsEnabled.toggle()
        // TODO: Biyometrik ayarları kaydet
    }

    private func loadUserProfile() {
        // TODO: Kullanıcı profilini yükle
        uiState.userProfile = UserProfile(
            id: "sample-id",
            name: "Kullanıcı",
            phoneNumber: "+90 555 123 4567",
            profileImageUrl: nil
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(NavigationManager())
    }
}