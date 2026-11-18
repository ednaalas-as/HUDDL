#!/bin/bash
# Starts the HUDDL Firebase emulators (Auth, Firestore, Storage, Functions) with Java 21.
cd "$(dirname "$0")"
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export PATH="$JAVA_HOME/bin:$PATH"
npm --prefix functions run build
exec firebase emulators:start --project demo-huddl --import=./.emulator-data --export-on-exit=./.emulator-data
