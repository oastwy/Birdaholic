#!/usr/bin/env bash
# 一键发版准备：同步版本号（4 处）→ 打安卓包（可选连鸿蒙）→ 打印发布清单。
# 不自动 push / 发 Release / 改服务器（对外操作留人工确认）。
# 用法: scripts/release.sh <版本如1.7.1> [build号,默认当前+1] [--all 连鸿蒙也打]
source "$(dirname "$0")/_lib.sh"

NAME="${1:-}"
[ -z "$NAME" ] && { c_red "用法: scripts/release.sh <版本如1.7.1> [build,默认当前+1] [--all]"; exit 1; }
shift
BUILD=""; ALL=0
for a in "$@"; do case "$a" in --all) ALL=1;; [0-9]*) BUILD="$a";; esac; done
[ -z "$BUILD" ] && BUILD=$(( $(cur_build) + 1 ))

step "发版 ${NAME}+${BUILD}（上一版 $(cur_version)）"
bump_version "$NAME" "$BUILD"

"$REPO/scripts/build_android.sh"
[ "$ALL" = 1 ] && "$REPO/scripts/build_harmony.sh"

cat <<TIP

$(c_green "✅ 打包完成。发布清单（逐条人工确认后执行）：")
  1) 提交+推送代码（提交护栏 hook 会拦二进制/密钥）：
       git add -u && git status   # 核对后 commit
       git commit -m "release: v${NAME} ..." && git push origin main
  2) GitHub Release（挂 APK；先写好发布说明 md）：
       gh release create v${NAME} \\
         releases/Birdaholic_v${NAME}_android.apk releases/Birdaholic_v${NAME}_android.apk.sha256 \\
         --title "鸟瘾综合征 ${NAME}" --notes-file /tmp/notes.md --latest
  3) birding.today 下载页：
       ssh root@124.223.101.188 \\
         "sed -i 's#v[0-9.]\\+</span>#v${NAME}</span>#; s#/v[0-9.]\\+/Birdaholic_v[0-9.]\\+_android.apk#/v${NAME}/Birdaholic_v${NAME}_android.apk#g' /usr/share/nginx/html/download.html"
  4) 鸿蒙：$([ "$ALL" = 1 ] && echo "已打 releases/Birdaholic_v${NAME}_ohos_api22_release.app" || echo "scripts/build_harmony.sh") → 传华为 AGC
  5) iOS：scripts/build_ios.sh → Xcode archive+上传
TIP
