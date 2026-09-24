import Flutter
import AVFoundation
import Contacts
import CallKit
import UIKit
import workmanager_apple
import firebase_messaging
import LocalAuthentication
import SQLCipher
import UserNotifications
import WebRTC

enum SecureChatContactsAccess {
  static func isReadable(_ status: CNAuthorizationStatus) -> Bool {
    if status == .authorized { return true }
    if #available(iOS 18.0, *), status == .limited { return true }
    return false
  }

  static var keysToFetch: [CNKeyDescriptor] {
    // The formatter accesses more than givenName/familyName. Missing keys
    // raise an Objective-C exception, which Swift do/catch cannot handle.
    [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
     CNContactPhoneNumbersKey as CNKeyDescriptor]
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let maintenanceTask = "com.securechat.app.background.maintenance"
  private static let senderKeyRotationTask = "com.securechat.app.background.sender-key-rotation"
  private let channelName = "com.securechat/native"
  private let videoThumbnailQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.securechat.video-thumbnails"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    return queue
  }()
  private var privacyOverlay: UIView?
  private var privacyOverlayHooksInstalled = false
  private var documentController: UIDocumentInteractionController?
  private let callIntegration = SecureChatCallKitIntegration()
  private let callTones = SecureChatCallTonePlayer()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: Self.maintenanceTask,
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: Self.senderKeyRotationTask,
      earliestBeginInSeconds: NSNumber(value: 7 * 24 * 60 * 60)
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    installPrivacyOverlayHooks()
    // Gomulu SQLCipher'i uygulama ikilisinde tutar.
    //
    // SQLCipher'a yalniz Dart FFI tarafindan basvuruluyor; Swift veya
    // Objective-C hicbir simgesine dokunmuyor. Bu cagri olmadan baglayici,
    // basvurulmayan statik kutuphaneyi atar ve uygulama iOS'un DUZ
    // SQLite'ina duser — o da `PRAGMA key`i sessizce yok sayip veritabanini
    // SIFRESIZ yazar. Dart tarafindaki `PRAGMA cipher_version` denetimi bu
    // durumu yakalayip depoyu hic acmaz; buradaki cagri sorunun en bastan
    // olusmamasi icin.
    SQLCipherRuntime.ensureLinked()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "native_bridge") else {
      assertionFailure("SecureChat native bridge registrar is unavailable")
      return
    }
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    callIntegration.onAction = { action, callId in
      channel.invokeMethod("nativeCallAction", arguments: ["action": action, "callId": callId])
    }
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enableScreenProtection":
        self?.installPrivacyOverlayHooks()
        result(nil)
      case "registerCallIntegration":
        self?.callIntegration.initialize()
        result(nil)
      case "reportIncomingCall":
        self?.handleCallKitReport(call.arguments, incoming: true, result: result)
      case "reportOutgoingCall":
        self?.handleCallKitReport(call.arguments, incoming: false, result: result)
      case "setNativeCallActive":
        self?.handleCallKitState(call.arguments, active: true, result: result)
      case "answerNativeCall":
        guard let callId = (call.arguments as? [String: Any])?["callId"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "callId is missing", details: nil))
          return
        }
        self?.callIntegration.answer(callId: callId) { error in
          if let error = error {
            result(FlutterError(code: "ANSWER_CALL_FAILED", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      case "setCallSpeaker":
        // CallKit owns the call lifecycle, while flutter_webrtc owns the
        // AVAudioSession route. Returning false keeps that route as fallback.
        result(false)
      case "endNativeCall":
        self?.handleCallKitState(call.arguments, active: false, result: result)
      case "startNativeCallRingback":
        result(self?.callTones.startRingback() ?? false)
      case "stopNativeCallTones":
        self?.callTones.stop()
        result(true)
      case "playNativeCallCue":
        let cue = (call.arguments as? [String: Any])?["cue"] as? String ?? ""
        result(self?.callTones.playCue(cue) ?? false)
      case "authenticateLockedChat":
        self?.authenticateLockedChat(call.arguments, result: result)
      case "getCallReadiness":
        self?.getCallReadiness(result: result)
      case "openNotificationChannelSettings":
        // iOS'ta bildirim KANALI kavrami yok; ses secimi paketlenmis
        // listeden yapiliyor. Burada yalnizca uygulamanin bildirim
        // ayarlari aciliyor (izin, banner, kilit ekrani gorunumu).
        self?.openNotificationSettings(result: result)
      case "openCallReadinessSetting":
        self?.openCallReadinessSetting(call.arguments, result: result)
      case "requestContactsPermission":
        self?.requestContactsPermission(result: result)
      case "readContacts":
        self?.readContacts(result: result)
      case "openLocalFile":
        self?.openLocalFile(call.arguments, result: result)
      case "localVideoThumbnail":
        guard let self = self else { result(nil); return }
        self.localVideoThumbnail(call.arguments, result: result)
      case "shareLocalFile":
        self?.shareLocalFile(call.arguments, result: result)
      case "getDiagnosticsMetadata":
        result([
          "versionName": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
          "versionCode": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
          "operatingSystem": "ios",
          "osVersion": UIDevice.current.systemVersion,
          "deviceModel": UIDevice.current.model,
          "manufacturer": "Apple"
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func authenticateLockedChat(_ arguments: Any?, result: @escaping FlutterResult) {
    let values = arguments as? [String: Any]
    let title = (values?["title"] as? String)?.prefix(80) ?? "Kilitli Sohbet"
    let context = LAContext()
    context.localizedCancelTitle = "İptal"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      result(FlutterError(
        code: "AUTH_UNAVAILABLE",
        message: error?.localizedDescription ?? "No biometric or device credential is configured",
        details: nil
      ))
      return
    }
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: "\(title) sohbetine erişmek için kimliğinizi doğrulayın"
    ) { success, _ in
      DispatchQueue.main.async { result(success) }
    }
  }

  private func getCallReadiness(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let granted: Bool
      switch settings.authorizationStatus {
      case .authorized, .provisional:
        granted = true
      default:
        granted = false
      }
      DispatchQueue.main.async {
        result([
          "battery": "notApplicable",
          "fullScreenIntent": "notApplicable",
          "notification": granted ? "granted" : "denied",
          "overlay": "notApplicable"
        ])
      }
    }
  }

  private func openNotificationSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }

  private func openCallReadinessSetting(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
          values["kind"] as? String == "notification",
          let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }

  private func handleCallKitReport(_ arguments: Any?, incoming: Bool, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
          let callId = values["callId"] as? String,
          let peerName = values["peerName"] as? String,
          !callId.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Call arguments are missing", details: nil))
      return
    }
    let hasVideo = values["hasVideo"] as? Bool ?? false
    let redactIdentity = values["redactIdentity"] as? Bool ?? true
    let systemPeerName = redactIdentity ? "Elçim araması" : String(peerName.prefix(80))
    if incoming {
      callIntegration.reportIncoming(callId: callId, peerName: systemPeerName, hasVideo: hasVideo) { error in
        if let error = error {
          result(FlutterError(code: "CALLKIT_INCOMING_FAILED", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    } else {
      callIntegration.reportOutgoing(callId: callId, peerName: systemPeerName, hasVideo: hasVideo) { error in
        if let error = error {
          let nativeError = error as NSError
          result(FlutterError(
            code: "CALLKIT_OUTGOING_FAILED",
            message: error.localizedDescription,
            details: ["domain": nativeError.domain, "code": nativeError.code]
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private func handleCallKitState(_ arguments: Any?, active: Bool, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
          let callId = values["callId"] as? String,
          !callId.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "callId is missing", details: nil))
      return
    }
    if active {
      callIntegration.setActive(callId: callId)
      result(nil)
    } else {
      callIntegration.end(callId: callId) { error in
        if let error = error {
          result(FlutterError(code: "CALLKIT_END_FAILED", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }

  private func requestContactsPermission(result: @escaping FlutterResult) {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if SecureChatContactsAccess.isReadable(status) {
      result(true)
      return
    }
    if status == .denied || status == .restricted {
      result(false)
      return
    }
    CNContactStore().requestAccess(for: .contacts) { granted, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "CONTACTS_PERMISSION_FAILED", message: error.localizedDescription, details: nil))
        } else {
          result(granted)
        }
      }
    }
  }

  private func readContacts(result: @escaping FlutterResult) {
    guard SecureChatContactsAccess.isReadable(CNContactStore.authorizationStatus(for: .contacts)) else {
      result(FlutterError(code: "PERMISSION_DENIED", message: "Contacts permission not granted", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let request = CNContactFetchRequest(keysToFetch: SecureChatContactsAccess.keysToFetch)
        request.sortOrder = .userDefault
        var records: [[String: Any]] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
          let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
          for phone in contact.phoneNumbers {
            records.append([
              "displayName": name,
              "phoneNumber": phone.value.stringValue,
              "avatarUri": NSNull()
            ])
          }
        }
        DispatchQueue.main.async { result(records) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "CONTACTS_READ_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func localVideoThumbnail(_ arguments: Any?, result: @escaping FlutterResult) {
    // Fail closed before opening a file or allocating a media decoder.
    guard let values = arguments as? [String: Any],
          let isViewOnce = values["isViewOnce"] as? Bool, !isViewOnce,
          let path = values["path"] as? String, !path.isEmpty,
          videoThumbnailQueue.operationCount < 24 else {
      result(nil)
      return
    }
    let maxSize = max(1, min(320, (values["maxSize"] as? NSNumber)?.intValue ?? 320))
    videoThumbnailQueue.addOperation {
      let data: Data? = autoreleasepool {
        guard let url = SecureChatPrivateFilePolicy.validatedURL(path: path) else { return nil }
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
          .appendingPathComponent("Library/Application Support/media", isDirectory: true)
          .standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: CGFloat(maxSize), height: CGFloat(maxSize))
        defer {
          generator.cancelAllCGImageGeneration()
          asset.cancelLoading()
        }
        do {
          let frame = try generator.copyCGImage(at: .zero, actualTime: nil)
          return UIImage(cgImage: frame).jpegData(compressionQuality: 0.8)
        } catch {
          return nil
        }
      }
      DispatchQueue.main.async {
        result(data.map { FlutterStandardTypedData(bytes: $0) })
      }
    }
  }

  private func openLocalFile(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let url = validatedMediaURL(arguments, result: result) else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let presenter = self.topViewController() else {
        result(FlutterError(code: "NO_PRESENTER", message: "File viewer is unavailable", details: nil))
        return
      }
      let controller = UIDocumentInteractionController(url: url)
      self.documentController = controller
      if controller.presentPreview(animated: true) ||
          controller.presentOpenInMenu(from: presenter.view.bounds, in: presenter.view, animated: true) {
        result(nil)
      } else {
        result(FlutterError(code: "FILE_OPEN_FAILED", message: "No application can open this file", details: nil))
      }
    }
  }

  private func shareLocalFile(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let url = validatedMediaURL(arguments, result: result) else { return }
    DispatchQueue.main.async { [weak self] in
      guard let presenter = self?.topViewController() else {
        result(FlutterError(code: "NO_PRESENTER", message: "Share sheet is unavailable", details: nil))
        return
      }
      let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 1, height: 1)
      }
      presenter.present(controller, animated: true) { result(nil) }
    }
  }

  private func validatedMediaURL(_ arguments: Any?, result: FlutterResult) -> URL? {
    guard let values = arguments as? [String: Any],
          let path = values["path"] as? String,
          !path.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "File path is missing", details: nil))
      return nil
    }
    guard let url = SecureChatPrivateFilePolicy.validatedURL(path: path) else {
      result(FlutterError(
        code: "FILE_NOT_ALLOWED",
        message: "Only retained media and local redacted diagnostics may leave private app storage",
        details: nil
      ))
      return nil
    }
    return url
  }

  private func topViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
    var current = root
    while let presented = current.presentedViewController { current = presented }
    if let navigation = current as? UINavigationController { return navigation.visibleViewController ?? navigation }
    if let tabs = current as? UITabBarController { return tabs.selectedViewController ?? tabs }
    return current
  }

  @objc private func userDidTakeScreenshot() {
    DispatchQueue.main.async { [weak self] in
      guard let presenter = self?.topViewController(),
            !(presenter.presentedViewController is UIAlertController) else { return }
      let warning = UIAlertController(
        title: "Ekran görüntüsü algılandı",
        message: "iOS ekran görüntüsünü teknik olarak engellemez. Görüntü cihazınızdan çıkmadan önce hassas içerik barındırmadığından emin olun.",
        preferredStyle: .alert
      )
      warning.addAction(UIAlertAction(title: "Tamam", style: .default))
      presenter.present(warning, animated: true)
    }
  }

  private func installPrivacyOverlayHooks() {
    guard !privacyOverlayHooksInstalled else { return }
    privacyOverlayHooksInstalled = true
    NotificationCenter.default.addObserver(
      forName: UIScene.willDeactivateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.showPrivacyOverlay()
    }
    NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.hidePrivacyOverlay()
    }
  }

  private func showPrivacyOverlay() {
    guard privacyOverlay == nil,
          let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(overlay)
    privacyOverlay = overlay
  }

  private func hidePrivacyOverlay() {
    privacyOverlay?.removeFromSuperview()
    privacyOverlay = nil
  }
}

/// The Dart layer stores sessions, keys, databases, media and redacted crash
/// reports below Application Support. Native open/share operations must never
/// turn a compromised or malformed Dart path into an exfiltration primitive.
enum SecureChatPrivateFilePolicy {
  private static let allowedRelativeRoots = [
    "Library/Application Support/media",
    "Library/Application Support/crash_logs"
  ]

  static func validatedURL(
    path: String,
    homeURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
    fileManager: FileManager = .default
  ) -> URL? {
    let home = homeURL.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = URL(fileURLWithPath: path)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let allowed = allowedRelativeRoots
      .map { home.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
      .contains { root in
        candidate.path.hasPrefix(root.path + "/")
      }
    guard allowed else { return nil }

    var isDirectory: ObjCBool = false
    let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey])
    guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
          !isDirectory.boolValue,
          values?.isRegularFile == true else {
      return nil
    }
    return candidate
  }
}

final class SecureChatCallTonePlayer: NSObject, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?

  func startRingback() -> Bool {
    play(resource: "elcim_ringback", loops: -1)
  }

  func playCue(_ cue: String) -> Bool {
    switch cue {
    case "connected":
      return play(resource: "elcim_call_connected", loops: 0)
    case "ended":
      return play(resource: "elcim_call_ended", loops: 0)
    default:
      return false
    }
  }

  func stop() {
    player?.stop()
    player = nil
  }

  private func play(resource: String, loops: Int) -> Bool {
    stop()
    guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else {
      return false
    }
    do {
      let next = try AVAudioPlayer(contentsOf: url)
      next.delegate = self
      next.numberOfLoops = loops
      next.volume = 0.9
      next.prepareToPlay()
      guard next.play() else { return false }
      player = next
      return true
    } catch {
      return false
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if self.player === player { self.player = nil }
  }
}

final class SecureChatProximityController {
  private let setMonitoring: (Bool) -> Void
  private let isReceiver: () -> Bool
  private var calls: [UUID: Bool] = [:]
  private var audioActive = false
  private var enabled = false

  init(
    setMonitoring: @escaping (Bool) -> Void = { UIDevice.current.isProximityMonitoringEnabled = $0 },
    isReceiver: @escaping () -> Bool = {
      AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInReceiver }
    }
  ) {
    self.setMonitoring = setMonitoring
    self.isReceiver = isReceiver
  }

  func start(_ uuid: UUID, hasVideo: Bool) {
    calls[uuid] = hasVideo
    refresh()
  }

  func end(_ uuid: UUID) {
    calls.removeValue(forKey: uuid)
    refresh()
  }

  func setAudioActive(_ active: Bool) {
    audioActive = active
    refresh()
  }

  func refresh() {
    let next = audioActive && calls.values.contains(false) &&
      !calls.values.contains(true) && isReceiver()
    guard next != enabled else { return }
    setMonitoring(next)
    enabled = next
  }

  func reset() {
    calls.removeAll()
    audioActive = false
    refresh()
  }
}

final class SecureChatCallKitIntegration: NSObject, CXProviderDelegate {
  typealias TransactionRequester = (CXTransaction, @escaping (Error?) -> Void) -> Void

  var onAction: ((String, String) -> Void)?
  private var provider: CXProvider?
  private let requestTransaction: TransactionRequester
  private var uuidByCallId: [String: UUID] = [:]
  private var callIdByUuid: [UUID: String] = [:]
  private var answerCompletions: [UUID: (Error?) -> Void] = [:]
  private var videoByUuid: [UUID: Bool] = [:]
  private let proximity = SecureChatProximityController()
  private var audioRouteObserver: NSObjectProtocol?

  init(requestTransaction: TransactionRequester? = nil) {
    let controller = CXCallController()
    self.requestTransaction = requestTransaction ?? { transaction, completion in
      controller.request(transaction, completion: completion)
    }
    super.init()
    audioRouteObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.proximity.refresh()
    }
  }

  deinit {
    if let observer = audioRouteObserver { NotificationCenter.default.removeObserver(observer) }
    proximity.reset()
  }

  func initialize() {
    guard provider == nil else { return }
    let configuration = CXProviderConfiguration(localizedName: "Elçim")
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 2
    configuration.supportedHandleTypes = [.generic]
    configuration.ringtoneSound = "elcim_bell.wav"
    let value = CXProvider(configuration: configuration)
    value.setDelegate(self, queue: .main)
    provider = value
  }

  func reportIncoming(
    callId: String,
    peerName: String,
    hasVideo: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    initialize()
    let uuid = remember(callId: callId)
    videoByUuid[uuid] = hasVideo
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: peerName)
    update.localizedCallerName = peerName
    update.hasVideo = hasVideo
    provider?.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      DispatchQueue.main.async {
        if error != nil { self?.forget(uuid: uuid) }
        completion(error)
      }
    }
  }

  func reportOutgoing(
    callId: String,
    peerName: String,
    hasVideo: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    initialize()
    let uuid = remember(callId: callId)
    videoByUuid[uuid] = hasVideo
    let handle = CXHandle(type: .generic, value: peerName)
    let action = CXStartCallAction(call: uuid, handle: handle)
    action.isVideo = hasVideo
    requestTransaction(CXTransaction(action: action)) { [weak self] error in
      DispatchQueue.main.async {
        // A rejected start never created a system call. Forget it before Dart
        // runs cleanup, or CXEndCallAction fails with unknownCallUUID as well.
        if error != nil { self?.forget(uuid: uuid) }
        completion(error)
      }
    }
  }

  func setActive(callId: String) {
    guard let uuid = uuidByCallId[callId] else { return }
    provider?.reportOutgoingCall(with: uuid, connectedAt: Date())
  }

  func answer(callId: String, completion: @escaping (Error?) -> Void) {
    guard let uuid = uuidByCallId[callId] else {
      completion(NSError(domain: "SecureChatCallKit", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Incoming call is unavailable"]))
      return
    }
    answerCompletions[uuid] = completion
    requestTransaction(CXTransaction(action: CXAnswerCallAction(call: uuid))) { [weak self] error in
      // Transaction acceptance is not completion of the answer action. Dart
      // starts media only after the provider configures the audio session.
      if let error = error {
        DispatchQueue.main.async { self?.completeAnswer(uuid: uuid, error: error) }
      }
    }
  }

  func end(callId: String, completion: @escaping (Error?) -> Void) {
    guard let uuid = uuidByCallId[callId] else {
      completion(nil)
      return
    }
    requestTransaction(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
      DispatchQueue.main.async {
        let nativeError = error as NSError?
        let alreadyEnded = nativeError?.domain == CXErrorDomainRequestTransaction &&
          nativeError?.code == CXErrorCodeRequestTransactionError.Code.unknownCallUUID.rawValue
        if error == nil || alreadyEnded { self?.forget(uuid: uuid) }
        completion(alreadyEnded ? nil : error)
      }
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    proximity.reset()
    videoByUuid.removeAll()
    for uuid in Array(answerCompletions.keys) {
      completeAnswer(uuid: uuid, error: answerUnavailable())
    }
    uuidByCallId.removeAll()
    callIdByUuid.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard configureCallAudio() else {
      action.fail()
      completeAnswer(uuid: action.callUUID, error: answerUnavailable())
      return
    }
    if let callId = callIdByUuid[action.callUUID] { onAction?("answer", callId) }
    proximity.start(action.callUUID, hasVideo: videoByUuid[action.callUUID] ?? true)
    action.fulfill()
    completeAnswer(uuid: action.callUUID, error: nil)
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    if let answer = action as? CXAnswerCallAction {
      completeAnswer(uuid: answer.callUUID, error: answerUnavailable())
    }
  }

  private func answerUnavailable() -> Error {
    NSError(domain: "SecureChatCallKit", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Call could not be answered"])
  }

  private func completeAnswer(uuid: UUID, error: Error?) {
    answerCompletions.removeValue(forKey: uuid)?(error)
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    if let callId = callIdByUuid[action.callUUID] { onAction?("end", callId) }
    forget(uuid: action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    if let callId = callIdByUuid[action.callUUID] {
      onAction?(action.isMuted ? "mute" : "unmute", callId)
    }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard configureCallAudio() else {
      action.fail()
      if let callId = callIdByUuid[action.callUUID] { onAction?("end", callId) }
      forget(uuid: action.callUUID)
      return
    }
    proximity.start(action.callUUID, hasVideo: action.isVideo)
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
    action.fulfill()
  }

  private func configureCallAudio() -> Bool {
    let audio = RTCAudioSession.sharedInstance()
    audio.lockForConfiguration()
    defer { audio.unlockForConfiguration() }
    do {
      // Configure only; CallKit activates the session at elevated priority.
      try audio.setCategory(.playAndRecord, with: [.allowBluetooth])
      try audio.setMode(.voiceChat)
      return true
    } catch {
      return false
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    proximity.setAudioActive(true)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    proximity.setAudioActive(false)
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
  }

  private func remember(callId: String) -> UUID {
    if let existing = uuidByCallId[callId] { return existing }
    let uuid = UUID()
    uuidByCallId[callId] = uuid
    callIdByUuid[uuid] = callId
    return uuid
  }

  private func forget(uuid: UUID) {
    proximity.end(uuid)
    videoByUuid.removeValue(forKey: uuid)
    completeAnswer(uuid: uuid, error: answerUnavailable())
    guard let callId = callIdByUuid.removeValue(forKey: uuid) else { return }
    uuidByCallId.removeValue(forKey: callId)
  }
}
