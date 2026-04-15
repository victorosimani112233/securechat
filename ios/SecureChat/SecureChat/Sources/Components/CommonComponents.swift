import SwiftUI

// MARK: - Avatar Component

/// Gradient renkli avatar bileşeni
public struct GradientAvatar: View {
    let name: String
    let size: CGFloat
    let isGroup: Bool

    public init(name: String, size: CGFloat = 48, isGroup: Bool = false) {
        self.name = name
        self.size = size
        self.isGroup = isGroup
    }

    public var body: some View {
        Circle()
            .fill(gradientForName(name))
            .frame(width: size, height: size)
            .overlay {
                if isGroup {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.white)
                        .font(.system(size: size * 0.4))
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
    }

    private func gradientForName(_ name: String) -> LinearGradient {
        let colorPairs: [(Color, Color)] = [
            (Color(hex: "00897B"), Color(hex: "004D40")),
            (Color(hex: "00ACC1"), Color(hex: "006064")),
            (Color(hex: "5C6BC0"), Color(hex: "283593")),
            (Color(hex: "7E57C2"), Color(hex: "4527A0")),
            (Color(hex: "EF5350"), Color(hex: "B71C1C")),
            (Color(hex: "FF7043"), Color(hex: "BF360C")),
            (Color(hex: "26A69A"), Color(hex: "00695C")),
            (Color(hex: "42A5F5"), Color(hex: "1565C0")),
            (Color(hex: "EC407A"), Color(hex: "880E4F")),
            (Color(hex: "66BB6A"), Color(hex: "2E7D32"))
        ]

        let index = abs(name.hashValue) % colorPairs.count
        let (startColor, endColor) = colorPairs[index]

        return LinearGradient(
            colors: [startColor, endColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Connection Status Banner

/// Bağlantı durumu banner'ı
public struct ConnectionStatusBanner: View {
    let connectionState: ConnectionState

    public init(connectionState: ConnectionState) {
        self.connectionState = connectionState
    }

    public var body: some View {
        if connectionState != .connected {
            HStack(spacing: 8) {
                Image(systemName: iconForState(connectionState))
                    .foregroundColor(colorForState(connectionState))

                Text(textForState(connectionState))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(colorForState(connectionState))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .overlay(
                Rectangle()
                    .frame(width: 4)
                    .foregroundColor(colorForState(connectionState)),
                alignment: .leading
            )
        }
    }

    private func textForState(_ state: ConnectionState) -> String {
        switch state {
        case .connecting:
            return "Bağlanıyor..."
        case .disconnected:
            return "Bağlantı kesildi"
        case .error:
            return "Bağlantı hatası"
        case .connected:
            return ""
        }
    }

    private func iconForState(_ state: ConnectionState) -> String {
        switch state {
        case .connecting:
            return "wifi.exclamationmark"
        case .disconnected:
            return "wifi.slash"
        case .error:
            return "exclamationmark.triangle.fill"
        case .connected:
            return "wifi"
        }
    }

    private func colorForState(_ state: ConnectionState) -> Color {
        switch state {
        case .connecting:
            return .orange
        case .disconnected, .error:
            return .red
        case .connected:
            return .green
        }
    }
}

// MARK: - Message Status Icon

/// Mesaj durumu ikonu
public struct MessageStatusIcon: View {
    let status: MessageStatus

    public init(status: MessageStatus) {
        self.status = status
    }

    public var body: some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.gray)

            case .sent:
                Image(systemName: "checkmark")
                    .foregroundColor(.gray)

            case .delivered:
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.blue)

            case .read:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)

            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.red)
            }
        }
        .font(.caption2)
    }
}

// MARK: - Empty State View

/// Boş durum gösterimi için genel component
public struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(icon: String, title: String, subtitle: String,
               actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: icon)
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(48)
    }
}

// MARK: - Search Bar

/// Arama çubuğu component'i
public struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    public init(text: Binding<String>, placeholder: String = "Ara...") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Floating Action Button

/// Floating action button component'i
public struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void

    public init(icon: String, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Extensions

extension Color {
    /// Hex renk kodundan Color oluştur
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}