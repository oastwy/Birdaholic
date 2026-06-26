#!/usr/bin/env bash
# 鸿蒙打包：保持鸿蒙态 → ohos/local.properties 同步版本+删 hwsdk.dir →
# hvigor assembleApp（flutter-hvigor-plugin 自动重编 Dart）→ 复制 releases + sha256。
# 产物是 AGC 上架用的 .app（compatible22·target22·Release·已签名）。
source "$(dirname "$0")/_lib.sh"

VER="$(cur_name)"; BUILD="$(cur_build)"
step "鸿蒙打包 ${VER}/${BUILD}：overrides on + flutter.sdk→flutter-ohos"
overrides on
set_flutter_sdk /Users/wuyang/flutter-ohos

# ohos/local.properties：同步版本号 + 删 hwsdk.dir（hvigor 必须用 OpenHarmony SDK 而非 DevEco 的 HarmonyOS SDK）
/usr/bin/sed -i '' \
  "s/^flutter.versionName=.*/flutter.versionName=${VER}/; s/^flutter.versionCode=.*/flutter.versionCode=${BUILD}/; /^hwsdk.dir=/d" \
  "$OHOS_LP"

if [ ! -d "$REPO/ohos/entry/oh_modules" ]; then
  step "oh_modules 缺，带 HOS_SDK_HOME 重建"
  HOS_SDK_HOME="$HOS_SDK" "$FLUTTER_OHOS" pub get || true
  /usr/bin/sed -i '' "/^hwsdk.dir=/d" "$OHOS_LP"   # pub get 会加回 hwsdk.dir，再删
fi

step "hvigor assembleApp -p product=default -p buildMode=release"
( cd "$REPO/ohos" && "$DEVECO/tools/node/bin/node" "$DEVECO/tools/hvigor/bin/hvigorw.js" \
    assembleApp -p product=default -p buildMode=release --mode project --no-daemon )

publish_artifact "$REPO/ohos/build/outputs/default/ohos-default-signed.app" \
  "Birdaholic_v${VER}_ohos_api22_release.app"
c_green "✅ 鸿蒙 ${VER}/${BUILD} .app 打好（api22·Release·已签名）——传华为 AGC 即可"
c_yellow "提示：flutter_assets 应已被重编（验：stat ohos/entry/src/main/resources/rawfile/flutter_assets）"
