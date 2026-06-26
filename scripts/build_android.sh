#!/usr/bin/env bash
# 安卓打包：注释 overrides → .flutter-sdk → clean/pubget/build apk → 复制 releases + sha256。
# 退出时（成功或失败）自动恢复鸿蒙开发态。
source "$(dirname "$0")/_lib.sh"
trap restore_harmony EXIT

VER="$(cur_name)"; BUILD="$(cur_build)"
step "安卓打包 ${VER}+${BUILD}：overrides off + flutter.sdk→.flutter-sdk"
overrides off
set_flutter_sdk /Users/wuyang/.flutter-sdk

step "flutter clean + pub get（.flutter-sdk）"
"$FLUTTER_ANDROID" clean >/dev/null
"$FLUTTER_ANDROID" pub get >/dev/null

step "flutter build apk --release"
"$FLUTTER_ANDROID" build apk --release

publish_artifact "$REPO/build/app/outputs/flutter-apk/app-release.apk" "Birdaholic_v${VER}_android.apk"

AAPT=$(ls "$HOME"/Library/Android/sdk/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
[ -n "$AAPT" ] && "$AAPT" dump badging "$RELEASES/Birdaholic_v${VER}_android.apk" 2>/dev/null \
  | /usr/bin/grep "package: name" | head -1
c_green "✅ 安卓 ${VER}+${BUILD} 打好（鸿蒙态由 trap 自动恢复）"
