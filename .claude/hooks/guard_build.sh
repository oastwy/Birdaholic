#!/usr/bin/env bash
# PreToolUse(Bash) 打包态护栏：直接 `flutter build apk/appbundle`，但 dependency_overrides
# 还开着（鸿蒙态）→ 编译必失败 → 拦截，提示用 scripts/build_android.sh。
# 脚本内部的 build 走的是脚本路径命令、且已 overrides off，不会被这里拦。
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
case "$cmd" in
  *"flutter build apk"*|*"flutter build appbundle"*) ;;
  *) exit 0 ;;
esac
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
if awk '
  /BUILD-SCRIPT-OVERRIDES-START/{i=1;next}
  /BUILD-SCRIPT-OVERRIDES-END/{i=0}
  i && /^dependency_overrides:/{f=1}
  END{exit f?0:1}' "$dir/pubspec.yaml" 2>/dev/null; then
  printf '🚫 打包态护栏：dependency_overrides 还开着（鸿蒙态），直接 flutter build apk 会编译失败。\n' >&2
  printf '→ 用 scripts/build_android.sh（自动注释 overrides 并打完恢复鸿蒙态），或先手动注释 overrides。\n' >&2
  exit 2
fi
exit 0
