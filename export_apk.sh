#!/usr/bin/env bash
# Export BoomOre Android debug APK with auto-incremented versionCode.
# Run: bash export_apk.sh
set -e
cd "$(dirname "$0")"

GODOT="/d/Godot/Godot_v4.7.2-stable_win64.exe"
AAPT="/c/Program Files (x86)/Android/android-sdk/build-tools/36.0.0/aapt.exe"
export JAVA_HOME="C:/Program Files/Android/openjdk/jdk-21.0.8"

cur=$(grep '^version/code=' export_presets.cfg | head -1 | cut -d= -f2)
cur=${cur:-1}
new=$((cur + 1))

sed -i "s/^version\/code=.*/version\/code=${new}/" export_presets.cfg
sed -i "s/^version\/name=.*/version\/name=\"1.${new}\"/" export_presets.cfg
echo "versionCode: ${cur} -> ${new}  (versionName: 1.${new})"

"$GODOT" --headless --export-debug "Android" "BoomOre_debug.apk"

echo "---- APK info ----"
"$AAPT" dump badging BoomOre_debug.apk | grep -E "package:|application-label:"
echo "DONE"
