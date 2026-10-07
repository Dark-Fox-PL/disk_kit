import Foundation
import XCTest

final class FileOperationsTests: XCTestCase {
  private var root: URL!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

  @objc func testRecursiveCopyAndNoOverwrite() throws {
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(
      at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
    try Data("DiskKit".utf8).write(to: source.appendingPathComponent("nested/data.txt"))
    let destination = root.appendingPathComponent("copy")
    try DiskKitFileOperations.copy(source: source, destination: destination)
    XCTAssertEqual(
      try Data(contentsOf: destination.appendingPathComponent("nested/data.txt")),
      Data("DiskKit".utf8))
    XCTAssertThrowsError(try DiskKitFileOperations.copy(source: source, destination: destination)) {
      error in
      XCTAssertEqual((error as? DiskKitNativeError)?.code, "destination_exists")
    }
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: source.appendingPathComponent("nested/data.txt").path))
  }

  @objc func testPathsCannotEscapeVolume() throws {
    XCTAssertThrowsError(try DiskKitFileOperations.relativeURL("../escape", volume: root))
    XCTAssertThrowsError(try DiskKitFileOperations.relativeURL("/etc/passwd", volume: root))
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("escape"),
      withDestinationURL: root.deletingLastPathComponent())
    XCTAssertThrowsError(try DiskKitFileOperations.relativeURL("escape/file", volume: root))
    XCTAssertEqual(
      try DiskKitFileOperations.relativeURL("folder/new.txt", volume: root).path,
      root.appendingPathComponent("folder/new.txt").path)
    XCTAssertThrowsError(try DiskKitFileOperations.absoluteURL("relative.txt"))
  }

  @objc func testCannotCopyDirectoryIntoItself() throws {
    XCTAssertThrowsError(
      try DiskKitFileOperations.copy(
        source: root, destination: root.appendingPathComponent("child")))
  }

  @objc func testNestedSymlinksArePreserved() throws {
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: source.appendingPathComponent("link").path, withDestinationPath: "../outside")
    let destination = root.appendingPathComponent("copy")
    try DiskKitFileOperations.copy(source: source, destination: destination)
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(
        atPath: destination.appendingPathComponent("link").path), "../outside")
  }

  @objc func testFormatPlansWithoutExecutingThem() throws {
    XCTAssertEqual(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4s1", fileSystem: "exFat", volumeName: "USB", scheme: nil),
      ["eraseVolume", "ExFAT", "USB", "/dev/disk4s1"])
    XCTAssertEqual(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4", fileSystem: "fat32", volumeName: "USB", scheme: "mbr"),
      ["eraseDisk", "MS-DOS FAT32", "USB", "MBR", "/dev/disk4"])
    XCTAssertEqual(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4", fileSystem: "apfs", volumeName: "USB", scheme: "gpt"),
      ["eraseDisk", "APFS", "USB", "GPT", "/dev/disk4"])
    // A shell metacharacter in a label stays within a single process argument.
    XCTAssertEqual(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4s1", fileSystem: "hfsPlus", volumeName: "a;echo hi", scheme: nil)[2],
      "a;echo hi")
  }

  @objc func testRejectsInvalidFormattingParameters() throws {
    XCTAssertThrowsError(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4;echo", fileSystem: "exFat", volumeName: "USB", scheme: nil))
    XCTAssertThrowsError(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4", fileSystem: "unknown", volumeName: "USB", scheme: nil))
    XCTAssertThrowsError(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4", fileSystem: "apfs", volumeName: "USB", scheme: "mbr"))
    XCTAssertThrowsError(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4", fileSystem: "exFat", volumeName: "../bad", scheme: "gpt"))
    XCTAssertThrowsError(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4", fileSystem: "fat32", volumeName: "lowercase", scheme: "mbr"))
    XCTAssertThrowsError(
      try DiskKitFileOperations.formatArguments(
        diskId: "disk4", fileSystem: "exFat", volumeName: String(repeating: "X", count: 16),
        scheme: "gpt"))
  }
}

let suite = XCTestSuite(forTestCaseClass: FileOperationsTests.self)
suite.run()
guard let run = suite.testRun, run.executionCount == 6 else {
  fatalError("Expected six native tests.")
}
exit(run.totalFailureCount == 0 ? 0 : 1)
