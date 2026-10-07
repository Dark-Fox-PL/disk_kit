import Cocoa
import DiskArbitration
import FlutterMacOS
import IOKit

private final class DiskOperation {
  // Keep the session alive until Disk Arbitration has delivered its callback.
  let session: DASession
  let completion: (DADisk, DADissenter?) -> Void

  init(session: DASession, completion: @escaping (DADisk, DADissenter?) -> Void) {
    self.session = session
    self.completion = completion
  }
}

private let operationCompleted: DADiskMountCallback = { disk, dissenter, context in
  guard let context = context else { return }
  let operation = Unmanaged<DiskOperation>.fromOpaque(context).takeRetainedValue()
  operation.completion(disk, dissenter)
}

private let diskAppeared: DADiskAppearedCallback = { disk, context in
  guard let context = context else { return }
  Unmanaged<DiskKitMacosPlugin>.fromOpaque(context).takeUnretainedValue().update(disk)
}

private let diskDisappeared: DADiskDisappearedCallback = { disk, context in
  guard let context = context, let name = DADiskGetBSDName(disk) else { return }
  let plugin = Unmanaged<DiskKitMacosPlugin>.fromOpaque(context).takeUnretainedValue()
  plugin.disks.removeValue(forKey: String(cString: name))
  plugin.emit()
}

private let diskChanged: DADiskDescriptionChangedCallback = { disk, _, context in
  guard let context = context else { return }
  Unmanaged<DiskKitMacosPlugin>.fromOpaque(context).takeUnretainedValue().update(disk)
}

public class DiskKitMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var session: DASession?
  fileprivate var disks: [String: [String: Any]] = [:]
  private var sink: FlutterEventSink?
  private let worker = DispatchQueue(label: "eu.byfox.disk_kit.fileOperations", qos: .userInitiated)
  // Reject overlapping native requests targeting the same whole disk.
  private var busyDisks = Set<String>()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DiskKitMacosPlugin()
    let methods = FlutterMethodChannel(
      name: "eu.byfox.disk_kit/methods", binaryMessenger: registrar.messenger)
    let events = FlutterEventChannel(
      name: "eu.byfox.disk_kit/disks", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  deinit {
    if let session = session {
      let context = Unmanaged.passUnretained(self).toOpaque()
      DAUnregisterCallback(
        session, unsafeBitCast(diskAppeared, to: UnsafeMutableRawPointer.self), context)
      DAUnregisterCallback(
        session, unsafeBitCast(diskDisappeared, to: UnsafeMutableRawPointer.self), context)
      DAUnregisterCallback(
        session, unsafeBitCast(diskChanged, to: UnsafeMutableRawPointer.self), context)
      DASessionSetDispatchQueue(session, nil)
    }
  }

  private func start() throws -> DASession {
    if let session = session { return session }
    guard let created = DASessionCreate(kCFAllocatorDefault) else {
      throw DiskKitNativeError(
        code: "session_unavailable", message: "Cannot create a Disk Arbitration session.")
    }
    session = created
    let context = Unmanaged.passUnretained(self).toOpaque()
    DARegisterDiskAppearedCallback(created, nil, diskAppeared, context)
    DARegisterDiskDisappearedCallback(created, nil, diskDisappeared, context)
    DARegisterDiskDescriptionChangedCallback(created, nil, nil, diskChanged, context)
    DASessionSetDispatchQueue(created, DispatchQueue.main)
    return created
  }

  private func snapshot() throws -> [[String: Any]] {
    let session = try start()
    var iterator: io_iterator_t = 0
    let status = IOServiceGetMatchingServices(
      kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator)
    guard status == KERN_SUCCESS else {
      throw DiskKitNativeError(
        code: "discovery_failed", message: "Cannot enumerate IOMedia devices.",
        details: ["status": status])
    }
    defer { IOObjectRelease(iterator) }
    var found: [String: [String: Any]] = [:]
    while true {
      let media = IOIteratorNext(iterator)
      if media == 0 { break }
      if let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, media),
        let info = describe(disk), let id = info["id"] as? String
      {
        found[id] = info
      }
      IOObjectRelease(media)
    }
    disks = found
    return sortedDisks()
  }

  private func sortedDisks() -> [[String: Any]] {
    return disks.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap {
      disks[$0]
    }
  }

  fileprivate func update(_ disk: DADisk) {
    guard let info = describe(disk), let id = info["id"] as? String else { return }
    disks[id] = info
    emit()
  }

  fileprivate func emit() { sink?(sortedDisks()) }

  private func describe(_ disk: DADisk) -> [String: Any]? {
    guard let name = DADiskGetBSDName(disk), let raw = DADiskCopyDescription(disk) else {
      return nil
    }
    let description = raw as NSDictionary
    let id = String(cString: name)
    var info: [String: Any] = ["id": id, "devicePath": "/dev/" + id]
    let keys: [(String, CFString)] = [
      ("name", kDADiskDescriptionMediaNameKey),
      ("volumeName", kDADiskDescriptionVolumeNameKey),
      ("fileSystem", kDADiskDescriptionVolumeKindKey),
      ("mediaContent", kDADiskDescriptionMediaContentKey),
      ("sizeBytes", kDADiskDescriptionMediaSizeKey),
      ("busProtocol", kDADiskDescriptionDeviceProtocolKey),
      ("vendor", kDADiskDescriptionDeviceVendorKey),
      ("model", kDADiskDescriptionDeviceModelKey),
      ("isWholeDisk", kDADiskDescriptionMediaWholeKey),
      ("isInternal", kDADiskDescriptionDeviceInternalKey),
      ("isRemovable", kDADiskDescriptionMediaRemovableKey),
      ("isEjectable", kDADiskDescriptionMediaEjectableKey),
      ("isWritable", kDADiskDescriptionMediaWritableKey),
      ("isMountable", kDADiskDescriptionVolumeMountableKey),
    ]
    for (key, nativeKey) in keys {
      if let value = description[nativeKey] { info[key] = value }
    }
    if let url = description[kDADiskDescriptionVolumePathKey] as? URL {
      info["volumePath"] = url.path
    }
    for (key, nativeKey) in [
      ("volumeUuid", kDADiskDescriptionVolumeUUIDKey),
      ("mediaUuid", kDADiskDescriptionMediaUUIDKey),
    ] {
      if let value = description[nativeKey], CFGetTypeID(value as CFTypeRef) == CFUUIDGetTypeID() {
        let uuid = unsafeBitCast(value as CFTypeRef, to: CFUUID.self)
        info[key] = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
      }
    }
    if let whole = DADiskCopyWholeDisk(disk), let wholeName = DADiskGetBSDName(whole) {
      info["wholeDiskId"] = String(cString: wholeName)
    }
    return info
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    do {
      let initial = try snapshot()
      sink = events
      events(initial)
      return nil
    } catch { return flutterError(error) }
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      if call.method == "getDisks" {
        result(try snapshot())
        return
      }
      guard
        [
          "mount", "unmount", "eject", "renameVolume", "copyFromDisk", "copyToDisk", "formatVolume",
          "formatDisk",
        ]
        .contains(call.method)
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let session = try start()
      guard let args = call.arguments as? [String: Any], let id = args["diskId"] as? String,
        id.range(of: "^disk[0-9]+(s[0-9]+)*$", options: .regularExpression) != nil
      else {
        throw DiskKitNativeError(
          code: "invalid_arguments", message: "A BSD disk identifier is required.")
      }
      // Resolve a fresh snapshot: a detached device must not be operated on.
      _ = try snapshot()
      guard let info = disks[id],
        let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/" + id)
      else {
        throw DiskKitNativeError(
          code: "disk_not_found", message: "The disk is no longer available.")
      }
      let wholeId = info["wholeDiskId"] as? String ?? id
      guard !busyDisks.contains(wholeId) else {
        throw DiskKitNativeError(
          code: "disk_busy", message: "Another DiskKit operation is running on this disk.")
      }
      if call.method.hasPrefix("copy") || call.method.hasPrefix("format") {
        try fileOperation(call.method, args: args, info: info, wholeId: wholeId, result: result)
        return
      }
      var target = disk
      if call.method == "eject" || (call.method == "unmount" && args["wholeDisk"] as? Bool == true)
      {
        guard let whole = DADiskCopyWholeDisk(disk) else {
          throw DiskKitNativeError(
            code: "disk_not_found", message: "The whole disk could not be resolved.")
        }
        target = whole
      }
      var newName: String?
      if call.method == "renameVolume" {
        guard info["isMountable"] as? Bool == true || info["volumeName"] is String else {
          throw DiskKitNativeError(
            code: "invalid_target", message: "Rename requires a recognized filesystem volume.")
        }
        guard let name = args["volumeName"] as? String else {
          throw DiskKitNativeError(
            code: "invalid_arguments", message: "A new volume name is required.")
        }
        try DiskKitFileOperations.validateVolumeName(
          name, fileSystem: info["fileSystem"] as? String)
        newName = name
      }
      busyDisks.insert(wholeId)
      let operation = DiskOperation(session: session) { [self] completedDisk, dissenter in
        busyDisks.remove(wholeId)
        if let dissenter = dissenter {
          result(
            FlutterError(
              code: "operation_failed",
              message: DADissenterGetStatusString(dissenter) as String?
                ?? "Disk Arbitration rejected the request.",
              details: [
                "operation": call.method, "diskId": id, "status": DADissenterGetStatus(dissenter),
              ]))
        } else {
          if let refreshed = try? snapshot() { sink?(refreshed) }
          if call.method == "eject" {
            result(nil)
          } else if let finalInfo = DADiskGetBSDName(completedDisk).flatMap({
            disks[String(cString: $0)]
          }) ?? describe(completedDisk) {
            result(finalInfo)
          } else {
            result(
              FlutterError(
                code: "disk_not_found",
                message: "The operation completed but its target description is unavailable.",
                details: ["operation": call.method, "diskId": id]))
          }
        }
      }
      let context = Unmanaged.passRetained(operation).toOpaque()
      switch call.method {
      case "mount":
        DADiskMount(
          target, nil, DADiskMountOptions(kDADiskMountOptionDefault), operationCompleted, context)
      case "unmount":
        let options =
          args["wholeDisk"] as? Bool == true
          ? kDADiskUnmountOptionWhole : kDADiskUnmountOptionDefault
        DADiskUnmount(target, DADiskUnmountOptions(options), operationCompleted, context)
      case "renameVolume":
        DADiskRename(
          target, newName! as CFString, DADiskRenameOptions(kDADiskRenameOptionDefault),
          operationCompleted, context)
      default:
        DADiskEject(
          target, DADiskEjectOptions(kDADiskEjectOptionDefault), operationCompleted, context)
      }
    } catch { result(flutterError(error)) }
  }

  private func fileOperation(
    _ method: String, args: [String: Any], info: [String: Any], wholeId: String,
    result: @escaping FlutterResult
  ) throws {
    let task: () throws -> Void
    if method.hasPrefix("copy") {
      guard let mountPath = info["volumePath"] as? String,
        let relativePath = args["relativePath"] as? String,
        let localPath = args["localPath"] as? String
      else {
        throw DiskKitNativeError(
          code: "volume_not_mounted", message: "Select a mounted volume and supply both paths.")
      }
      let volume = URL(fileURLWithPath: mountPath)
      // Validate once on the main thread, again immediately before file access.
      _ = try DiskKitFileOperations.relativeURL(relativePath, volume: volume)
      _ = try DiskKitFileOperations.absoluteURL(localPath)
      task = {
        let onDisk = try DiskKitFileOperations.relativeURL(relativePath, volume: volume)
        let local = try DiskKitFileOperations.absoluteURL(localPath)
        try DiskKitFileOperations.copy(
          source: method == "copyFromDisk" ? onDisk : local,
          destination: method == "copyFromDisk" ? local : onDisk)
      }
    } else {
      guard let id = info["id"] as? String, let fs = args["fileSystem"] as? String,
        let name = args["volumeName"] as? String
      else {
        throw DiskKitNativeError(
          code: "invalid_arguments", message: "Filesystem and volume name are required.")
      }
      // First release supports formatting explicitly identified external media.
      guard info["isInternal"] as? Bool == false else {
        throw DiskKitNativeError(
          code: "protected_disk",
          message: "Formatting is limited to disks positively identified as external.")
      }
      let entireDisk = method == "formatDisk"
      guard (info["isWholeDisk"] as? Bool) == entireDisk else {
        throw DiskKitNativeError(
          code: "invalid_target",
          message: entireDisk
            ? "formatDisk requires a whole disk." : "formatVolume requires a partition or volume.")
      }
      guard !entireDisk || args["partitionScheme"] is String else {
        throw DiskKitNativeError(
          code: "invalid_arguments", message: "A partition scheme is required.")
      }
      let arguments = try DiskKitFileOperations.formatArguments(
        diskId: id, fileSystem: fs, volumeName: name,
        scheme: entireDisk ? args["partitionScheme"] as? String : nil)
      task = { try DiskKitFileOperations.format(arguments: arguments) }
    }
    busyDisks.insert(wholeId)
    worker.async { [self] in
      var failure: FlutterError?
      do { try task() } catch { failure = flutterError(error) }
      DispatchQueue.main.async { [self] in
        busyDisks.remove(wholeId)
        result(failure)
        if let refreshed = try? snapshot() { sink?(refreshed) }
      }
    }
  }

  private func flutterError(_ error: Error) -> FlutterError {
    if let error = error as? DiskKitNativeError {
      return FlutterError(code: error.code, message: error.message, details: error.details)
    }
    let error = error as NSError
    return FlutterError(
      code: "io_failed", message: error.localizedDescription,
      details: ["domain": error.domain, "status": error.code])
  }
}
