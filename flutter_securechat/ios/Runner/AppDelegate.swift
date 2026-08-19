import Flutter
import Contacts
import CallKit
import UIKit
import workmanager_apple
import firebase_messaging
import LocalAuthentication
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let maintenanceTask = "com.securechat.app.background.maintenance"
  private static let senderKeyRotationTask = "com.securechat.app.background.sender-key-rotation"
  private let channelName = "com.securechat/native"
  private var privacyOverlay: UIView?
  private var privacyOverlayHooksInstalled = false
  private var documentController: UIDocumentInteractionController?
  private let callIntegration = SecureChatCallKitIntegration()

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
      case "endNativeCall":
        self?.handleCallKitState(call.arguments, active: false, result: result)
      case "authenticateLockedChat":
        self?.authenticateLockedChat(call.arguments, result: result)
      case "getCallReadiness":
        self?.getCallReadiness(result: result)
      case "openCallReadinessSetting":
        self?.openCallReadinessSetting(call.arguments, result: result)
      case "requestContactsPermission":
        self?.requestContactsPermission(result: result)
      case "readContacts":
        self?.readContacts(result: result)
      case "openLocalFile":
        self?.openLocalFile(call.arguments, result: result)
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
          result(FlutterError(code: "CALLKIT_OUTGOING_FAILED", message: error.localizedDescription, details: nil))
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
    if status == .authorized {
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
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
      result(FlutterError(code: "PERMISSION_DENIED", message: "Contacts permission not granted", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let keys: [CNKeyDescriptor] = [
          CNContactGivenNameKey as CNKeyDescriptor,
          CNContactFamilyNameKey as CNKeyDescriptor,
          CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
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

final class SecureChatCallKitIntegration: NSObject, CXProviderDelegate {
  var onAction: ((String, String) -> Void)?
  private var provider: CXProvider?
  private let controller = CXCallController()
  private var uuidByCallId: [String: UUID] = [:]
  private var callIdByUuid: [UUID: String] = [:]

  func initialize() {
    guard provider == nil else { return }
    let configuration = CXProviderConfiguration(localizedName: "Elçim")
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 2
    configuration.supportedHandleTypes = [.generic]
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
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: peerName)
    update.localizedCallerName = peerName
    update.hasVideo = hasVideo
    provider?.reportNewIncomingCall(with: uuid, update: update, completion: completion)
  }

  func reportOutgoing(
    callId: String,
    peerName: String,
    hasVideo: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    initialize()
    let uuid = remember(callId: callId)
    let handle = CXHandle(type: .generic, value: peerName)
    let action = CXStartCallAction(call: uuid, handle: handle)
    action.isVideo = hasVideo
    controller.request(CXTransaction(action: action), completion: completion)
  }

  func setActive(callId: String) {
    guard let uuid = uuidByCallId[callId] else { return }
    provider?.reportOutgoingCall(with: uuid, connectedAt: Date())
  }

  func end(callId: String, completion: @escaping (Error?) -> Void) {
    guard let uuid = uuidByCallId[callId] else {
      completion(nil)
      return
    }
    controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
      if error == nil { self?.forget(uuid: uuid) }
      completion(error)
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    uuidByCallId.removeAll()
    callIdByUuid.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    if let callId = callIdByUuid[action.callUUID] { onAction?("answer", callId) }
    action.fulfill()
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
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
    action.fulfill()
  }

  private func remember(callId: String) -> UUID {
    if let existing = uuidByCallId[callId] { return existing }
    let uuid = UUID()
    uuidByCallId[callId] = uuid
    callIdByUuid[uuid] = callId
    return uuid
  }

  private func forget(uuid: UUID) {
    guard let callId = callIdByUuid.removeValue(forKey: uuid) else { return }
    uuidByCallId.removeValue(forKey: callId)
  }
}
