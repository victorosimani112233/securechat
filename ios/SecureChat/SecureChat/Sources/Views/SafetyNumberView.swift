import SwiftUI
import CoreImage.CIFilterBuiltins

/// Güvenlik numarası doğrulama ekranı
/// QR kod ve rakamsal güvenlik numarası gösterimi
public struct SafetyNumberView: View {

    let peerId: String
    let peerName: String

    @StateObject private var viewModel: SafetyNumberViewModel
    @EnvironmentObject private var navigationManager: NavigationManager
    @State private var showingVerificationSheet = false

    public init(peerId: String, peerName: String) {
        self.peerId = peerId
        self.peerName = peerName
        self._viewModel = StateObject(wrappedValue: SafetyNumberViewModel(peerId: peerId, peerName: peerName))
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Açıklama
                    VStack(spacing: 16) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Güvenlik Numarası")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Bu güvenlik numarası \(peerName) ile olan konuşmanızın uçtan uca şifrelendiğini doğrular.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    // QR Kod
                    VStack(spacing: 16) {
                        Text("QR Kodu taratarak doğrula")
                            .font(.headline)

                        if let qrImage = viewModel.qrCodeImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 200, height: 200)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 4)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 200, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    ProgressView()
                                }
                        }

                        Button("QR Kodu Tarat") {
                            // TODO: QR kod tarayıcısını aç
                            showingVerificationSheet = true
                        }
                        .foregroundColor(.blue)
                    }

                    // Sayısal güvenlik numarası
                    VStack(spacing: 16) {
                        Text("Sayısal güvenlik numarası")
                            .font(.headline)

                        if let safetyNumber = viewModel.safetyNumber {
                            SafetyNumberGridView(safetyNumber: safetyNumber)
                        } else {
                            ProgressView("Güvenlik numarası oluşturuluyor...")
                        }
                    }

                    // Doğrulama durumu
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: viewModel.isVerified ? "checkmark.shield.fill" : "shield")
                                .foregroundColor(viewModel.isVerified ? .green : .gray)

                            Text(viewModel.isVerified ? "Doğrulandı" : "Doğrulanmadı")
                                .font(.headline)
                                .foregroundColor(viewModel.isVerified ? .green : .gray)
                        }

                        if !viewModel.isVerified {
                            Button("Doğrula") {
                                viewModel.markAsVerified()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    // Bilgi metni
                    VStack(spacing: 12) {
                        Text("Bu numaralar her iki cihazda da aynı görünüyorsa konuşmanız güvenlidir.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Güvenlik numaraları hakkında daha fazla bilgi") {
                            // TODO: Yardım sayfası
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 32)
                }
                .padding(.vertical, 24)
            }
            .navigationTitle(peerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Geri") {
                        navigationManager.goBack()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            viewModel.shareSecurityNumber()
                        } label: {
                            Label("Paylaş", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            viewModel.copySafetyNumber()
                        } label: {
                            Label("Kopyala", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showingVerificationSheet) {
            QRScannerView { result in
                viewModel.verifyQRCode(result)
                showingVerificationSheet = false
            }
        }
    }
}

// MARK: - Safety Number Grid

/// Güvenlik numarasını 5x12 grid halinde gösteren view
struct SafetyNumberGridView: View {
    let safetyNumber: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<12, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(0..<5, id: \.self) { col in
                        let index = row * 5 + col
                        if index < safetyNumber.count {
                            let digit = String(Array(safetyNumber)[index])
                            Text(digit)
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - QR Scanner View

struct QRScannerView: View {
    let onResult: (String) -> Void

    var body: some View {
        NavigationView {
            VStack {
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        VStack {
                            Text("QR Kod Tarayıcısı")
                                .foregroundColor(.white)
                                .font(.title2)

                            Rectangle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 200, height: 200)

                            Text("Karşı tarafın QR kodunu taratın")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }

                Button("Demo Doğrulama") {
                    onResult("demo_qr_code_result")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 32)
            }
            .navigationTitle("QR Tarayıcı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("İptal") {
                        onResult("")
                    }
                }
            }
        }
    }
}

// MARK: - Safety Number ViewModel

@MainActor
class SafetyNumberViewModel: ObservableObject {
    @Published var safetyNumber: String?
    @Published var qrCodeImage: UIImage?
    @Published var isVerified: Bool = false

    private let peerId: String
    private let peerName: String

    init(peerId: String, peerName: String) {
        self.peerId = peerId
        self.peerName = peerName

        generateSafetyNumber()
        generateQRCode()
    }

    func markAsVerified() {
        isVerified = true
        // TODO: Doğrulama durumunu kaydet
    }

    func verifyQRCode(_ qrResult: String) {
        // TODO: QR kod doğrulaması
        if !qrResult.isEmpty {
            isVerified = true
        }
    }

    func shareSecurityNumber() {
        guard let safetyNumber = safetyNumber else { return }

        let shareText = "Güvenlik Numarası (\(peerName)):\n\n\(formatSafetyNumberForSharing(safetyNumber))"

        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }

    func copySafetyNumber() {
        guard let safetyNumber = safetyNumber else { return }

        UIPasteboard.general.string = formatSafetyNumberForSharing(safetyNumber)

        // TODO: Toast mesajı göster
    }

    private func generateSafetyNumber() {
        // Simüle edilmiş güvenlik numarası (60 haneli)
        let randomNumber = (0..<60).map { _ in String(Int.random(in: 0...9)) }.joined()
        self.safetyNumber = randomNumber
    }

    private func generateQRCode() {
        guard let safetyNumber = safetyNumber else { return }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        let data = Data(safetyNumber.utf8)
        filter.setValue(data, forKey: "inputMessage")

        if let qrCode = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledQRCode = qrCode.transformed(by: transform)

            if let cgImage = context.createCGImage(scaledQRCode, from: scaledQRCode.extent) {
                self.qrCodeImage = UIImage(cgImage: cgImage)
            }
        }
    }

    private func formatSafetyNumberForSharing(_ number: String) -> String {
        var formatted = ""
        for (index, digit) in number.enumerated() {
            if index % 5 == 0 && index > 0 {
                formatted += " "
            }
            if index % 25 == 0 && index > 0 {
                formatted += "\n"
            }
            formatted += String(digit)
        }
        return formatted
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SafetyNumberView(peerId: "sample-peer", peerName: "Ahmet Yılmaz")
            .environmentObject(NavigationManager())
    }
}