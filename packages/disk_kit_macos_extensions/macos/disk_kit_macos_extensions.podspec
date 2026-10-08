Pod::Spec.new do |s|
  s.name = 'disk_kit_macos_extensions'
  s.version = '0.1.0'
  s.summary = 'Optional filesystem tools for DiskKit on macOS.'
  s.description = 'Inspect filesystem tool availability and format external partitions using caller-supplied tools.'
  s.homepage = 'https://github.com/Dark-Fox-PL/disk_kit'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = 'ByFox'
  s.source = { :path => '.' }
  s.source_files = 'disk_kit_macos_extensions/Sources/disk_kit_macos_extensions/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.frameworks = 'DiskArbitration', 'IOKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
