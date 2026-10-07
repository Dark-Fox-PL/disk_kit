import Foundation
import Darwin
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

  @objc func testVolumeRenameLabels() throws {
    try DiskKitFileOperations.validateVolumeName("NEW_USB", fileSystem: "exfat")
    try DiskKitFileOperations.validateVolumeName("USB", fileSystem: "msdos")
    XCTAssertThrowsError(try DiskKitFileOperations.validateVolumeName("", fileSystem: "apfs"))
    XCTAssertThrowsError(
      try DiskKitFileOperations.validateVolumeName("BAD/NAME", fileSystem: "exfat"))
    XCTAssertThrowsError(
      try DiskKitFileOperations.validateVolumeName("lowercase", fileSystem: "msdos"))
    XCTAssertThrowsError(
      try DiskKitFileOperations.validateVolumeName(
        String(repeating: "🙂", count: 8), fileSystem: "exfat"))
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
  @objc func testRawImageValidationBeforeDiskAccess() throws {
    let raw = root.appendingPathComponent("test.img")
    try Data(repeating: 0x5a, count: 4096).write(to: raw)
    let image = try DiskKitMediaOperations.image(raw.path, extensions: ["img", "iso"])
    try DiskKitMediaOperations.validateRawImage(image, capacity: 8192)
    XCTAssertThrowsError(try DiskKitMediaOperations.validateRawImage(image, capacity: 512))
    try DiskKitMediaOperations.checkSource(image)
    try Data(repeating: 0, count: 512).write(to: raw)
    XCTAssertThrowsError(try DiskKitMediaOperations.checkSource(image))
    let iso = root.appendingPathComponent("optical.iso")
    var bytes = Data(repeating: 0, count: 4096)
    try bytes.write(to: iso)
    XCTAssertThrowsError(try DiskKitMediaOperations.validateRawImage(
      DiskKitMediaOperations.image(iso.path, extensions: ["iso"]), capacity: 8192))
    bytes[510] = 0x55
    bytes[511] = 0xaa
    bytes[450] = 0x83
    try bytes.write(to: iso)
    try DiskKitMediaOperations.validateRawImage(
      DiskKitMediaOperations.image(iso.path, extensions: ["iso"]), capacity: 8192)
  }

  @objc func testWindowsPreflightAndFATLimits() throws {
    try FileManager.default.createDirectory(at: root.appendingPathComponent("sources"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("efi/boot"), withIntermediateDirectories: true)
    for name in ["sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"] {
      try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
    }
    XCTAssertEqual(try DiskKitMediaOperations.windowsFiles(root).filter { !$0.directory }.count, 3)
    let esd = root.appendingPathComponent("sources/install.esd")
    _ = FileManager.default.createFile(atPath: esd.path, contents: nil)
    let handle = try FileHandle(forWritingTo: esd)
    try handle.truncate(atOffset: UInt64(DiskKitMediaOperations.fatLimit + 1))
    try handle.close()
    XCTAssertThrowsError(try DiskKitMediaOperations.windowsFiles(root))
    try FileManager.default.removeItem(at: esd)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root)
    XCTAssertThrowsError(try DiskKitMediaOperations.windowsFiles(root))
  }

  @objc func testVerificationAndQuoting() throws {
    let source = root.appendingPathComponent("a")
    let destination = root.appendingPathComponent("b")
    try Data("DiskKit".utf8).write(to: source)
    try Data("DiskKit".utf8).write(to: destination)
    let a = try FileHandle(forReadingFrom: source)
    let b = try FileHandle(forReadingFrom: destination)
    defer { try? a.close(); try? b.close() }
    try DiskKitMediaOperations.compare(a, b, bytes: 7, check: {}, progress: { _, _, _ in })
    try Data("DiskBad".utf8).write(to: destination)
    try a.seek(toOffset: 0)
    try b.seek(toOffset: 0)
    XCTAssertThrowsError(try DiskKitMediaOperations.compare(a, b, bytes: 7, check: {}, progress: { _, _, _ in }))
    let value = "a' ; $(echo dangerous) \\ \" end"
    let output = try DiskKitMediaOperations.run("/bin/sh", ["-c", "printf %s " + DiskKitMediaOperations.quote(value)])
    XCTAssertEqual(String(decoding: output, as: UTF8.self), value)
    XCTAssertThrowsError(try DiskKitMediaOperations.installer(source.path))
    XCTAssertThrowsError(try DiskKitMediaOperations.wimlib(root.appendingPathComponent("missing").path))
  }

  @objc func testSocketDescriptorTransfer() throws {
    let file = root.appendingPathComponent("descriptor.txt")
    try Data("native descriptor".utf8).write(to: file)
    let original = Darwin.open(file.path, O_RDONLY)
    XCTAssertGreaterThanOrEqual(original, 0)
    defer { Darwin.close(original) }
    var sockets: [Int32] = [-1, -1]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
    defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }
    let headerSize = (MemoryLayout<cmsghdr>.size + 3) & ~3
    let controlSize = headerSize + MemoryLayout<Int32>.size
    let control = UnsafeMutableRawPointer.allocate(byteCount: controlSize, alignment: MemoryLayout<cmsghdr>.alignment)
    defer { control.deallocate() }
    let header = cmsghdr(cmsg_len: socklen_t(controlSize), cmsg_level: SOL_SOCKET, cmsg_type: SCM_RIGHTS)
    control.storeBytes(of: header, as: cmsghdr.self)
    control.advanced(by: headerSize).storeBytes(of: original, as: Int32.self)
    var byte: UInt8 = 1
    let result = withUnsafeMutablePointer(to: &byte) { bytes in
      var vector = iovec(iov_base: UnsafeMutableRawPointer(bytes), iov_len: 1)
      return withUnsafeMutablePointer(to: &vector) { vectors in
        var message = msghdr()
        message.msg_iov = vectors
        message.msg_iovlen = 1
        message.msg_control = control
        message.msg_controllen = socklen_t(controlSize)
        return sendmsg(sockets[1], &message, 0)
      }
    }
    XCTAssertEqual(result, 1)
    let descriptor = DiskKitMediaOperations.receiveDescriptor(sockets[0])
    XCTAssertGreaterThanOrEqual(descriptor, 0)
    let received = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? received.close() }
    XCTAssertEqual(String(decoding: try received.readToEnd() ?? Data(), as: UTF8.self), "native descriptor")
  }

}

let suite = XCTestSuite(forTestCaseClass: FileOperationsTests.self)
suite.run()
guard let run = suite.testRun, run.executionCount == 11 else {
  fatalError("Expected eleven native tests.")
}
exit(run.totalFailureCount == 0 ? 0 : 1)
