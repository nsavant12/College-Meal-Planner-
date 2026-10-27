#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

args=(--disable-xctest)
developer_dir="$(xcode-select -p)"
testing_plugin="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
# Some standalone Command Line Tools releases ship Testing but omit its plugin
# from the default search path. Full Xcode needs no override.
if [[ "$developer_dir" == */CommandLineTools && -f "$testing_plugin" ]]; then
    args+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test "${args[@]}" "$@"
