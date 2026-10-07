#!/bin/sh
# Tests use temporary files and formatting plans; no disk is formatted.
set -eu
cd "$(dirname "$0")/.."
disk_kit_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/disk-kit-tests.XXXXXX")
trap 'rm -rf "$disk_kit_test_dir"' EXIT HUP INT TERM
disk_kit_xctest_path="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
disk_kit_xctest_lib="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib"
xcrun swiftc -module-cache-path "$disk_kit_test_dir/cache" \
  -I "$disk_kit_xctest_lib" -L "$disk_kit_xctest_lib" -Xlinker -rpath -Xlinker "$disk_kit_xctest_lib" \
  -F "$disk_kit_xctest_path" -Xlinker -rpath -Xlinker "$disk_kit_xctest_path" \
  packages/disk_kit_macos/macos/disk_kit_macos/Sources/disk_kit_macos/DiskKitFileOperations.swift \
  packages/disk_kit_macos/macos/disk_kit_macos/Sources/disk_kit_macos/DiskKitMediaOperations.swift \
  packages/disk_kit_macos/macos/Tests/main.swift \
  -o "$disk_kit_test_dir/tests"
"$disk_kit_test_dir/tests"
