#!/usr/bin/env bash
# PreToolUse(Bash) 提交护栏：git commit / push 时，暂存或待推送提交里若有不该入库的
# 二进制 / 签名 / 大文件 → 拦截（exit 2）。这次发版人肉盯着才没误推 APK/签名，固化成 hook。
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
case "$cmd" in
  *"git commit"*|*"git push"*) ;;
  *) exit 0 ;;
esac
cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0

staged=$(git diff --cached --name-only --diff-filter=AM 2>/dev/null || true)
unpushed=$(git diff --name-only --diff-filter=AM '@{u}..HEAD' 2>/dev/null || true)
bad=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.apk|*.app|*.hap|*.ipa|*.p12|*.jks|*.keystore|*.mobileprovision|*build-profile.json5|*/local.properties|*.env|*xeno_key*)
      bad="${bad}
  $f" ;;
    *)
      if [ -f "$f" ]; then
        sz=$(stat -f%z "$f" 2>/dev/null || echo 0)
        [ "${sz:-0}" -gt 5000000 ] && bad="${bad}
  $f ($((sz/1000000))MB)"
      fi ;;
  esac
done < <(printf '%s\n%s\n' "$staged" "$unpushed" | sort -u)

if [ -n "$bad" ]; then
  printf '🚫 提交护栏拦截：以下不该入库的二进制/签名/大文件在暂存或待推送提交里：%s\n' "$bad" >&2
  printf '→ git restore --staged <文件> 取消暂存；APK 走 GitHub Release 附件，签名/local.properties 应 gitignore。\n' >&2
  exit 2
fi
exit 0
