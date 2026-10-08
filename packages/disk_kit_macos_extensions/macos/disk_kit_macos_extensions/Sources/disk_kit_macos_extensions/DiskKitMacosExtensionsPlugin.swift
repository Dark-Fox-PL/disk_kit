import Cocoa
import DiskArbitration
import FlutterMacOS
import IOKit

private struct ExtensionFailure: Error {
  let code: String
  let message: String
  var flutter: FlutterError { FlutterError(code: code, message: message, details: nil) }
}

private final class ExtensionCallback {
  let completion: (DADisk, DADissenter?) -> Void
  init(_ completion: @escaping (DADisk, DADissenter?) -> Void) { self.completion = completion }
}

private let extensionCompleted: DADiskUnmountCallback = { disk, dissenter, context in
  guard let context = context else { return }
  Unmanaged<ExtensionCallback>.fromOpaque(context).takeRetainedValue().completion(disk, dissenter)
}

private let extensionKeepClaim: DADiskClaimReleaseCallback = { _, _ in
  Unmanaged.passRetained(DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy),
    "DiskKit extensions are formatting this disk." as CFString))
}

private let extensionMountApproval: DADiskMountApprovalCallback = { disk, context in
  guard let context = context, let whole = DADiskCopyWholeDisk(disk),
    let name = DADiskGetBSDName(whole) else { return nil }
  let plugin = Unmanaged<DiskKitMacosExtensionsPlugin>.fromOpaque(context).takeUnretainedValue()
  guard plugin.active.contains(String(cString: name)) else { return nil }
  return Unmanaged.passRetained(DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy),
    "DiskKit extensions are formatting this disk." as CFString))
}

private struct ExtensionTool {
  let path: String
  let version: String
  let stamp: String

  static func fingerprint(_ path: String) throws -> String {
    var value = stat()
    guard stat(path, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
      access(path, X_OK) == 0 else {
      throw ExtensionFailure(code: "tool_unavailable", message: "Formatter must be a regular executable file.")
    }
    return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec)"
  }

  func check() throws {
    guard try Self.fingerprint(path) == stamp else {
      throw ExtensionFailure(code: "tool_changed", message: "The formatter changed after its version probe.")
    }
  }
}

private struct ExtensionTarget {
  let id: String
  let wholeId: String
  let identity: UInt64
  let wholeIdentity: UInt64
  let content: String
  let expires: Date

  static func registryID(_ id: String) throws -> UInt64 {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, id))
    guard service != 0 else {
      throw ExtensionFailure(code: "disk_not_found", message: "The selected media is no longer attached.")
    }
    defer { IOObjectRelease(service) }
    var value: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(service, &value) == KERN_SUCCESS else {
      throw ExtensionFailure(code: "disk_not_found", message: "Cannot identify the selected media.")
    }
    return value
  }

  func check() throws {
    guard try Self.registryID(id) == identity, try Self.registryID(wholeId) == wholeIdentity else {
      throw ExtensionFailure(code: "target_changed", message: "The selected media was removed or replaced.")
    }
  }
}

/// Native implementation for the explicitly added DiskKit extensions package.
public class DiskKitMacosExtensionsPlugin: NSObject, FlutterPlugin {
  private var session: DASession?
  private let worker = DispatchQueue(label: "eu.byfox.disk_kit.extensions", qos: .userInitiated)
  private var targets: [String: ExtensionTarget] = [:]
  fileprivate var active = Set<String>() // Accessed only on the main queue.

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DiskKitMacosExtensionsPlugin()
    let channel = FlutterMethodChannel(name: "eu.byfox.disk_kit/extensions", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  deinit {
    if let session = session {
      DAUnregisterCallback(session,
        unsafeBitCast(extensionMountApproval, to: UnsafeMutableRawPointer.self),
        Unmanaged.passUnretained(self).toOpaque())
      DASessionSetDispatchQueue(session, nil)
    }
  }

  private func start() throws -> DASession {
    if let session = session { return session }
    guard let created = DASessionCreate(kCFAllocatorDefault) else {
      throw ExtensionFailure(code: "session_unavailable", message: "Cannot create a Disk Arbitration session.")
    }
    DARegisterDiskMountApprovalCallback(created, nil, extensionMountApproval,
      Unmanaged.passUnretained(self).toOpaque())
    DASessionSetDispatchQueue(created, DispatchQueue.main)
    session = created
    return created
  }

  private func disk(_ id: String) throws -> DADisk {
    guard id.range(of: "^disk[0-9]+(s[0-9]+)*$", options: .regularExpression) != nil else {
      throw ExtensionFailure(code: "invalid_arguments", message: "Invalid BSD disk identifier.")
    }
    guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, try start(), "/dev/" + id),
      DADiskCopyDescription(disk) != nil else {
      throw ExtensionFailure(code: "disk_not_found", message: "The selected disk is not present.")
    }
    return disk
  }

  private func validatedTarget(_ id: String) throws -> ExtensionTarget {
    let selected = try disk(id)
    guard let description = DADiskCopyDescription(selected) as NSDictionary?,
      let whole = DADiskCopyWholeDisk(selected), let wholeName = DADiskGetBSDName(whole),
      let physical = DADiskCopyDescription(whole) as NSDictionary? else {
      throw ExtensionFailure(code: "invalid_target", message: "Cannot resolve the containing physical disk.")
    }
    let wholeId = String(cString: wholeName)
    guard physical[kDADiskDescriptionDeviceInternalKey] as? Bool == false,
      physical[kDADiskDescriptionDeviceProtocolKey] as? String != "Disk Image" else {
      throw ExtensionFailure(code: "protected_disk", message: "Select positively identified external physical media.")
    }
    // A physical partition has exactly one slice component. Reject APFS logical
    // volumes and container/system partitions, even on external devices.
    let content = description[kDADiskDescriptionMediaContentKey] as? String ?? ""
    let allowed = ["Microsoft Basic Data", "Windows_NTFS",
      "Linux", "Linux Filesystem", "Linux Filesystem Data",
      "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7", "0FC63DAF-8483-4772-8E79-3D69D8477DE4"]
    guard id.range(of: "^disk[0-9]+s[0-9]+$", options: .regularExpression) != nil,
      id.hasPrefix(wholeId + "s"), description[kDADiskDescriptionMediaWholeKey] as? Bool == false,
      physical[kDADiskDescriptionMediaWholeKey] as? Bool == true, allowed.contains(content),
      description[kDADiskDescriptionMediaWritableKey] as? Bool == true,
      let size = description[kDADiskDescriptionMediaSizeKey] as? NSNumber, size.int64Value > 0 else {
      throw ExtensionFailure(code: "invalid_target", message: "Select a writable physical data partition; whole disks, containers, and system partitions are unsupported.")
    }
    return ExtensionTarget(id: id, wholeId: wholeId,
      identity: try ExtensionTarget.registryID(id), wholeIdentity: try ExtensionTarget.registryID(wholeId),
      content: content, expires: Date().addingTimeInterval(300))
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "getCapabilities":
        worker.async {
          let values = ["ntfs", "ext2", "ext3", "ext4", "btrfs"].map { fs -> [String: Any] in
            do {
              let tool = try Self.resolveTool(fs, args: args)
              return ["fileSystem": fs, "formatting": "available", "toolPath": tool.path,
                "toolVersion": tool.version, "reason": "Formatter is runnable; target access and compatibility are checked separately."]
            } catch {
              return ["fileSystem": fs, "formatting": "unavailable", "reason": Self.failure(error).message ?? "Tool unavailable."]
            }
          }
          DispatchQueue.main.async { result(values) }
        }
      case "getVolumeAccess":
        guard let id = args["diskId"] as? String,
          let description = DADiskCopyDescription(try disk(id)) as NSDictionary? else {
          throw ExtensionFailure(code: "invalid_arguments", message: "A current volume identifier is required.")
        }
        var value: [String: Any] = ["diskId": id]
        value["fileSystem"] = description[kDADiskDescriptionVolumeKindKey]
        if let url = description[kDADiskDescriptionVolumePathKey] as? URL {
          value["mountPath"] = url.path
          let path = url.path
          worker.async {
            var value = value
            var info = statfs()
            let known = statfs(path, &info) == 0
            value["canRead"] = access(path, R_OK | X_OK) == 0
            if known { value["canWrite"] = info.f_flags & UInt32(MNT_RDONLY) == 0 && access(path, W_OK | X_OK) == 0 }
            let accessResult = value
            DispatchQueue.main.async { result(accessResult) }
          }
        } else { result(value) }
      case "prepareFormat":
        guard let id = args["diskId"] as? String else {
          throw ExtensionFailure(code: "invalid_arguments", message: "A current partition identifier is required.")
        }
        targets = targets.filter { $0.value.expires > Date() }
        guard targets.count < 64 else {
          throw ExtensionFailure(code: "too_many_targets", message: "Too many pending format targets; wait for them to expire.")
        }
        let target = try validatedTarget(id)
        let token = UUID().uuidString
        targets[token] = target
        result(["diskId": target.id, "wholeDiskId": target.wholeId, "token": token])
      case "formatVolume":
        guard let token = args["token"] as? String, let target = targets.removeValue(forKey: token),
          target.expires > Date(), let fs = args["fileSystem"] as? String,
          let name = args["volumeName"] as? String else {
          throw ExtensionFailure(code: "invalid_target", message: "Prepare a fresh target before each formatting attempt.")
        }
        try Self.validateLabel(name, fs: fs)
        try target.check()
        let current = try validatedTarget(target.id)
        let compatibleTypes = fs == "ntfs"
          ? ["Microsoft Basic Data", "Windows_NTFS", "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"]
          : ["Linux", "Linux Filesystem", "Linux Filesystem Data", "0FC63DAF-8483-4772-8E79-3D69D8477DE4"]
        guard current.content == target.content, compatibleTypes.contains(current.content) else {
          throw ExtensionFailure(code: "invalid_target", message: "Use a partition with a compatible type: Microsoft Basic Data/NTFS for NTFS, or Linux Filesystem for ext. This extension does not change partition types.")
        }
        guard !active.contains(target.wholeId) else {
          throw ExtensionFailure(code: "disk_busy", message: "An extension operation is already running on this disk.")
        }
        active.insert(target.wholeId)
        worker.async { [self] in
          do {
            let tool = try Self.resolveTool(fs, args: args)
            try target.check()
            // Permission check performs no writes and precedes any unmount.
            let fd = open("/dev/" + target.id, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else {
              throw ExtensionFailure(code: "permission_denied", message: "The application lacks device access. This extension does not elevate privileges.")
            }
            var device = stat()
            let validDevice = fstat(fd, &device) == 0 && device.st_mode & S_IFMT == S_IFBLK
            close(fd)
            guard validDevice else {
              throw ExtensionFailure(code: "invalid_target", message: "The target is not a block device.")
            }
            DispatchQueue.main.async { [self] in
              do {
                try target.check()
                let session = try start()
                let whole = try disk(target.wholeId)
                if let volumeURL = try URL(fileURLWithPath: tool.path).resourceValues(forKeys: [.volumeURLKey]).volume,
                  let source = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL),
                  let sourceWhole = DADiskCopyWholeDisk(source), let sourceName = DADiskGetBSDName(sourceWhole),
                  String(cString: sourceName) == target.wholeId {
                  throw ExtensionFailure(code: "invalid_path", message: "The formatter must be stored off the target disk.")
                }
                let unmount = ExtensionCallback { [self] _, dissenter in
                  guard dissenter == nil else { finish(target, whole: nil, error: ExtensionFailure(code: "disk_busy", message: "Cannot unmount all target volumes without force."), result: result); return }
                  let claim = ExtensionCallback { [self] _, dissenter in
                    guard dissenter == nil else { finish(target, whole: nil, error: ExtensionFailure(code: "disk_busy", message: "Another process has claimed the disk."), result: result); return }
                    worker.async { [self] in
                      var error: Error?
                      do {
                        try target.check()
                        try tool.check()
                        let arguments = fs == "ntfs"
                          ? ["-Q", "-L", name, "/dev/" + target.id]
                          : ["-t", fs, "-F", "-L", name, "/dev/" + target.id]
                        let output = try Self.run(tool.path, arguments: arguments, target: target)
                        guard output.status == 0 else {
                          throw ExtensionFailure(code: "format_failed", message: "Formatter exited with status \(output.status): \(output.text)")
                        }
                        try target.check()
                        sync()
                      } catch let failure { error = failure }
                      let completedError = error
                      DispatchQueue.main.async { [self] in finish(target, whole: whole, error: completedError, result: result) }
                    }
                  }
                  DADiskClaim(whole, DADiskClaimOptions(kDADiskClaimOptionDefault), extensionKeepClaim, nil,
                    extensionCompleted, Unmanaged.passRetained(claim).toOpaque())
                }
                DADiskUnmount(whole, DADiskUnmountOptions(kDADiskUnmountOptionWhole), extensionCompleted,
                  Unmanaged.passRetained(unmount).toOpaque())
              } catch { finish(target, whole: nil, error: error, result: result) }
            }
          } catch {
            let failure = Self.failure(error)
            DispatchQueue.main.async { [self] in active.remove(target.wholeId); result(failure) }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    } catch { result(Self.failure(error)) }
  }

  private func finish(_ target: ExtensionTarget, whole: DADisk?, error: Error?, result: FlutterResult) {
    if let whole = whole { DADiskUnclaim(whole) }
    active.remove(target.wholeId)
    result(error.map(Self.failure))
  }

  private static func failure(_ error: Error) -> FlutterError {
    (error as? ExtensionFailure)?.flutter ?? FlutterError(code: "io_failed", message: error.localizedDescription, details: nil)
  }

  private static func validateLabel(_ name: String, fs: String) throws {
    guard ["ntfs", "ext2", "ext3", "ext4"].contains(fs) else {
      throw ExtensionFailure(code: "unsupported_filesystem", message: "Btrfs formatting is not implemented.")
    }
    guard !name.isEmpty, !name.contains(where: { $0 == "/" || $0 == ":" || $0 == "\\" || $0 == "\0" }),
      fs == "ntfs" ? name.utf16.count <= 128 : name.utf8.count <= 16 else {
      throw ExtensionFailure(code: "invalid_arguments", message: "Use a nonempty label without path separators or NUL: NTFS up to 128 UTF-16 units; ext up to 16 UTF-8 bytes.")
    }
  }

  private static func resolveTool(_ fs: String, args: [String: Any]) throws -> ExtensionTool {
    guard ["ntfs", "ext2", "ext3", "ext4"].contains(fs) else {
      throw ExtensionFailure(code: "unsupported_filesystem", message: "Btrfs has no supported macOS backend in this release.")
    }
    let executable = fs == "ntfs" ? "mkntfs" : "mke2fs"
    let key = fs == "ntfs" ? "mkntfsPath" : "mke2fsPath"
    let candidates: [String]
    if let configured = args[key] as? String {
      guard configured.hasPrefix("/"), !configured.contains("\0") else {
        throw ExtensionFailure(code: "invalid_arguments", message: "Tool paths must be absolute and contain no NUL.")
      }
      candidates = [configured]
    } else {
      let formula = fs == "ntfs" ? "ntfs-3g" : "e2fsprogs"
      candidates = ["/opt/homebrew", "/usr/local"].flatMap { prefix in
        ["\(prefix)/opt/\(formula)/sbin/\(executable)", "\(prefix)/opt/\(formula)/bin/\(executable)",
         "\(prefix)/sbin/\(executable)", "\(prefix)/bin/\(executable)"]
      }
    }
    var lastError: Error = ExtensionFailure(code: "tool_unavailable", message: "No executable \(executable) found; supply a trusted macOS binary or install it separately.")
    for candidate in candidates {
      do {
        let path = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        let stamp = try ExtensionTool.fingerprint(path)
        let output = try run(path, arguments: ["-V"], target: nil)
        guard output.status == 0, output.text.lowercased().contains(executable) else {
          throw ExtensionFailure(code: "tool_unavailable", message: "The \(executable) version probe failed; verify architecture and dependent libraries.")
        }
        let tool = ExtensionTool(path: path, version: output.text.trimmingCharacters(in: .whitespacesAndNewlines), stamp: stamp)
        try tool.check()
        return tool
      } catch {
        if args[key] is String || FileManager.default.fileExists(atPath: candidate) { lastError = error }
      }
    }
    throw lastError
  }

  private static func run(_ path: String, arguments: [String], target: ExtensionTarget?) throws -> (status: Int32, text: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    let started = Date()
    watchdog.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
    watchdog.setEventHandler {
      // Kill a formatter on detach; version probes have a ten-second deadline.
      if (target.map { (try? $0.check()) == nil } ?? (Date().timeIntervalSince(started) > 10)), process.isRunning {
        kill(process.processIdentifier, SIGKILL)
      }
    }
    watchdog.resume()
    defer { watchdog.cancel() }
    var output = Data()
    while true {
      let chunk = pipe.fileHandleForReading.readData(ofLength: 4096)
      if chunk.isEmpty { break }
      output.append(chunk)
      if output.count > 16384 { output.removeFirst(output.count - 16384) }
    }
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self))
  }
}
