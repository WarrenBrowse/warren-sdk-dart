#
# Cocoapods spec for the iOS native build of the Warren in-process engine.
# cargokit compiles `native/warren_sdk_frb` from source and force-loads the
# resulting static library into the plugin framework. See NATIVE_BUILD.md.
#
Pod::Spec.new do |s|
  s.name             = 'warren_sdk_ffi'
  s.version          = '0.1.0'
  s.summary          = 'In-process Warren VPN engine (Mode A) for iOS.'
  s.description      = <<-DESC
Runs the audited Warren Rust engine inside the Flutter app process via
flutter_rust_bridge. Built from source by cargokit; no prebuilt binaries.
                       DESC
  s.homepage         = 'https://warrenbrowse.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Warren' => 'dev@warrenbrowse.com' }
  s.module_name      = 'warren_sdk_ffi'

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Warren Rust engine',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../native/warren_sdk_frb warren_sdk_frb',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${PODS_CONFIGURATION_BUILD_DIR}/warren_sdk_ffi/libwarren_sdk_frb.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/warren_sdk_ffi/libwarren_sdk_frb.a',
  }
end
