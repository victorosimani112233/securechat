import SwiftUI

/// Sohbet ekranı
/// Mesaj baloncukları, chat header, mesaj giriş çubuğu ve dosya gönderme desteği içerir
public struct ChatView: View {

    let conversationId: String

    @StateObject private var viewModel: ChatViewModel
    @EnvironmentObject private var navigationManager: NavigationManager
    @State private var scrollProxy: ScrollViewReader?

    public init(conversationId: String) {
        self.conversationId = conversationId
        self._viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversationId))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Chat header
            ChatHeaderView(
                conversationInfo: viewModel.conversationInfo,
                onVoiceCallTap: {
                    if let peerId = viewModel.startVoiceCall() {
                        navigationManager.startVoiceCall(with: peerId)
                    }
                },
                onVideoCallTap: {
                    if let peerId = viewModel.startVideoCall() {
                        navigationManager.startVideoCall(with: peerId)
                    }
                }
            )

            Divider()

            // Mesaj listesi
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(groupedMessagesByDate(), id: \.date) { group in
                            // Tarih ayırıcısı
                            DateSeparatorView(date: group.date)

                            // Bu tarihteki mesajlar
                            ForEach(group.messages, id: \.id) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    scrollToBottom()
                }
            }

            // Mesaj giriş alanı
            MessageInputView(
                text: Binding(
                    get: { viewModel.uiState.messageText },
                    set: { viewModel.updateMessageText($0) }
                ),
                onSend: {
                    viewModel.sendMessage(viewModel.uiState.messageText)
                },
                onAttachmentTap: {
                    // TODO: Dosya seçici aç
                }
            )
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    navigationManager.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            viewModel.markMessagesAsRead()
        }
    }

    // MARK: - Private Methods

    private func groupedMessagesByDate() -> [MessageGroup] {
        let grouped = Dictionary(grouping: viewModel.messages) { message in
            Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(message.timestamp / 1000)))
        }

        return grouped.map { (date, messages) in
            MessageGroup(date: date, messages: messages.sorted { $0.timestamp < $1.timestamp })
        }.sorted { $0.date < $1.date }
    }

    private func scrollToBottom() {
        guard let lastMessage = viewModel.messages.last else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Chat Header

/// Sohbet ekranı header'ı
struct ChatHeaderView: View {
    let conversationInfo: ConversationInfo?
    let onVoiceCallTap: () -> Void
    let onVideoCallTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let info = conversationInfo {
                GradientAvatar(
                    name: info.peerName,
                    size: 40,
                    isGroup: info.isGroup
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.peerName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(info.isOnline ? "Çevrimiçi" : "Çevrimdışı")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 16) {
                    Button(action: onVoiceCallTap) {
                        Image(systemName: "phone.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }

                    Button(action: onVideoCallTap) {
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            } else {
                HStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 16)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 12)
                    }

                    Spacer()
                }
                .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Message Bubble

/// Mesaj baloncuğu view'i
struct MessageBubbleView: View {
    let message: LocalMessage

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(message.isOutgoing ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.isOutgoing ?
                        Color.blue :
                        Color(.systemGray5)
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: message.isOutgoing ? 16 : 4,
                            bottomTrailingRadius: message.isOutgoing ? 4 : 16,
                            topTrailingRadius: 16
                        )
                    )

                HStack(spacing: 4) {
                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if message.isOutgoing {
                        MessageStatusIcon(status: message.status)
                    }
                }
            }

            if !message.isOutgoing {
                Spacer(minLength: 80)
            }
        }
    }
}

// MARK: - Date Separator

/// Tarih ayırıcısı
struct DateSeparatorView: View {
    let date: Date

    var body: some View {
        Text(formatDate(date))
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()

        if Calendar.current.isDateInToday(date) {
            return "Bugün"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Dün"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Message Input

/// Mesaj giriş alanı
struct MessageInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    let onAttachmentTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAttachmentTap) {
                Image(systemName: "paperclip")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            HStack {
                TextField("Mesaj yazın...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)

                if !text.isEmpty {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Supporting Types

struct MessageGroup {
    let date: Date
    let messages: [LocalMessage]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView(conversationId: "sample-conversation")
            .environmentObject(NavigationManager())
    }
}