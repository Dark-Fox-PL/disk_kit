import Foundation
import AppKit
import IOKit
import Darwin
import Security

/// Installer preparation is separate from discovery and Disk Arbitration callbacks.
/// No shell command is accepted from Dart. Elevated commands are assembled here
/// from validated paths, fixed tools, and freshly checked device identities.
enum DiskKitMediaOperations {
  typealias Progress = (String, Int64?, Int64?) -> Void
  static let fatLimit: Int64 = 4_294_967_295

  struct Target {
    let id: String
    let registryID: UInt64
    let size: Int64

    init(info: [String: Any]) throws {
      guard let id = info["id"] as? String,
        id.range(of: "^disk[0-9]+$", options: .regularExpression) != nil,
        info["isWholeDisk"] as? Bool == true else {
        throw DiskKitNativeError(code: "invalid_target", message: "Select a whole disk, not a volume.")
      }
      guard info["isInternal"] as? Bool == false,
        info["busProtocol"] as? String != "Disk Image" else {
        throw DiskKitNativeError(code: "protected_disk", message: "Select positively external physical media.")
      }
      guard info["isWritable"] as? Bool == true,
        let size = (info["sizeBytes"] as? NSNumber)?.int64Value, size > 0 else {
        throw DiskKitNativeError(code: "invalid_target", message: "The target must be writable with a known capacity.")
      }
      self.id = id
      self.size = size
      registryID = try Self.identity(id)
    }

    static func identity(_ id: String) throws -> UInt64 {
      let service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, id))
      guard service != 0 else {
        throw DiskKitNativeError(code: "disk_not_found", message: "The target is no longer attached.")
      }
      defer { IOObjectRelease(service) }
      var identity: UInt64 = 0
      guard IORegistryEntryGetRegistryEntryID(service, &identity) == KERN_SUCCESS else {
        throw DiskKitNativeError(code: "disk_not_found", message: "Cannot identify the attached media.")
      }
      return identity
    }

    func check() throws {
      guard try Self.identity(id) == registryID else {
        throw DiskKitNativeError(code: "target_changed", message: "The selected device was removed or replaced.")
      }
    }
  }

  struct Image {
    let url: URL
    let size: Int64
    let stamp: String
  }

  static func image(_ path: String, extensions: [String]) throws -> Image {
    let url = try DiskKitFileOperations.absoluteURL(path)
    guard extensions.contains(url.pathExtension.lowercased()) else {
      throw DiskKitNativeError(code: "unsupported_image", message: "Select an uncompressed \(extensions.joined(separator: "/")) file.")
    }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
      throw DiskKitNativeError(code: "unsupported_image", message: "The image must be a nonempty regular file.")
    }
    // Check readability using the application's current privileges before elevation.
    let handle = try FileHandle(forReadingFrom: url)
    try handle.close()
    let stamp = try fingerprint(url.path)
    return Image(url: url, size: Int64(size), stamp: stamp)
  }

  static func fingerprint(_ path: String) throws -> String {
    var info = stat()
    guard stat(path, &info) == 0 else {
      throw DiskKitNativeError(code: "io_failed", message: "Cannot inspect the image file.", details: ["errno": errno])
    }
    return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
  }

  static func checkSource(_ image: Image) throws {
    let stamp = try fingerprint(image.url.path)
    guard stamp == image.stamp else {
      throw DiskKitNativeError(code: "source_changed", message: "The source file changed during preparation.")
    }
  }

  /// Reject ordinary optical-only ISO layouts before erasing anything. A hybrid
  /// ISO needs a partition signature as well as its optical filesystem. This is
  /// structural detection, not a claim about boot compatibility with every host.
  static func validateRawImage(_ image: Image, capacity: Int64) throws {
    guard image.size <= capacity, image.size % 512 == 0 else {
      throw DiskKitNativeError(code: "unsupported_image", message: "The image must fit on the disk and have a size divisible by 512 bytes.")
    }
    let file = try FileHandle(forReadingFrom: image.url)
    defer { try? file.close() }
    let header = try file.read(upToCount: 1024) ?? Data()
    let hasMBR = header.count >= 512 && header[510] == 0x55 && header[511] == 0xaa
      && (0..<4).contains { header[446 + $0 * 16 + 4] != 0 }
    let hasGPT = header.count >= 520 && header.subdata(in: 512..<520) == Data("EFI PART".utf8)
    if image.url.pathExtension.lowercased() == "iso", !hasMBR && !hasGPT {
      throw DiskKitNativeError(code: "unsupported_image", message: "This ISO has no USB disk partition layout. Use the dedicated Windows installer operation for Windows ISOs.")
    }
  }

  static func run(_ executable: String, _ arguments: [String], code: String = "media_failed") throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw DiskKitNativeError(code: code,
        message: String(decoding: data.suffix(8192), as: UTF8.self),
        details: ["exitCode": process.terminationStatus, "tool": executable])
    }
    return data
  }

  static func plist(_ executable: String, _ arguments: [String]) throws -> [String: Any] {
    // Keep stderr separate: warning text must not corrupt a plist response.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    // These system plist commands produce small stderr output.
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw DiskKitNativeError(code: "media_failed", message: String(decoding: error, as: UTF8.self))
    }
    guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
      throw DiskKitNativeError(code: "media_failed", message: "Invalid system plist response.")
    }
    return result
  }

  static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }

  /// Use AppleScript's system authorization UI; never collect or retain passwords.
  /// Telemetry is in an exclusively created root-owned directory under sticky
  /// /private/tmp, not in a user-controlled directory that root would follow.
  static func privileged(target: Target, body: (String) -> String, progress: @escaping Progress) throws {
    let telemetry = "/private/tmp/disk-kit-media-" + UUID().uuidString
    let q = quote(telemetry)
    let guardScript = """
      /usr/sbin/ioreg -a -r -c IOMedia -d 1 > \(q)/media.plist
      found=0
      index=0
      while entry=$(/usr/bin/plutil -extract "$index.IORegistryEntryID" raw -o - \(q)/media.plist 2>/dev/null); do
        name=$(/usr/bin/plutil -extract "$index.BSD Name" raw -o - \(q)/media.plist 2>/dev/null || true)
        if [ "$name" = \(quote(target.id)) ] && [ "$entry" = \(quote(String(target.registryID))) ]; then found=1; break; fi
        index=$((index + 1))
      done
      [ "$found" = 1 ] || { echo target_changed; exit 70; }
      /usr/sbin/diskutil info -plist \(quote("/dev/" + target.id)) > \(q)/disk.plist
      [ "$(/usr/bin/plutil -extract Internal raw -o - \(q)/disk.plist)" = false ] || exit 70
      [ "$(/usr/bin/plutil -extract WholeDisk raw -o - \(q)/disk.plist)" = true ] || exit 70
      [ "$(/usr/bin/plutil -extract Writable raw -o - \(q)/disk.plist)" = true ] || exit 70
      [ "$(/usr/bin/plutil -extract TotalSize raw -o - \(q)/disk.plist)" = \(quote(String(target.size))) ] || exit 70
      """
    let shell = """
      set -eu
      /bin/kill -0 \(getpid()) 2>/dev/null || { echo host_unavailable; exit 76; }
      umask 022
      /bin/mkdir -m 755 \(q)
      trap '/bin/rm -rf \(q)' EXIT
      \(guardScript)
      \(body(telemetry))
      """
    let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let script = "do shell script \"" + escaped + "\" with administrator privileges\n"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output
    progress("authorizing", nil, nil)
    try process.run()
    input.fileHandleForWriting.write(Data(script.utf8))
    try input.fileHandleForWriting.close()
    var lastStage = ""
    while process.isRunning {
      let reportedStage = (try? String(contentsOfFile: telemetry + "/stage", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
      let stage = ["writing", "formatting", "syncing", "verifying"].contains(reportedStage ?? "")
        ? reportedStage! : (lastStage.isEmpty ? "authorizing" : lastStage)
      if stage != lastStage {
        progress(stage, nil, nil)
        lastStage = stage
      }
      Thread.sleep(forTimeInterval: 0.2)
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let text = String(decoding: data.suffix(8192), as: UTF8.self)
      let code = text.contains("(-128)") ? "authorization_cancelled"
        : text.contains("target_changed") ? "target_changed"
        : text.contains("verification_failed") ? "verification_failed"
        : text.contains("source_changed") ? "source_changed"
        : text.contains("Operation not permitted") || text.contains("Permission denied") ? "permission_denied" : "media_failed"
      let message = code == "permission_denied"
        ? "macOS denied disk access even after administrator authorization. Check the host app's Files and Folders / Full Disk Access settings, restart it, and retry. " + text
        : text
      throw DiskKitNativeError(code: code, message: message,
        details: ["exitCode": process.terminationStatus])
    }
  }

  static func writeImage(_ image: Image, target: Target, verify: Bool,
    device: FileHandle, progress: @escaping Progress) throws {
    try target.check()
    try checkSource(image)
    let source = try FileHandle(forReadingFrom: image.url)
    defer { try? source.close() }
    let output = device
    try target.check()
    try checkSource(image)
    var written: Int64 = 0
    progress("writing", 0, image.size)
    while written < image.size {
      try target.check()
      let bytes = try source.read(upToCount: Int(min(4 * 1024 * 1024, image.size - written))) ?? Data()
      guard !bytes.isEmpty else {
        throw DiskKitNativeError(code: "source_changed", message: "Unexpected end of image.")
      }
      try output.write(contentsOf: bytes)
      written += Int64(bytes.count)
      progress("writing", written, image.size)
    }
    progress("syncing", nil, nil)
    if fsync(output.fileDescriptor) < 0 {
      if errno == ENOTSUP || errno == EINVAL || errno == ENOTTY { Darwin.sync() }
      else { throw DiskKitNativeError(code: "io_failed", message: "Cannot flush the raw device.", details: ["errno": errno]) }
    }
    // F_FULLFSYNC is not supported by every raw device; fsync/system sync runs first.
    if fcntl(output.fileDescriptor, F_FULLFSYNC) < 0 && errno != ENOTSUP && errno != EINVAL && errno != ENOTTY {
      throw DiskKitNativeError(code: "media_failed", message: "Cannot flush the target write cache.")
    }
    if verify {
      try source.seek(toOffset: 0)
      try output.seek(toOffset: 0)
      try compare(source, output, bytes: image.size, check: target.check, progress: progress)
    }
    try checkSource(image)
    try target.check()
  }

  /// Receives exactly one descriptor from Apple's authopen over a Unix socket.
  /// It authorizes only read/write opening of this existing device, never file
  /// creation, truncation, arbitrary shell execution, or changing node ownership.
  static func openDevice(_ target: Target, elevate: Bool, progress: Progress) throws -> FileHandle {
    let path = "/dev/r" + target.id
    try target.check()
    let direct = Darwin.open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    if direct >= 0 { return try checkedDevice(direct, path: path, target: target) }
    guard elevate else {
      throw DiskKitNativeError(code: "permission_denied", message: "Raw disk access was denied. Enable allowElevation and check the host application's macOS disk privacy permissions.", details: ["errno": errno])
    }
    progress("authorizing", nil, nil)
    DispatchQueue.main.sync {
      if #available(macOS 14.0, *) { NSApplication.shared.activate() }
      else { NSApplication.shared.activate(ignoringOtherApps: true) }
    }
    var sockets: [Int32] = [-1, -1]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
      throw DiskKitNativeError(code: "io_failed", message: "Cannot create the authopen descriptor socket.", details: ["errno": errno])
    }
    _ = fcntl(sockets[0], F_SETFD, FD_CLOEXEC)
    _ = fcntl(sockets[1], F_SETFD, FD_CLOEXEC)
    let receive = FileHandle(fileDescriptor: sockets[0], closeOnDealloc: true)
    let send = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
    defer { try? receive.close(); try? send.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/libexec/authopen")
    process.arguments = ["-stdoutpipe", "-o", String(O_RDWR), path]
    let errors = Pipe()
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = send
    process.standardError = errors
    try target.check()
    try process.run()
    // Close the parent's copy of the sending endpoint, so EOF is observable if
    // authopen fails. Foundation duplicates the child's stdout during launch.
    try send.close()
    let descriptor = receiveDescriptor(receive.fileDescriptor)
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, descriptor >= 0 else {
      if descriptor >= 0 { Darwin.close(descriptor) }
      let errorText = String(decoding: errorData.suffix(8192), as: UTF8.self)
      let cancelled = errorText.contains(String(errAuthorizationCanceled))
        || errorText.localizedCaseInsensitiveContains("cancel")
      throw DiskKitNativeError(code: cancelled ? "authorization_cancelled" : "permission_denied",
        message: "macOS denied raw-device access. Check the host app's Files and Folders / Full Disk Access permissions, restart it, and retry. " + String(decoding: errorData.suffix(8192), as: UTF8.self),
        details: ["exitCode": process.terminationStatus])
    }
    return try checkedDevice(descriptor, path: path, target: target)
  }

  static func checkedDevice(_ descriptor: Int32, path: String, target: Target) throws -> FileHandle {
    do {
      try target.check()
      var opened = stat()
      var current = stat()
      guard fstat(descriptor, &opened) == 0, stat(path, &current) == 0,
        opened.st_mode & S_IFMT == S_IFCHR, opened.st_rdev == current.st_rdev else {
        throw DiskKitNativeError(code: "target_changed", message: "The authorized descriptor is not the selected raw device.")
      }
      _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
      return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    } catch {
      Darwin.close(descriptor)
      throw error
    }
  }

  /// Darwin uses 32-bit alignment for CMSG_DATA/CMSG_LEN (sys/socket.h).
  /// authopen sends one SCM_RIGHTS record with exactly one int descriptor.
  static func receiveDescriptor(_ socket: Int32) -> Int32 {
    let headerSize = (MemoryLayout<cmsghdr>.size + 3) & ~3
    let controlSize = headerSize + MemoryLayout<Int32>.size
    let control = UnsafeMutableRawPointer.allocate(byteCount: controlSize, alignment: MemoryLayout<cmsghdr>.alignment)
    defer { control.deallocate() }
    control.initializeMemory(as: UInt8.self, repeating: 0, count: controlSize)
    var payload: UInt8 = 0
    return withUnsafeMutablePointer(to: &payload) { bytes in
      var vector = iovec(iov_base: UnsafeMutableRawPointer(bytes), iov_len: 1)
      return withUnsafeMutablePointer(to: &vector) { vectors in
        var message = msghdr()
        message.msg_iov = vectors
        message.msg_iovlen = 1
        message.msg_control = control
        message.msg_controllen = socklen_t(controlSize)
        var count: Int
        repeat { count = recvmsg(socket, &message, 0) } while count < 0 && errno == EINTR
        guard count > 0, message.msg_controllen >= controlSize,
          message.msg_flags & MSG_CTRUNC == 0 else { return -1 }
        let header = control.load(as: cmsghdr.self)
        guard header.cmsg_level == SOL_SOCKET, header.cmsg_type == SCM_RIGHTS,
          header.cmsg_len == controlSize else { return -1 }
        return control.advanced(by: headerSize).load(as: Int32.self)
      }
    }
  }

  static func compare(_ source: FileHandle, _ destination: FileHandle, bytes: Int64,
    check: () throws -> Void, progress: Progress, offset: Int64 = 0, total: Int64? = nil) throws {
    var read: Int64 = 0
    progress("verifying", offset, total ?? bytes)
    while read < bytes {
      try check()
      let count = Int(min(4 * 1024 * 1024, bytes - read))
      let a = try source.read(upToCount: count) ?? Data()
      var b = Data()
      while b.count < a.count {
        let chunk = try destination.read(upToCount: a.count - b.count) ?? Data()
        if chunk.isEmpty { break }
        b.append(chunk)
      }
      guard !a.isEmpty, a == b else {
        throw DiskKitNativeError(code: "verification_failed", message: "Destination data differs from the source.")
      }
      read += Int64(a.count)
      progress("verifying", offset + read, total ?? bytes)
    }
  }

  struct WindowsFile {
    let url: URL
    let relative: String
    let size: Int64
    let directory: Bool
  }

  static func mountedISO(_ image: Image, at mount: URL) throws {
    _ = try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, image.url.path], code: "unsupported_image")
  }

  static func windowsFiles(_ root: URL) throws -> [WindowsFile] {
    let root = try DiskKitFileOperations.absoluteURL(root.path)
    var enumerationFailure: Error?
    guard let enumerator = FileManager.default.enumerator(at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
      errorHandler: { _, error in enumerationFailure = error; return false }) else {
      throw DiskKitNativeError(code: "unsupported_image", message: "Cannot enumerate the mounted ISO.")
    }
    var files: [WindowsFile] = []
    var folded = Set<String>()
    for case let url as URL in enumerator {
      let value = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard value.isSymbolicLink != true, value.isDirectory == true || value.isRegularFile == true else {
        throw DiskKitNativeError(code: "unsupported_image", message: "The Windows ISO contains unsupported special files or symlinks.")
      }
      let relative = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
      guard folded.insert(relative.lowercased()).inserted,
        !relative.split(separator: "/").contains(where: { component in
          component.contains(where: { "\\:*?\"<>|".contains($0) }) || component.hasSuffix(".") || component.hasSuffix(" ")
        }) else {
        throw DiskKitNativeError(code: "unsupported_image", message: "The ISO contains names incompatible with FAT32.")
      }
      let size = Int64(value.fileSize ?? 0)
      if size > fatLimit && relative.lowercased() != "sources/install.wim" {
        throw DiskKitNativeError(code: "unsupported_image", message: "FAT32 cannot hold \(relative). Only sources/install.wim can be split.")
      }
      files.append(WindowsFile(url: url, relative: relative, size: size, directory: value.isDirectory == true))
    }
    if let failure = enumerationFailure { throw failure }
    let paths = Set(files.filter { !$0.directory && $0.size > 0 }.map { $0.relative.lowercased() })
    guard paths.contains("sources/boot.wim"), paths.contains("sources/install.wim") || paths.contains("sources/install.esd") || paths.contains("sources/install.swm"),
      ["efi/boot/bootx64.efi", "efi/boot/bootaa64.efi", "efi/boot/bootia32.efi"].contains(where: paths.contains) else {
      throw DiskKitNativeError(code: "unsupported_image", message: "Select a Windows setup ISO with sources/boot.wim and a UEFI bootloader.")
    }
    return files.sorted { $0.relative < $1.relative }
  }

  static func wimlib(_ path: String?) throws -> String {
    let candidates = path.map { [$0] } ?? ["/opt/homebrew/bin/wimlib-imagex", "/usr/local/bin/wimlib-imagex"]
    for candidate in candidates {
      let resolved = try DiskKitFileOperations.absoluteURL(candidate)
      if FileManager.default.isExecutableFile(atPath: resolved.path) {
        _ = try run(resolved.path, ["--version"], code: "dependency_missing")
        return resolved.path
      }
    }
    throw DiskKitNativeError(code: "dependency_missing", message: "Install wimlib (brew install wimlib) or supply wimlibPath before preparing this oversized WIM.")
  }

  static func format(_ target: Target, fs: String, name: String, scheme: String = "gpt", progress: Progress) throws -> URL {
    try target.check()
    progress("formatting", nil, nil)
    try DiskKitFileOperations.format(arguments: DiskKitFileOperations.formatArguments(
      diskId: target.id, fileSystem: fs, volumeName: name, scheme: scheme))
    try target.check()
    let layout = try plist("/usr/sbin/diskutil", ["list", "-plist", "/dev/" + target.id])
    let disks = layout["AllDisksAndPartitions"] as? [[String: Any]] ?? []
    let partitions = disks.first?["Partitions"] as? [[String: Any]] ?? []
    for partition in partitions {
      guard let id = partition["DeviceIdentifier"] as? String,
        ["Microsoft Basic Data", "DOS_FAT_32", "Windows_FAT_32", "Apple_HFS"].contains(partition["Content"] as? String ?? "") else { continue }
      let info = try plist("/usr/sbin/diskutil", ["info", "-plist", "/dev/" + id])
      if info["ParentWholeDisk"] as? String == target.id, info["VolumeName"] as? String == name,
        let path = info["MountPoint"] as? String {
        return URL(fileURLWithPath: path)
      }
    }
    throw DiskKitNativeError(code: "volume_not_mounted", message: "The newly formatted data volume did not mount.")
  }

  static func createWindows(_ image: Image, target: Target, wimlibPath: String?, verify: Bool,
    progress: @escaping Progress) throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("disk-kit-iso-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: temporary) }
    let mount = temporary.appendingPathComponent("iso")
    try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
    try mountedISO(image, at: mount)
    // Never force-detach if a process is still using the mounted image.
    defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
    let files = try windowsFiles(mount)
    let largeWIM = files.first { !$0.directory && $0.size > fatLimit }
    let tool = try largeWIM.map { _ in try wimlib(wimlibPath) }
    let total = files.filter { !$0.directory }.reduce(Int64(0)) { $0 + $1.size }
    // Leave space for FAT metadata, GPT/EFI, and split-WIM overhead.
    guard total + max(512 * 1024 * 1024, total / 20) < target.size else {
      throw DiskKitNativeError(code: "image_too_large", message: "The installation files and filesystem overhead do not fit on this disk.")
    }
    try checkSource(image)
    // Split before erasure. Validate FAT32-sized parts and optional WIM integrity
    // while the original USB data still exists. Requires local temporary space.
    var splitFiles: [URL] = []
    if let largeWIM = largeWIM, let tool = tool {
      guard !files.contains(where: { $0.relative.lowercased().hasPrefix("sources/install") && $0.url.pathExtension.lowercased() == "swm" }) else {
        throw DiskKitNativeError(code: "unsupported_image", message: "The ISO already contains conflicting split WIM files.")
      }
      progress("splitting", nil, nil)
      let destination = temporary.appendingPathComponent("install.swm")
      _ = try run(tool, ["split", largeWIM.url.path, destination.path, "3800"], code: "split_failed")
      splitFiles = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.fileSizeKey])
        .filter { $0.pathExtension.lowercased() == "swm" }.sorted { $0.path < $1.path }
      guard !splitFiles.isEmpty else { throw DiskKitNativeError(code: "split_failed", message: "No split WIM files were created.") }
      for file in splitFiles {
        guard Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= fatLimit else {
          throw DiskKitNativeError(code: "split_failed", message: "A WIM resource could not be split below FAT32's size limit.")
        }
      }
      if verify { _ = try run(tool, ["verify", destination.path, "--ref=" + temporary.appendingPathComponent("install*.swm").path], code: "verification_failed") }
    }
    var payload = files.filter { $0.relative != largeWIM?.relative }
    if let largeWIM = largeWIM {
      let parent = (largeWIM.relative as NSString).deletingLastPathComponent
      payload += try splitFiles.map { file in
        WindowsFile(url: file, relative: parent + "/" + file.lastPathComponent,
          size: Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), directory: false)
      }
    }
    let copyTotal = payload.filter { !$0.directory }.reduce(Int64(0)) { $0 + $1.size }
    guard copyTotal + max(512 * 1024 * 1024, copyTotal / 20) < target.size else {
      throw DiskKitNativeError(code: "image_too_large", message: "Split installation files do not fit on this disk.")
    }
    try target.check()
    let volume = try format(target, fs: "fat32", name: "WINDOWS", scheme: "mbr", progress: progress)
    var copied: Int64 = 0
    progress("writing", 0, copyTotal)
    for file in payload.sorted(by: { $0.relative < $1.relative }) {
      try target.check()
      let destination = try DiskKitFileOperations.relativeURL(file.relative, volume: volume)
      if file.directory {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      } else {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = try FileHandle(forReadingFrom: file.url)
        defer { try? source.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
          throw DiskKitNativeError(code: "io_failed", message: "Cannot create an installation file.")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var remaining = file.size
        while remaining > 0 {
          try target.check()
          let bytes = try source.read(upToCount: Int(min(4 * 1024 * 1024, remaining))) ?? Data()
          guard !bytes.isEmpty else { throw DiskKitNativeError(code: "source_changed", message: "Unexpected end of installation file.") }
          try output.write(contentsOf: bytes)
          remaining -= Int64(bytes.count)
          copied += Int64(bytes.count)
          progress("writing", copied, copyTotal)
        }
        try output.synchronize()
      }
    }
    progress("syncing", nil, nil)
    _ = try run("/bin/sync", [])
    if verify {
      var checked: Int64 = 0
      for file in payload where !file.directory {
        let destination = try DiskKitFileOperations.relativeURL(file.relative, volume: volume)
        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == file.size else {
          throw DiskKitNativeError(code: "verification_failed", message: "An installation file has the wrong size.")
        }
        let a = try FileHandle(forReadingFrom: file.url)
        let b = try FileHandle(forReadingFrom: destination)
        defer { try? a.close(); try? b.close() }
        try compare(a, b, bytes: file.size, check: target.check, progress: progress, offset: checked, total: copyTotal)
        checked += file.size
      }
    }
    try checkSource(image)
    try target.check()
  }

  static func installer(_ path: String) throws -> URL {
    let app = try DiskKitFileOperations.absoluteURL(path)
    guard app.pathExtension.lowercased() == "app" else {
      throw DiskKitNativeError(code: "unsupported_image", message: "Select a full Install macOS .app, not an ISO or DMG.")
    }
    let tool = try DiskKitFileOperations.absoluteURL(app.appendingPathComponent("Contents/Resources/createinstallmedia").path)
    guard tool.path.hasPrefix(app.path + "/"), FileManager.default.isExecutableFile(atPath: tool.path),
      FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/SharedSupport").path) else {
      throw DiskKitNativeError(code: "unsupported_image", message: "This app does not contain a complete macOS installer.")
    }
    // Verify both the complete installer and the exact executable before granting
    // it root privileges. The elevated shell repeats these checks after the prompt.
    _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=anchor apple", app.path], code: "unsupported_image")
    _ = try run("/usr/bin/codesign", ["--verify", "--strict", "-R=anchor apple", tool.path], code: "unsupported_image")
    return tool
  }

  static func createMacOS(app: URL, tool: URL, target: Target, elevate: Bool,
    progress: @escaping Progress) throws {
    try target.check()
    if !elevate && geteuid() != 0 {
      throw DiskKitNativeError(code: "permission_denied", message: "createinstallmedia requires administrator privileges. Enable allowElevation.")
    }
    _ = try installer(app.path)
    if elevate && geteuid() != 0 {
      // Authorization and Apple signature checks precede the first erase.
      try privileged(target: target, body: { directory in
        let q = quote(directory)
        return """
          /usr/bin/codesign --verify --deep --strict '-R=anchor apple' \(quote(app.path))
          /usr/bin/codesign --verify --strict '-R=anchor apple' \(quote(tool.path))
          echo formatting > \(q)/stage
          /usr/sbin/diskutil eraseDisk JHFS+ DISKKIT GPT \(quote("/dev/" + target.id)) > \(q)/progress 2>&1 || { /usr/bin/tail -c 8192 \(q)/progress; exit 74; }
          /usr/sbin/diskutil list -plist \(quote("/dev/" + target.id)) > \(q)/layout.plist
          index=0
          volume=''
          while content=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions:0:Partitions:$index:Content" \(q)/layout.plist 2>/dev/null); do
            if [ "$content" = Apple_HFS ]; then
              slice=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions:0:Partitions:$index:DeviceIdentifier" \(q)/layout.plist)
              /usr/sbin/diskutil info -plist "/dev/$slice" > \(q)/volume.plist
              [ "$(/usr/libexec/PlistBuddy -c 'Print :ParentWholeDisk' \(q)/volume.plist)" = \(quote(target.id)) ] || { echo target_changed; exit 70; }
              volume=$(/usr/libexec/PlistBuddy -c 'Print :MountPoint' \(q)/volume.plist)
              break
            fi
            index=$((index + 1))
          done
          [ -n "$volume" ] || { echo volume_not_mounted; exit 75; }
          echo writing > \(q)/stage
          \(quote(tool.path)) --volume "$volume" --nointeraction > \(q)/progress 2>&1 || { /usr/bin/tail -c 8192 \(q)/progress; exit 73; }
          echo syncing > \(q)/stage
          /bin/sync
          """
      }, progress: progress)
    } else {
      let volume = try format(target, fs: "hfsPlus", name: "DISKKIT", progress: progress)
      try target.check()
      progress("writing", nil, nil)
      _ = try run(tool.path, ["--volume", volume.path, "--nointeraction"])
      progress("syncing", nil, nil)
      _ = try run("/bin/sync", [])
    }
    try target.check()
  }
}
