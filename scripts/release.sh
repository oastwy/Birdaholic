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

$(c_green "✅ 打包完成（仅 arm64-v8a）。发布清单（逐条人工确认后执行）：")
  1) 提交+推送代码（提交护栏 hook 会拦二进制/密钥）：
       git add -u && git status   # 核对后 commit
       git commit -m "release: v${NAME} ..." && git push origin main
  2) 【主渠道】国内服务器 OTA —— 真实用户一键更新走这里：
       scp releases/Birdaholic_v${NAME}_android_arm64.apk \\
           root@your-server-ip:/usr/share/nginx/html/birdaholic/
       # 从 releases/Birdaholic_v${NAME}_android_arm64.apk.sha256 复制第一列校验值
       再把服务器 /usr/share/nginx/html/birdaholic/version.json 改成（url 必须指 *_arm64.apk）：
         {"versionCode": ${BUILD}, "versionName": "${NAME}",
          "url": "https://birding.today/birdaholic/Birdaholic_v${NAME}_android_arm64.apk",
          "sha256": "<上一步的 sha256>",
          "notes": "……填更新说明……", "date": "$(date +%F)"}
  3) 下载页 download.html 兜底（一键装失败者手动下 arm64）：
       改 download.html 的下载链接指向 Birdaholic_v${NAME}_android_arm64.apk（页面版本号同步成 ${NAME}）。
  4) GitHub Release（仅给存量 ≤1.7.2 老用户 bootstrap；主渠道已是国内 OTA）：
       gh release create v${NAME} \\
         releases/Birdaholic_v${NAME}_android_arm64.apk releases/Birdaholic_v${NAME}_android_arm64.apk.sha256 \\
         --title "鸟瘾综合征 ${NAME}" --notes-file /tmp/notes.md --latest
  5) 鸿蒙：$([ "$ALL" = 1 ] && echo "已打 releases/Birdaholic_v${NAME}_ohos_api22_release.app" || echo "scripts/build_harmony.sh") → 传华为 AGC
  6) iOS：scripts/build_ios.sh → Xcode archive+上传
TIP
