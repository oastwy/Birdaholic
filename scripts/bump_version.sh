#!/usr/bin/env bash
# 只同步版本号到 4 处（pubspec / lib/app_version.dart / android+ohos local.properties）。
# 用法: scripts/bump_version.sh <版本如1.7.1> [build号,默认当前+1]
source "$(dirname "$0")/_lib.sh"
[ -z "${1:-}" ] && { c_red "用法: scripts/bump_version.sh <版本> [build,默认当前+1]"; exit 1; }
BUILD="${2:-$(( $(cur_build) + 1 ))}"
bump_version "$1" "$BUILD"
