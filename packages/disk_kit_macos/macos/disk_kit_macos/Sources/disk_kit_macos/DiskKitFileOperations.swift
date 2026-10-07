import Foundation

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

  /// No merge or overwrite. FileManager recursively copies directories.
  static func copy(source: URL, destination: URL) throws {
    let source = try absoluteURL(source.path)
    let destination = try absoluteURL(destination.path)
    guard destination != source, source.path != "/", !destination.path.hasPrefix(source.path + "/")
    else {
      throw DiskKitNativeError(
        code: "invalid_path", message: "The destination cannot be inside the source.")
    }
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw DiskKitNativeError(
        code: "destination_exists", message: "The destination already exists.")
    }
    try FileManager.default.copyItem(at: source, to: destination)
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
    let formats = ["exFat": "ExFAT", "fat32": "MS-DOS FAT32", "apfs": "APFS", "hfsPlus": "JHFS+"]
    guard let format = formats[fileSystem] else {
      throw DiskKitNativeError(code: "invalid_arguments", message: "Unsupported filesystem.")
    }
    try validateVolumeName(volumeName, fileSystem: fileSystem)
    if let scheme = scheme {
      guard ["gpt", "mbr"].contains(scheme), !(fileSystem == "apfs" && scheme == "mbr") else {
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
