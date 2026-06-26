# 打包 / 发版脚本

把 HANDOFF 的打包配方固化成脚本，消掉「注释 overrides → 换 flutter.sdk → clean/pubget/build → 复制 → 恢复鸿蒙」这套易错的手活。**机器相关路径写死在 `_lib.sh`**（本机 wuyang）。

## 常用

```bash
# 改版本号（4 处同步：pubspec / app_version.dart / android+ohos local.properties）
scripts/bump_version.sh 1.7.1            # build 自动 = 当前+1
scripts/bump_version.sh 1.7.1 90         # 指定 build

# 打安卓（自动注释 overrides、打完自动恢复鸿蒙态）→ releases/*.apk + .sha256
scripts/build_android.sh

# 打鸿蒙 AGC .app（保持鸿蒙态、删 hwsdk.dir、hvigor assembleApp）→ releases/*.app
scripts/build_harmony.sh

# iOS：保持 overrides on（ohos fork 的 darwin 即上游 iOS 实现）、pod install，archive-ready
scripts/build_ios.sh            # 只准备，去 Xcode archive
scripts/build_ios.sh --ipa      # 试着直接出 ipa（发布签名需你的账号）

# 一键发版：bump + 打安卓(+--all 连鸿蒙) + 打印发布清单（gh release / download.html / AGC / iOS）
scripts/release.sh 1.7.1
scripts/release.sh 1.7.1 --all
```

## 关键约定
- `pubspec.yaml` 里 `# BUILD-SCRIPT-OVERRIDES-START / END` 之间是 ohos 专用 `dependency_overrides`，脚本自动切换，**勿手动改这两行标记**。
- **安卓**要 overrides off（ohos fork 编不过）；**iOS / 鸿蒙**保持 on。
- 发布（push / gh release / 改服务器）脚本**不自动做**，打印清单人工确认——对外操作不误触。

## 配套 hooks（`.claude/`）
- `guard_commit.sh`：commit/push 前拦截误入库的 `*.apk/*.app/*.hap/*.p12/*.jks/build-profile.json5/local.properties` 及 >5MB 大文件。
- `guard_build.sh`：直接 `flutter build apk` 但 overrides 还开着 → 拦，提示用 `build_android.sh`。
