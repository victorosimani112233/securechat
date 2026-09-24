import Flutter
import CallKit
import Contacts
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testContactsFetchIncludesFormatterDescriptorAndPhoneNumbers() {
    let formatterKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
    XCTAssertTrue(SecureChatContactsAccess.keysToFetch.contains { $0.isEqual(formatterKeys) })
    XCTAssertTrue(SecureChatContactsAccess.keysToFetch.contains {
      $0.isEqual(CNContactPhoneNumbersKey as CNKeyDescriptor)
    })
  }

  func testContactsPermissionSupportsLimitedAccessWithoutBroadeningIt() {
    XCTAssertTrue(SecureChatContactsAccess.isReadable(.authorized))
    XCTAssertFalse(SecureChatContactsAccess.isReadable(.denied))
    XCTAssertFalse(SecureChatContactsAccess.isReadable(.restricted))
    XCTAssertFalse(SecureChatContactsAccess.isReadable(.notDetermined))
    if #available(iOS 18.0, *) {
      XCTAssertTrue(SecureChatContactsAccess.isReadable(.limited))
    }
  }

  private var temporaryHome: URL!

  override func setUpWithError() throws {
    temporaryHome = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let temporaryHome, FileManager.default.fileExists(atPath: temporaryHome.path) {
      try FileManager.default.removeItem(at: temporaryHome)
    }
    temporaryHome = nil
  }

  func testPrivateFilePolicyAllowsOnlyRetainedMediaAndRedactedDiagnostics() throws {
    let media = temporaryHome
      .appendingPathComponent("Library/Application Support/media/received_files/photo.jpg")
    let diagnostics = temporaryHome
      .appendingPathComponent("Library/Application Support/crash_logs/crash_1.json")
    let database = temporaryHome
      .appendingPathComponent("Library/Application Support/securechat.securejson")
    for file in [media, diagnostics, database] {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("fixture".utf8).write(to: file)
    }

    XCTAssertNotNil(SecureChatPrivateFilePolicy.validatedURL(path: media.path, homeURL: temporaryHome))
    XCTAssertNotNil(SecureChatPrivateFilePolicy.validatedURL(path: diagnostics.path, homeURL: temporaryHome))
    XCTAssertNil(SecureChatPrivateFilePolicy.validatedURL(path: database.path, homeURL: temporaryHome))
  }

  func testPrivateFilePolicyRejectsSymlinkEscape() throws {
    let mediaDirectory = temporaryHome
      .appendingPathComponent("Library/Application Support/media", isDirectory: true)
    let secret = temporaryHome
      .appendingPathComponent("Library/Application Support/session.securejson")
    let link = mediaDirectory.appendingPathComponent("shared.json")
    try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
    try Data("secret".utf8).write(to: secret)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

    XCTAssertNil(SecureChatPrivateFilePolicy.validatedURL(path: link.path, homeURL: temporaryHome))
  }

  func testOutgoingCallKitCapabilityIsBundled() {
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    XCTAssertTrue(modes?.contains("voip") == true)
    XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription"))
  }

  @MainActor
  func testRejectedOutgoingCallCanBeCleanedUpAndRetried() async {
    var transactions: [CXTransaction] = []
    let rejected = NSError(
      domain: CXErrorDomainRequestTransaction,
      code: CXErrorCodeRequestTransactionError.Code.unentitled.rawValue
    )
    let calls = SecureChatCallKitIntegration { transaction, completion in
      transactions.append(transaction)
      completion(transactions.count == 1 ? rejected : nil)
    }

    let error = await reportOutgoing(calls)
    XCTAssertEqual((error as NSError?)?.code, rejected.code)
    let cleanupError = await end(calls)
    XCTAssertNil(cleanupError)
    XCTAssertEqual(transactions.count, 1, "Rejected calls must not submit an end transaction")

    let retryError = await reportOutgoing(calls)
    XCTAssertNil(retryError)
    let first = transactions[0].actions[0] as! CXStartCallAction
    let retry = transactions[1].actions[0] as! CXStartCallAction
    XCTAssertNotEqual(first.callUUID, retry.callUUID)
    let endError = await end(calls)
    XCTAssertNil(endError)
    let endAction = transactions[2].actions[0] as! CXEndCallAction
    XCTAssertEqual(endAction.callUUID, retry.callUUID)
  }

  @MainActor
  func testInAppAnswerUsesAnswerTransactionAndPropagatesRejection() async {
    var transactions: [CXTransaction] = []
    let rejected = NSError(domain: "test.answer", code: 7)
    let calls = SecureChatCallKitIntegration { transaction, completion in
      transactions.append(transaction)
      completion(transaction.actions[0] is CXAnswerCallAction ? rejected : nil)
    }
    let startError = await reportOutgoing(calls)
    XCTAssertNil(startError)
    let error: Error? = await withCheckedContinuation { continuation in
      calls.answer(callId: "test-call") { continuation.resume(returning: $0) }
    }
    XCTAssertEqual((error as NSError?)?.domain, rejected.domain)
    XCTAssertTrue(transactions[1].actions[0] is CXAnswerCallAction)
    let first = transactions[0].actions[0] as! CXStartCallAction
    let answer = transactions[1].actions[0] as! CXAnswerCallAction
    XCTAssertEqual(first.callUUID, answer.callUUID)
  }

  @MainActor
  func testAnswerOfUnknownCallFailsWithoutTransaction() async {
    let calls = SecureChatCallKitIntegration { _, _ in
      XCTFail("Unknown call must not create a system transaction")
    }
    let error: Error? = await withCheckedContinuation { continuation in
      calls.answer(callId: "missing") { continuation.resume(returning: $0) }
    }
    XCTAssertNotNil(error)
  }

  @MainActor
  func testEndingAlreadyRemovedSystemCallIsIdempotent() async {
    var requests = 0
    let calls = SecureChatCallKitIntegration { transaction, completion in
      requests += 1
      completion(transaction.actions[0] is CXEndCallAction ? NSError(
        domain: CXErrorDomainRequestTransaction,
        code: CXErrorCodeRequestTransactionError.Code.unknownCallUUID.rawValue
      ) : nil)
    }
    let startError = await reportOutgoing(calls)
    XCTAssertNil(startError)
    let endError = await end(calls)
    XCTAssertNil(endError)
    let repeatedEndError = await end(calls)
    XCTAssertNil(repeatedEndError)
    XCTAssertEqual(requests, 2)
  }

  @MainActor
  func testEndPreservesOtherNativeFailuresForDiagnosisAndRetry() async {
    var endRequests = 0
    let failure = NSError(
      domain: "test.other.domain",
      code: CXErrorCodeRequestTransactionError.Code.unknownCallUUID.rawValue
    )
    let calls = SecureChatCallKitIntegration { transaction, completion in
      if transaction.actions[0] is CXEndCallAction {
        endRequests += 1
        completion(endRequests == 1 ? failure : nil)
      } else {
        completion(nil)
      }
    }
    let startError = await reportOutgoing(calls)
    XCTAssertNil(startError)
    let firstEndError = await end(calls)
    XCTAssertEqual((firstEndError as NSError?)?.domain, failure.domain)
    let retryError = await end(calls)
    XCTAssertNil(retryError)
    XCTAssertEqual(endRequests, 2)
  }

  @MainActor
  private func reportOutgoing(_ calls: SecureChatCallKitIntegration) async -> Error? {
    await withCheckedContinuation { continuation in
      calls.reportOutgoing(callId: "test-call", peerName: "Private", hasVideo: false) { error in
        continuation.resume(returning: error)
      }
    }
  }

  @MainActor
  private func end(_ calls: SecureChatCallKitIntegration) async -> Error? {
    await withCheckedContinuation { continuation in
      calls.end(callId: "test-call") { error in
        continuation.resume(returning: error)
      }
    }
  }

}
