#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/moledesk-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cache="$test_dir/module-cache"
sources=(Sources/Desk.swift Sources/Report.swift Sources/Scanner.swift Sources/Distribution.swift Sources/DiskBrowser.swift Sources/AppUsage.swift Sources/AppUninstall.swift)
xcrun swiftc -module-cache-path "$cache" Sources/Report.swift Sources/Scanner.swift Tests/Checks.swift -o "$test_dir/checks"
"$test_dir/checks"
xcrun swiftc -module-cache-path "$cache" "${sources[@]}" Tests/AppUsageChecks.swift -o "$test_dir/usage"
"$test_dir/usage"
xcrun swiftc -module-cache-path "$cache" "${sources[@]}" Tests/AppUninstallChecks.swift -o "$test_dir/uninstall"
"$test_dir/uninstall"
xcrun swiftc -module-cache-path "$cache" "${sources[@]}" Tests/WindowChecks.swift -o "$test_dir/window"
"$test_dir/window"
