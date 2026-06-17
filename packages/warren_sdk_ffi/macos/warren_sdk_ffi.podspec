#
# Cocoapods spec for the macOS native build of the Warren in-process engine.
# cargokit compiles `native/warren_sdk_frb` from source and force-loads the
# resulting static library into the plugin framework. See NATIVE_BUILD.md.
#
Pod::Spec.new do |s|
  s.name             = 'warren_sdk_ffi'
  s.version          = '0.1.0'
  s.summary          = 'In-process Warren VPN engine (Mode A) for macOS.'
  s.description      = <<-DESC
Runs the audited Warren Rust engine inside the Flutter app process via
flutter_rust_bridge. Built from source by cargokit; no prebuilt binaries.
                       DESC
  s.homepage         = 'https://warrenbrowse.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Warren' => 'dev@warrenbrowse.com' }
  s.module_name      = 'warren_sdk_ffi'

  # The Classes forwarder keeps a non-empty source set so CocoaPods emits a
  # framework; the Rust symbols are linked in by the script phase below.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Warren Rust engine',
    # Args: relative path to the crate (Cargo.toml dir), then the cargo lib name.
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../native/warren_sdk_frb warren_sdk_frb',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${PODS_CONFIGURATION_BUILD_DIR}/warren_sdk_ffi/libwarren_sdk_frb.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/warren_sdk_ffi/libwarren_sdk_frb.a',
  }
end
