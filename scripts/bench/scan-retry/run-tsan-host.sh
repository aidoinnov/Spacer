#!/bin/bash
# Run an already instrumented XCTest bundle without changing Xcode/system files.
# SwiftPM's platform-signed discovery helper can reject sanitizer insertion on
# this macOS version. A private ad-hoc signed copy of xctest avoids that host
# incompatibility while preserving the same test bundle and TSAN runtime.
set -euo pipefail
bundle="${1:?usage: run-tsan-host.sh BUNDLE [XCTest filter]}"
filter="${2:-SpaceSnifferCoreTests.ScanRetryTests,SpaceSnifferCoreTests.ScanAdmissionTests,SpaceSnifferCoreTests.ScanSchedulingTests}"
developer_dir="$(xcode-select -p)"
compiler_path="$(xcrun --find clang)"
runtime_dir="$("$compiler_path" -print-runtime-dir)"
test_host_dir="$(mktemp -d /private/tmp/sniffer-tsan-host.XXXXXX)"
trap 'unset DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH; rm -rf "$test_host_dir"' EXIT
cp "$developer_dir/usr/bin/xctest" "$test_host_dir/xctest"
codesign --force --sign - "$test_host_dir/xctest"
export DYLD_FRAMEWORK_PATH="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
export DYLD_LIBRARY_PATH="$developer_dir/Platforms/MacOSX.platform/Developer/usr/lib:$runtime_dir"
export DYLD_INSERT_LIBRARIES="$runtime_dir/libclang_rt.tsan_osx_dynamic.dylib"
"$test_host_dir/xctest" -XCTest "$filter" "$bundle"
