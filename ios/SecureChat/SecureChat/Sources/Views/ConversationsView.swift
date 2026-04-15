import SwiftUI

/// Konuşma listesi ana ekranı
/// Tüm aktif konuşmaları gösterir, yeni sohbet başlatma FAB'i ve ayarlar erişimi sağlar
public struct ConversationsView: View {

    @StateObject private var viewModel = ConversationsViewModel()
    @EnvironmentObject private var navigationManager: NavigationManager

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Bağlantı durumu banner'ı
                    if viewModel.connectionState != .connected {
                        ConnectionStatusBanner(connectionState: viewModel.connectionState)
                    }

                    // Arama çubuğu
                    if viewModel.uiState.isSearchVisible {
                        VStack {
                            SearchBar(
                                text: Binding(
                                    get: { viewModel.uiState.searchQuery },
                                    set: { viewModel.updateSearchQuery($0) }
                                ),
                                placeholder: "Sohbetlerde ara..."
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            Divider()
                        }
                    }

                    // Konuşma listesi
                    if viewModel.filteredConversations.isEmpty {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: viewModel.uiState.searchQuery.isEmpty ? "Henüz bir sohbet yok" : "Sonuç bulunamadı",
                            subtitle: viewModel.uiState.searchQuery.isEmpty ?
                                "Yeni sohbet başlatmak için\nsağ alttaki butona dokunun." :
                                "Farklı bir arama terimi deneyin."
                        )
                    } else {
                        List {
                            ForEach(viewModel.filteredConversations, id: \.id) { conversation in
                                ConversationItemView(
                                    conversation: conversation,
                                    onTap: {
                                        navigationManager.openChat(conversationId: conversation.id)
                                    }
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.deleteConversation(conversation.id)
                                    } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            viewModel.refreshConversations()
                        }
                    }

                    Spacer()
                }

                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingActionButton(icon: "plus.bubble") {
                            navigationManager.startNewChat()
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Elçim")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        // TODO: Yeni grup oluştur
                    } label: {
                        Image(systemName: "person.2.badge.plus")
                    }

                    Button {
                        viewModel.toggleSearchVisibility()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }

                    Button {
                        navigationManager.openSettings()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .onAppear {
            viewModel.refreshConversations()
        }
    }
}

// MARK: - Conversation Item View

/// Tek bir konuşma öğesi view'i
struct ConversationItemView: View {
    let conversation: Conversation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                GradientAvatar(
                    name: conversation.peerName,
                    size: 52,
                    isGroup: conversation.isGroup
                )

                // İçerik
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(conversation.peerName)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(conversation.formattedLastMessageTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(conversation.lastMessage ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        if conversation.unreadCount > 0 {
                            Text("\(conversation.unreadCount)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ConversationsView()
            .environmentObject(NavigationManager())
    }
}