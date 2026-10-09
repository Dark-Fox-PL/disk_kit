import Foundation
import Darwin

struct DiskKitNativeError: Error {
  let code: String
  let message: String
  var details: [String: Any] = [:]
}

/// Filesystem operations kept separate from Flutter and Disk Arbitration.
enum DiskKitFileOperations {
  static func relativeURL(_ path: String, volume: URL) throws -> URL {
    guard !(path as NSString).isAbsolutePath,
      !path.split(separator: "/").contains(".."), !path.contains("\0")
    else {
      throw DiskKitNativeError(
        code: "invalid_path", message: "Use a relative path inside the volume.")
    }
    let root = try absoluteURL(volume.path)
    var target = root
    // Resolve existing parents one at a time. Resolving the final URL alone
    // may leave a symlink unresolved when the destination does not exist yet.
    for component in path.split(separator: "/") where component != "." {
      target = target.appendingPathComponent(String(component)).resolvingSymlinksInPath()
      guard root.path == "/" || target.path == root.path || target.path.hasPrefix(root.path + "/")
      else {
        throw DiskKitNativeError(
          code: "invalid_path", message: "The path escapes the volume through a symlink.")
      }
    }
    return target
  }

  static func absoluteURL(_ path: String) throws -> URL {
    guard (path as NSString).isAbsolutePath, !path.contains("\0") else {
      throw DiskKitNativeError(code: "invalid_path", message: "An absolute local path is required.")
    }
    var resolved = URL(fileURLWithPath: "/")
    for component in URL(fileURLWithPath: path).standardizedFileURL.pathComponents.dropFirst() {
      resolved = resolved.appendingPathComponent(component).resolvingSymlinksInPath()
    }
    return resolved
  }

  /// Check the requested path before resolving a dangling final symlink.
  static func requireNewDestination(_ destination: URL) throws {
    guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
      throw DiskKitNativeError(code: "destination_exists", message: "The destination already exists.")
    }
  }

  /// Foundation directory enumeration suppresses recognized AppleDouble
  /// companions. A file-backup API must enumerate them as literal user files.
  static func directoryEntries(_ directory: URL) throws -> [URL] {
    guard let stream = opendir(directory.path) else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
        userInfo: [NSFilePathErrorKey: directory.path])
    }
    defer { closedir(stream) }
    var entries: [URL] = []
    errno = 0
    while let entry = readdir(stream) {
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
      }
      if name != "." && name != ".." { entries.append(directory.appendingPathComponent(name)) }
      errno = 0
    }
    guard errno == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
        userInfo: [NSFilePathErrorKey: directory.path])
    }
    return entries
  }

  /// Preserve literal companion bytes instead of reserializing the same
  /// metadata into an automatically generated destination AppleDouble file.
  static func hasLiteralCompanion(_ source: URL) -> Bool {
    let companion = source.deletingLastPathComponent()
      .appendingPathComponent("._" + source.lastPathComponent)
    return (try? FileManager.default.attributesOfItem(atPath: companion.path)) != nil
  }

  /// No merge or overwrite. Bounded file workers preserve directory metadata.
  static func copy(source: URL, destination: URL, parallel: Bool = true,
    progress: @escaping (String, Int64, Bool) -> Void = { _, _, _ in }) throws {
    guard (destination.path as NSString).isAbsolutePath, !destination.path.contains("\0") else {
      throw DiskKitNativeError(code: "invalid_path", message: "An absolute local path is required.")
    }
    // Refuse a dangling link too, before resolving its missing target.
    guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
      throw DiskKitNativeError(code: "destination_exists", message: "The destination already exists.")
    }
    let source = try absoluteURL(source.path)
    let destination = try absoluteURL(destination.path)
    guard destination != source, source.path != "/", !destination.path.hasPrefix(source.path + "/")
    else {
      throw DiskKitNativeError(
        code: "invalid_path", message: "The destination cannot be inside the source.")
    }
    guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
      throw DiskKitNativeError(
        code: "destination_exists", message: "The destination already exists.")
    }
    // One disk lease covers the complete copy, including all worker completion.
    // Bound outstanding work rather than queuing the entire drive in memory.
    let state = CopyState()
    let slots = DispatchSemaphore(value: parallel ? 4 : 1)
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "eu.byfox.disk_kit.copy", qos: .userInitiated,
      attributes: .concurrent)
    var directories: [(URL, URL)] = []
    func walk(_ input: URL, _ output: URL) throws {
      try state.check()
      let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
      if attributes[.type] as? FileAttributeType == .typeDirectory {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        directories.append((input, output))
        for child in try directoryEntries(input) {
          try walk(child, output.appendingPathComponent(child.lastPathComponent))
        }
      } else {
        slots.wait()
        do { try state.check() } catch { slots.signal(); throw error }
        group.enter()
        queue.async {
          defer { slots.signal(); group.leave() }
          do {
            try state.check()
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            progress(input.path, bytes, false)
            if attributes[.type] as? FileAttributeType == .typeRegular,
              input.lastPathComponent.hasPrefix("._") || hasLiteralCompanion(input) {
              let flags = copyfile_flags_t(COPYFILE_DATA | COPYFILE_STAT | COPYFILE_EXCL | COPYFILE_NOFOLLOW)
              if copyfile(input.path, output.path, nil, flags) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                  userInfo: [NSFilePathErrorKey: output.path])
              }
            } else {
              try FileManager.default.copyItem(at: input, to: output)
            }
            let copied = try FileManager.default.attributesOfItem(atPath: output.path)
            if attributes[.type] as? FileAttributeType == .typeRegular,
              (copied[.size] as? NSNumber)?.int64Value != bytes {
              throw DiskKitNativeError(code: "io_failed", message: "The copied file size changed.",
                details: ["sourcePath": input.path, "destinationPath": output.path])
            }
            progress(input.path, bytes, true)
          } catch { state.fail(error) }
        }
      }
    }
    do { try walk(source, destination) } catch { state.fail(error) }
    group.wait()
    try state.check()
    // Apply directory metadata after descendants, retaining nested symlinks and
    // FileManager file-copy behavior while permitting independent file I/O.
    for (input, output) in directories.reversed() {
      let flags = copyfile_flags_t(hasLiteralCompanion(input) ? COPYFILE_STAT : COPYFILE_METADATA)
      if copyfile(input.path, output.path, nil, flags) != 0 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
          userInfo: [NSFilePathErrorKey: output.path])
      }
    }
  }

  /// Validates both formatting labels and native filesystem rename requests.
  static func validateVolumeName(_ volumeName: String, fileSystem: String?) throws {
    guard !volumeName.isEmpty,
      !volumeName.contains(where: { "/:\\\0".contains($0) }),
      volumeName.utf16.count <= 255
    else {
      throw DiskKitNativeError(
        code: "invalid_arguments", message: "Invalid volume name.")
    }
    if fileSystem == "exFat" || fileSystem == "exfat", volumeName.utf16.count > 15 {
      throw DiskKitNativeError(
        code: "invalid_arguments", message: "An exFAT label can contain at most 15 UTF-16 units.")
    }
    if fileSystem == "fat32" || fileSystem == "msdos",
      volumeName.range(of: "^[A-Z0-9_ ]{1,11}$", options: .regularExpression) == nil
    {
      throw DiskKitNativeError(
        code: "invalid_arguments",
        message: "Use 1–11 uppercase ASCII letters, digits, underscores, or spaces for FAT32.")
    }
  }

  /// Returns arguments only; this function never launches diskutil.
  static func formatArguments(
    diskId: String, fileSystem: String, volumeName: String, scheme: String?
  ) throws -> [String] {
    guard diskId.range(of: "^disk[0-9]+(s[0-9]+)*$", options: .regularExpression) != nil else {
      throw DiskKitNativeError(code: "invalid_arguments", message: "Invalid BSD disk identifier.")
    }
    let formats = [
      "exFat": "ExFAT", "fat32": "MS-DOS FAT32", "apfs": "APFS", "hfsPlus": "JHFS+",
      "apfsCaseSensitive": "APFSX", "hfsPlusNonJournaled": "HFS+",
      "hfsPlusCaseSensitive": "HFSX", "hfsPlusCaseSensitiveJournaled": "JHFSX",
    ]
    guard let format = formats[fileSystem] else {
      throw DiskKitNativeError(code: "invalid_arguments", message: "Unsupported filesystem.")
    }
    try validateVolumeName(volumeName, fileSystem: fileSystem)
    if let scheme = scheme {
      guard ["gpt", "mbr"].contains(scheme), !(["apfs", "apfsCaseSensitive"].contains(fileSystem) && scheme == "mbr") else {
        throw DiskKitNativeError(
          code: "invalid_arguments", message: "Unsupported partition scheme; APFS requires GPT.")
      }
      return ["eraseDisk", format, volumeName, scheme == "gpt" ? "GPT" : "MBR", "/dev/" + diskId]
    }
    return ["eraseVolume", format, volumeName, "/dev/" + diskId]
  }

  static func format(arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    // Drain before waiting so a full pipe cannot deadlock the subprocess.
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw DiskKitNativeError(
        code: "format_failed",
        message: String(data: data, encoding: .utf8)?.trimmingCharacters(
          in: .whitespacesAndNewlines)
          ?? "diskutil failed.",
        details: ["exitCode": process.terminationStatus]
      )
    }
  }
}

private final class CopyState {
  private let lock = NSLock()
  private var failure: Error?
  func fail(_ error: Error) {
    lock.lock(); defer { lock.unlock() }
    if failure == nil { failure = error }
  }
  func check() throws {
    lock.lock(); defer { lock.unlock() }
    if let error = failure { throw error }
  }
}
