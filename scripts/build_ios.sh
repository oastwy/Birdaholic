#!/usr/bin/env bash
# iOS 准备/打包：保持 overrides on（ohos fork 的 audioplayers_darwin 即上游 iOS 实现、能用，
# 别像安卓那样注释）→ .flutter-sdk pub get → pod install（同步 Pods 沙盒）。
# 默认只做到 archive-ready，由你在 Xcode archive+上传（发布签名需你的 Apple 账号）。
# 加 --ipa 让脚本直接试 flutter build ipa。
source "$(dirname "$0")/_lib.sh"

VER="$(cur_name)"; BUILD="$(cur_build)"
step "iOS 准备 ${VER}+${BUILD}：overrides on + 用 .flutter-sdk 编 Dart"
overrides on
set_flutter_sdk /Users/wuyang/.flutter-sdk

step "flutter pub get（.flutter-sdk，写 ios/Flutter/Generated.xcconfig 指向 .flutter-sdk）"
"$FLUTTER_ANDROID" pub get >/dev/null

step "pod install（同步 Pods/Manifest.lock，解决 '[CP] Check Pods Manifest.lock' 沙盒不同步）"
( cd "$REPO/ios" && pod install )

if [ "${1:-}" = "--ipa" ]; then
  step "flutter build ipa --release（发布签名需你的账号，失败属正常）"
  if "$FLUTTER_ANDROID" build ipa --release; then
    ls -la "$REPO/build/ios/ipa"/*.ipa 2>/dev/null
    c_green "✅ ipa 已出，可上传 App Store Connect"
  else
    c_yellow "ipa 未出——多半是缺 Apple Distribution 证书。请在 Xcode 里 archive+上传。"
  fi
else
  c_green "✅ iOS 已 archive-ready。Xcode：打开 ios/Runner.xcworkspace → ⇧⌘K 清缓存 → Product→Archive → 上传。"
  c_yellow "（想脚本直接试 ipa：scripts/build_ios.sh --ipa）"
fi

# 只复原 android/local.properties 的 flutter.sdk（dev 默认鸿蒙）；不跑 flutter-ohos pub get，
# 以免把 ios/Flutter/Generated.xcconfig 重指回 flutter-ohos、破坏 Xcode archive。
set_flutter_sdk /Users/wuyang/flutter-ohos
