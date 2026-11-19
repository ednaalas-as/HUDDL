#!/bin/sh
# Writes Config/Google.local.xcconfig from firebase/GoogleService-Info.plist (both git-ignored).
set -e
cd "$(dirname "$0")/.."
P=firebase/GoogleService-Info.plist
CID=$(/usr/libexec/PlistBuddy -c "Print CLIENT_ID" "$P")
RCID=$(/usr/libexec/PlistBuddy -c "Print REVERSED_CLIENT_ID" "$P")
printf '// Generated from %s. Git-ignored: never commit.\nGOOGLE_CLIENT_ID = %s\nGOOGLE_REVERSED_CLIENT_ID = %s\n' "$P" "$CID" "$RCID" > Config/Google.local.xcconfig
echo "Wrote Config/Google.local.xcconfig"
