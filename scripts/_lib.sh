#!/usr/bin/env bash
# 共享库：被 build_*.sh / release.sh source。把 HANDOFF 的打包配方固化在这里。
# 用法：source "$(dirname "$0")/_lib.sh"
set -euo pipefail

# ── 机器相关路径（本机 wuyang 固定）────────────────────────────────
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_ANDROID=/Users/wuyang/.flutter-sdk/bin/flutter      # 安卓/iOS 用上游 SDK
FLUTTER_OHOS=/Users/wuyang/flutter-ohos/bin/flutter         # 鸿蒙用 ohos fork SDK
DEVECO=/Applications/DevEco-Studio.app/Contents
HOS_SDK=/Applications/DevEco-Studio.app/Contents/sdk
PUBSPEC="$REPO/pubspec.yaml"
ANDROID_LP="$REPO/android/local.properties"
OHOS_LP="$REPO/ohos/local.properties"
RELEASES="$REPO/releases"

cd "$REPO"

c_green() { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
step() { c_green ">>> $*"; }

# ── pubspec dependency_overrides 切换（标记 BUILD-SCRIPT-OVERRIDES-START/END 之间）──
overrides() { # overrides off|on
  local mode="$1"
  awk -v mode="$mode" '
    /BUILD-SCRIPT-OVERRIDES-START/ {print; inb=1; next}
    /BUILD-SCRIPT-OVERRIDES-END/   {print; inb=0; next}
    inb && mode=="off" { if ($0 !~ /^# /) sub(/^/, "# "); print; next }
    inb && mode=="on"  { sub(/^# /, ""); print; next }
    {print}
  ' "$PUBSPEC" > "$PUBSPEC.tmp" && mv "$PUBSPEC.tmp" "$PUBSPEC"
}
overrides_active() { # 返回 0 = 当前 overrides 开启（未注释）
  awk '/BUILD-SCRIPT-OVERRIDES-START/{i=1;next}/BUILD-SCRIPT-OVERRIDES-END/{i=0}
       i && /^dependency_overrides:/{found=1} END{exit found?0:1}' "$PUBSPEC"
}

set_flutter_sdk() { # set_flutter_sdk <path>
  /usr/bin/sed -i '' "s#^flutter.sdk=.*#flutter.sdk=$1#" "$ANDROID_LP"
}

# ── 恢复鸿蒙开发态（android 打包后必做；脚本 EXIT trap 调用）────────
restore_harmony() {
  step "恢复鸿蒙开发态（overrides on + flutter.sdk→flutter-ohos + pub get）"
  overrides on
  set_flutter_sdk /Users/wuyang/flutter-ohos
  "$FLUTTER_OHOS" pub get >/dev/null 2>&1 || true
  c_green "已恢复鸿蒙态。"
}

# ── 读当前版本（pubspec version: X.Y.Z+B）──────────────────────────
cur_version() { /usr/bin/grep -E '^version:' "$PUBSPEC" | /usr/bin/sed -E 's/version: *//'; }
cur_name() { cur_version | /usr/bin/sed -E 's/\+.*//'; }
cur_build() { cur_version | /usr/bin/sed -E 's/.*\+//'; }

# ── 四处同步版本号 ───────────────────────────────────────────────
bump_version() { # bump_version <name> <build>
  local name="$1" build="$2"
  /usr/bin/sed -i '' "s/^version: .*/version: ${name}+${build}/" "$PUBSPEC"
  printf "const appVersionName = '%s';\nconst appBuildNumber = %s;\n" "$name" "$build" > "$REPO/lib/app_version.dart"
  /usr/bin/sed -i '' "s/^flutter.versionName=.*/flutter.versionName=${name}/; s/^flutter.versionCode=.*/flutter.versionCode=${build}/" "$ANDROID_LP"
  /usr/bin/sed -i '' "s/^flutter.versionName=.*/flutter.versionName=${name}/; s/^flutter.versionCode=.*/flutter.versionCode=${build}/" "$OHOS_LP"
  c_green "版本已同步到 ${name}+${build}（pubspec / app_version / android+ohos local.properties）"
}

# ── 复制产物到 releases/ + sha256 ────────────────────────────────
publish_artifact() { # publish_artifact <src> <dest-basename>
  local src="$1" dest="$RELEASES/$2"
  /bin/cp "$src" "$dest"
  ( cd "$RELEASES" && /usr/bin/shasum -a 256 "$2" > "$2.sha256" )
  c_green "产物：$dest"
  /usr/bin/shasum -a 256 "$dest" | /usr/bin/awk '{print "  sha256:",$1}'
}
