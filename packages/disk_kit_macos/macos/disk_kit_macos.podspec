#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint disk_kit_macos.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'disk_kit_macos'
  s.version          = '1.0.0'
  s.summary          = 'macOS storage operations for DiskKit.'
  s.description      = <<-DESC
Disk discovery, notifications, mounting, copying and formatting for DiskKit.
                       DESC
  s.homepage         = 'https://github.com/Dark-Fox-PL/disk_kit'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'ByFox'

  s.source           = { :path => '.' }
  s.source_files = 'disk_kit_macos/Sources/disk_kit_macos/**/*.swift'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'disk_kit_macos_privacy' => ['disk_kit_macos/Sources/disk_kit_macos/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.frameworks = 'DiskArbitration', 'IOKit', 'Security'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
