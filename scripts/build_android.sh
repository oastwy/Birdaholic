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
if ! "$FLUTTER_ANDROID" pub get >/dev/null; then
  c_yellow "pub get 网络刷新失败，改用本地缓存继续打包。"
  "$FLUTTER_ANDROID" pub get --offline >/dev/null
fi

step "flutter build apk --release（仅 arm64-v8a）"
# build.gradle 已过滤为 arm64-v8a：原来 72MB 的 universal 包会变成约 25MB 的真机包。
"$FLUTTER_ANDROID" build apk --release

APKDIR="$REPO/build/app/outputs/flutter-apk"
publish_artifact "$APKDIR/app-release.apk" "Birdaholic_v${VER}_android_arm64.apk"

AAPT=$(ls "$HOME"/Library/Android/sdk/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
[ -n "$AAPT" ] && "$AAPT" dump badging "$RELEASES/Birdaholic_v${VER}_android_arm64.apk" 2>/dev/null \
  | /usr/bin/grep "package: name" | head -1
c_green "✅ 安卓 ${VER}+${BUILD} 已打 arm64-only 包（鸿蒙态由 trap 自动恢复）"
c_yellow "发版提醒：version.json 与 download.html 均指向 *_arm64.apk。"
