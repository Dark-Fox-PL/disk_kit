import Cocoa
import FlutterMacOS
import XCTest

@testable import disk_kit_macos

class RunnerTests: XCTestCase {
  func testGetDisks() {
    let plugin = DiskKitMacosPlugin()
    plugin.handle(FlutterMethodCall(methodName: "getDisks", arguments: nil)) { result in
      guard let disks = result as? [[String: Any]] else {
        XCTFail("Expected a disk snapshot, got \(String(describing: result))")
        return
      }
      XCTAssertFalse(disks.isEmpty)
      XCTAssertNotNil(disks.first?["id"])
    }
  }
}
