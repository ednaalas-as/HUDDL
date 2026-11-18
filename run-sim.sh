#!/bin/bash
# Builds HUDDL and launches it in the iPhone 17 Pro simulator (uses local Firebase emulators).
set -e
cd "$(dirname "$0")"
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
xcodebuild -project HUDDL.xcodeproj -scheme HUDDL -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build -quiet build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/HUDDL.app
xcrun simctl launch booted com.huddl.app
