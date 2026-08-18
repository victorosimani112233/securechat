import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

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

}
