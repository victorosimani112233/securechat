import SwiftUI

/// Kişi seçimi ekranı
/// Rehber kişilerini gösterir ve SecureChat kullanıcıları ile sohbet başlatma imkanı sağlar
public struct ContactsView: View {

    @StateObject private var viewModel = ContactsViewModel()
    @EnvironmentObject private var navigationManager: NavigationManager

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // İzin durumu kontrolü
                if !viewModel.hasPermission {
                    ContactPermissionView {
                        viewModel.requestPermission()
                    }
                } else {
                    // Arama çubuğu
                    SearchBar(
                        text: Binding(
                            get: { viewModel.uiState.searchQuery },
                            set: { viewModel.updateSearchQuery($0) }
                        ),
                        placeholder: "Kişilerde ara..."
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if viewModel.uiState.isLoading {
                        ProgressView("Kişiler yükleniyor...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.filteredContacts.isEmpty {
                        EmptyStateView(
                            icon: "person.crop.circle.badge.questionmark",
                            title: "Kişi bulunamadı",
                            subtitle: "Rehberinizde SecureChat kullanıcısı bulunmuyor."
                        )
                    } else {
                        contactsList
                    }
                }
            }
            .navigationTitle("Kişiler")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("İptal") {
                        navigationManager.goBack()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.refreshContacts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.uiState.isLoading)
                }
            }
        }
        .onAppear {
            if viewModel.hasPermission {
                viewModel.refreshContacts()
            }
        }
    }

    // MARK: - Contacts List

    private var contactsList: some View {
        List {
            // SecureChat kullanıcıları
            if !viewModel.secureChatUsers.isEmpty {
                Section("SecureChat") {
                    ForEach(viewModel.secureChatUsers, id: \.phoneNumber) { contact in
                        ContactItemView(contact: contact, isSecureChatUser: true) {
                            if let userId = viewModel.startChat(with: contact) {
                                navigationManager.openChat(conversationId: userId)
                            }
                        }
                    }
                }
            }

            // Diğer kişiler
            if !viewModel.nonSecureChatUsers.isEmpty {
                Section("Diğer Kişiler") {
                    ForEach(viewModel.nonSecureChatUsers, id: \.phoneNumber) { contact in
                        ContactItemView(contact: contact, isSecureChatUser: false) {
                            viewModel.inviteContact(contact)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.refreshContacts()
        }
    }
}

// MARK: - Contact Permission View

/// Kişi izni isteme ekranı
struct ContactPermissionView: View {
    let requestPermission: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("Kişi İzni Gerekli")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("SecureChat kullanıcılarını bulmak için rehberinize erişim izni gerekiyor.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("İzin Ver") {
                requestPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(32)
    }
}

// MARK: - Contact Item View

/// Tek bir kişi öğesi
struct ContactItemView: View {
    let contact: ContactInfo
    let isSecureChatUser: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                GradientAvatar(
                    name: contact.displayName,
                    size: 48
                )

                // İçerik
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(formatPhoneNumber(contact.phoneNumber))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Durum göstergesi
                if isSecureChatUser {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundColor(.blue)

                        Text("Davet Et")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Basit telefon numarası formatlaması
        if phoneNumber.hasPrefix("+90") {
            let cleaned = phoneNumber.dropFirst(3)
            if cleaned.count == 10 {
                let areaCode = cleaned.prefix(3)
                let middle = cleaned.dropFirst(3).prefix(3)
                let last = cleaned.suffix(4)
                return "+90 \(areaCode) \(middle) \(last)"
            }
        }
        return phoneNumber
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContactsView()
            .environmentObject(NavigationManager())
    }
}