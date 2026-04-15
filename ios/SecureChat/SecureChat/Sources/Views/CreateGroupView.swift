import SwiftUI

/// Yeni grup oluşturma ekranı
/// Kişi seçimi ve grup bilgileri girişi için kullanılır
public struct CreateGroupView: View {

    @StateObject private var viewModel = CreateGroupViewModel()
    @EnvironmentObject private var navigationManager: NavigationManager

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.currentStep == .selectContacts {
                    contactSelectionView
                } else {
                    groupInfoView
                }
            }
            .navigationTitle(viewModel.currentStep == .selectContacts ? "Üye Seç" : "Yeni Grup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("İptal") {
                        navigationManager.goBack()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.currentStep == .selectContacts {
                        Button("İleri") {
                            viewModel.proceedToGroupInfo()
                        }
                        .disabled(viewModel.selectedContacts.isEmpty)
                    } else {
                        Button("Oluştur") {
                            viewModel.createGroup()
                        }
                        .disabled(viewModel.groupName.isEmpty)
                    }
                }
            }
        }
        .onReceive(viewModel.$shouldNavigateToChat) { groupId in
            if let groupId = groupId {
                navigationManager.openChat(conversationId: groupId)
                viewModel.shouldNavigateToChat = nil
            }
        }
    }

    // MARK: - Contact Selection View

    private var contactSelectionView: some View {
        VStack(spacing: 0) {
            // Seçili kişiler bar'ı
            if !viewModel.selectedContacts.isEmpty {
                selectedContactsBar
            }

            // Arama çubuğu
            SearchBar(
                text: $viewModel.searchQuery,
                placeholder: "Kişilerde ara..."
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Kişi listesi
            List {
                ForEach(viewModel.filteredContacts, id: \.phoneNumber) { contact in
                    SelectableContactItemView(
                        contact: contact,
                        isSelected: viewModel.selectedContacts.contains(where: { $0.phoneNumber == contact.phoneNumber })
                    ) { contact in
                        viewModel.toggleContactSelection(contact)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Selected Contacts Bar

    private var selectedContactsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(viewModel.selectedContacts, id: \.phoneNumber) { contact in
                    VStack(spacing: 4) {
                        ZStack {
                            GradientAvatar(
                                name: contact.displayName,
                                size: 48
                            )

                            Button {
                                viewModel.toggleContactSelection(contact)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 20, height: 20)
                                    )
                            }
                            .offset(x: 18, y: -18)
                        }

                        Text(contact.displayName.components(separatedBy: " ").first ?? "")
                            .font(.caption)
                            .lineLimit(1)
                            .frame(width: 60)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 80)
        .background(Color(.systemGray6))
    }

    // MARK: - Group Info View

    private var groupInfoView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Grup avatarı
                Button {
                    // TODO: Grup avatarı seç
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 100)

                        Image(systemName: "camera.fill")
                            .font(.title)
                            .foregroundColor(.gray)
                    }
                }

                // Grup adı girişi
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grup Adı")
                        .font(.headline)

                    TextField("Grup adını girin", text: $viewModel.groupName)
                        .textFieldStyle(RoundedTextFieldStyle())
                }

                // Grup açıklaması girişi
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grup Açıklaması (İsteğe Bağlı)")
                        .font(.headline)

                    TextField("Grup hakkında kısa bir açıklama", text: $viewModel.groupDescription, axis: .vertical)
                        .textFieldStyle(RoundedTextFieldStyle())
                        .lineLimit(3...6)
                }

                // Seçili üyeler listesi
                VStack(alignment: .leading, spacing: 12) {
                    Text("Grup Üyeleri (\(viewModel.selectedContacts.count))")
                        .font(.headline)

                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.selectedContacts, id: \.phoneNumber) { contact in
                            HStack(spacing: 12) {
                                GradientAvatar(
                                    name: contact.displayName,
                                    size: 40
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.displayName)
                                        .font(.body)
                                        .fontWeight(.medium)

                                    Text(contact.phoneNumber)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    viewModel.toggleContactSelection(contact)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - Selectable Contact Item

struct SelectableContactItemView: View {
    let contact: ContactInfo
    let isSelected: Bool
    let onToggle: (ContactInfo) -> Void

    var body: some View {
        Button {
            onToggle(contact)
        } label: {
            HStack(spacing: 12) {
                GradientAvatar(
                    name: contact.displayName,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(contact.phoneNumber)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                } else {
                    Circle()
                        .stroke(Color(.systemGray3), lineWidth: 1)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Group ViewModel

@MainActor
class CreateGroupViewModel: ObservableObject {
    @Published var currentStep: GroupCreationStep = .selectContacts
    @Published var selectedContacts: [ContactInfo] = []
    @Published var searchQuery = ""
    @Published var groupName = ""
    @Published var groupDescription = ""
    @Published var shouldNavigateToChat: String?

    // Mock data - gerçek implementasyonda ContactsManager'dan gelecek
    @Published var contacts: [ContactInfo] = [
        ContactInfo(
            displayName: "Ahmet Yılmaz",
            phoneNumber: "+90 555 123 4567",
            isSecureChatUser: true,
            secureChatUserId: "user1"
        ),
        ContactInfo(
            displayName: "Fatma Kaya",
            phoneNumber: "+90 555 234 5678",
            isSecureChatUser: true,
            secureChatUserId: "user2"
        ),
        ContactInfo(
            displayName: "Mehmet Demir",
            phoneNumber: "+90 555 345 6789",
            isSecureChatUser: true,
            secureChatUserId: "user3"
        )
    ]

    var filteredContacts: [ContactInfo] {
        if searchQuery.isEmpty {
            return contacts
        } else {
            return contacts.filter { contact in
                contact.displayName.localizedCaseInsensitiveContains(searchQuery) ||
                contact.phoneNumber.contains(searchQuery)
            }
        }
    }

    func toggleContactSelection(_ contact: ContactInfo) {
        if let index = selectedContacts.firstIndex(where: { $0.phoneNumber == contact.phoneNumber }) {
            selectedContacts.remove(at: index)
        } else {
            selectedContacts.append(contact)
        }
    }

    func proceedToGroupInfo() {
        currentStep = .groupInfo
    }

    func createGroup() {
        // Grup oluşturma simülasyonu
        let groupId = "group_\(UUID().uuidString)"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.shouldNavigateToChat = groupId
        }
    }
}

// MARK: - Supporting Types

enum GroupCreationStep {
    case selectContacts
    case groupInfo
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CreateGroupView()
            .environmentObject(NavigationManager())
    }
}