# 鸿蒙（HarmonyOS NEXT / 纯血鸿蒙）.hap 构建指南

> 目标：给 Birdaholic 出一个能在纯血鸿蒙（HarmonyOS NEXT）真机 sideload 的 `.hap`。
> 纯血鸿蒙去安卓化，**不能装 APK**，必须原生 `.hap`，且即便不上架也要签名（debug 即可）。

---

## ✅ 2026-06-14 实测：已在 HarmonyOS NEXT 模拟器跑通（UI + 存储 + 鸟鸣播放全部正常）

**实测环境**
- DevEco Studio 26.0.0.461（Beta1）；SDK = `/Applications/DevEco-Studio.app/Contents/sdk`
- 模拟器 Pura 90 Pro · HarmonyOS 7.0.0(26.0.0) Beta1 · API 26（`127.0.0.1:5555`）
- ohos Flutter：`gitcode.com/openharmony-sig/flutter_flutter` 分支 **`br_3.27.4-ohos-1.0.4`**（Flutter 3.27.4，匹配本项目用的 `withValues` 3.27 API，无需改代码）
  - 浅克隆会导致版本 `0.0.0-unknown` → pub 解析失败；修法：`git fetch --unshallow --tags` 后 `git tag -f 3.27.4 HEAD`，再 `flutter --version` 显示 3.27.4。

**环境变量**（已存 `~/ohos-env.sh`，每步先 `source`）
```bash
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export TOOL_HOME=/Applications/DevEco-Studio.app/Contents/tools
export PATH=$HOME/flutter-ohos/bin:$TOOL_HOME/ohpm/bin:$TOOL_HOME/hvigor/bin:$TOOL_HOME/node/bin:$PATH
export FLUTTER_GIT_URL=https://gitcode.com/openharmony-sig/flutter_flutter.git
```

**ohos 工程**：`flutter create --platforms ohos --org com.birdflash .` 生成 `ohos/`（bundleName `com.birdflash.bird_flashcard`，含 `ohos.permission.INTERNET`）。
**签名**：DevEco → 文件 → 项目结构 → 签名配置 → 勾「自动生成签名文件」（**需先连一台设备/模拟器**），生成到 `~/.ohos/config/`，写进 `ohos/build-profile.json5`。

**插件适配（关键）**——本地 clone 三个 ohos 仓库，pubspec 用 path 挂上：
- federated（解决启动白屏，main() 一上来 await SharedPreferences）：`gitcode.com/openharmony-sig/flutter_packages` → `packages/{shared_preferences,path_provider,url_launcher}/*_ohos` 三个用 `path:` 加进 `dependencies`。
- **audioplayers（鸟鸣，核心）**：`gitcode.com/openharmony-sig/flutter_audioplayers` 分支 **`br_audioplayers-v6.1.0_ohos`**（对齐 6.1.0）。fork 内部 git URL 写坏了（`gitcode.com//flutter_audioplayers`），必须把**全部子包用 path 覆盖**（见 `dependency_overrides`），且 `audioplayers_platform_interface` 改用 **pub 正版 ^7.0.0**（fork 自带的那个 `forceSpeaker` 未定义、编不过）。
- wakelock_plus → pub 的 `wakelock_plus_ohos: ^0.0.3`（可用）。
- **geolocator_ohos 0.0.3 有空安全 bug（DateTime? 编不过）→ 已移除**；定位（eBird"用当前位置"）在 ohos 上暂不可用。
- **file_picker 暂缓**：fork 才 8.0.6、本项目用 11.x，版差大；上传是次要功能。

> ⚠️ 上述 pubspec 改动（`*_ohos` path 依赖 + audioplayers `dependency_overrides` + 移除 geolocator_ohos）**只用于本机 ohos 构建**，路径写死在 `~/ohos-*`。**别提交进发布分支，也别用它构建 Android/iOS 正式包**。

**出包**
```bash
source ~/ohos-env.sh && cd <repo>
flutter run -d 127.0.0.1:5555 --debug     # 装模拟器调试
flutter build hap --release               # 产物 build/ohos/hap/entry-default-signed.hap（真机 sideload）
flutter build app --release               # 产物 build/ohos/app/ohos-default-signed.app（AppGallery 上架/开放测试）
```

---

## ✅ 2026-06-14 实测：AppGallery 发布签名打通（.app 通过 hap-sign-tool verify）

**踩坑根因**：AGC 只认 **hvigor 自己签+打**的 `.app`；手动 `hap-sign-tool`+`app_packing_tool` 重打的包 AGC 一律报 991/996（解析失败）。而 hvigor 签名要的是 **DevEco 加密后的密码密文**（≥32 hex），明文会被拒（`storePassword < 32`）。密文解密时 hvigor 还要去**密钥库 `.p12` 同目录找 `material/`**（fd/ac/ce，AES-128-GCM+pbkdf2 的密钥材料）——这个文件夹只有 DevEco 配签名时才会生成。手工没法造。

**正解（唯一可靠路径）**：让 DevEco 走一遍签名配置，由它写密文 + 生成 `material/`，再用 hvigor/flutter 出包。
1. DevEco → 文件 → 项目结构 → 签名配置，用「生成私钥和证书请求文件」向导新建 **v3** 密钥（`birdaholic_v3.p12`，库密码=密钥密码都填 `<密钥库密码·见本机签名备份>`，别名 `birdaholic_v3`）；高级设置里手动把密钥密码也填一遍保持一致。
2. 拿生成的 `.csr` 去 AGC → 证书申请**发布证书** `birdaholic_v3.cer`；再 AGC → Profile 用该证书+本 App 建**发布 Profile** `birdaholic_v3Release.p7b`。
3. DevEco 签名配置挂上这套 v3（p12+cer+p7b），密码 `<密钥库密码·见本机签名备份>` → 应用。DevEco 会：① 把加密密文写进 `ohos/build-profile.json5` 的 `storePassword`/`keyPassword`；② 在 `~/Downloads/material/`（密钥库同目录）生成密钥材料。**这两样齐了 hvigor 才能解密码签名。**
4. `source ~/ohos-env.sh && flutter build app --release` → `build/ohos/app/ohos-default-signed.app`。

**产物自检（务必跑，验签 + 证书类型必须 Release）**
```bash
JBR=$(find /Applications/DevEco-Studio.app -path '*/jbr/Contents/Home/bin/java'|head -1)
TOOL=$(find /Applications/DevEco-Studio.app -name hap-sign-tool.jar|head -1)
"$JBR" -jar "$TOOL" verify-app -inFile <xxx>.app -outCertChain /tmp/out.cer -outProfile /tmp/out.p7b
#  → 末行 "verify: Verify success"；out.cer 叶子证书 CN 必须含 ",Release"（不是 ",Development"）
#  叶子公钥要 == birdaholic_v3.cer 公钥（openssl ... -pubkey | dgst -sha256 比对）
```
> ⚠️ 之前 AGC 一致性检测 55 分失败，就是误用了 **Development** 叶子证书去配 **Release** Profile。v3 全链路都是 Release 证书，公钥一致，verify 通过 → AGC 可解析。

**已交付**：`~/Downloads/Birdaholic_v1.6.16-73_HarmonyOS_release.app`（55.9MB，bundle `com.birdflash.bird_flashcard`，versionName 1.6.16 / versionCode 73），verify success，叶子证书 Release。可直接传 AGC「开放测试」。

**仍待办**：file_picker(上传) / geolocator(定位) ohos 适配；真机 sideload 需把设备 UDID 登记进 debug profile（debug 签名只能装登记设备，发给任意用户须走 AppGallery）。

---

## 为什么不能在 CI / 无人值守环境直接出包
- HarmonyOS SDK / DevEco / 命令行工具的下载**卡在华为开发者账号登录**后面，无法 headless 安装。
- 装包要签名 → debug 签名需在 DevEco 里登录华为账号自动配置（或手动用证书签）。

所以分工：**账号 + DevEco 安装由本人在 Mac 上一次性完成；其余 clone fork / 配置 / 插件对齐 / `flutter build hap` 全部命令行可做。**

---

## 一、本人需要做的（一次性，GUI + 华为账号）
1. 注册/登录华为开发者账号（developer.huawei.com）。
2. 下载安装 **DevEco Studio**（macOS 版），在里面用 SDK Manager 装好 **HarmonyOS SDK**（API 12+）。
3. 记下两个路径，待会告诉我：
   - `DEVECO_SDK_HOME`（HarmonyOS SDK 根目录）
   - DevEco 里的 `node` / `ohpm` / `hvigor` 路径（一般在 DevEco.app 内）
4. 真机：手机进开发者模式、USB 调试打开；DevEco 登录账号后会自动给 debug 签名（sideload 用 debug 包即可）。

## 二、我来做的（命令行）
1. clone 鸿蒙 Flutter 分支（**不覆盖**你现在的 `~/.flutter-sdk`，单独放）：
   ```bash
   git clone https://gitcode.com/openharmony-sig/flutter_flutter.git ~/flutter-ohos
   # 选分支：本项目用到 Flutter 3.27+ API（Color.withValues），
   # 因此用与之匹配的 oh-3.35.x-dev 分支，而非 3.22.x-ohos 稳定分支
   cd ~/flutter-ohos && git checkout oh-3.35.7-dev   # 以实际最新可用 dev 分支为准
   export PATH="$HOME/flutter-ohos/bin:$PATH"
   flutter doctor   # 确认 OpenHarmony toolchain 这一项 ✓（依赖上面的 SDK 路径）
   ```
2. 生成 ohos 平台目录（不动现有 android/ios）：
   ```bash
   cd /Users/wuyang/Documents/bird_flashcard_repo
   flutter create --platforms ohos .
   ```
3. 插件 ohos 适配（见下表）。federated 插件加 `*_ohos` 实现包即可自动注册；
   纯 git 源的用 `dependency_overrides`。**仅在 ohos 构建时启用，别提交进主 pubspec**（会破坏安卓/iOS）。
4. 出包：
   ```bash
   flutter build hap --release    # 产物 .hap；编译产物走云端，无需 --local-engine
   # 安装到真机：
   flutter install   # 或 hdc app install <xxx.hap>
   ```

---

## 三、插件适配清单（已核实，2026-06）
| 插件 | 鸿蒙方案 | 备注 |
|---|---|---|
| audioplayers | `OpenHarmony-SIG/flutter_audioplayers`（gitee，git 依赖） | 命脉。已知 AMR 不支持，本项目用 mp3/m4a 不受影响 |
| geolocator | `geolocator_ohos`（pub.dev） | 版本可能基于较旧 geolocator，按需 override 对齐 |
| wakelock_plus | `wakelock_plus_ohos`（pub.dev 0.0.2+） | |
| file_picker | `openharmony-sig/fluttertpc_file_picker`（gitcode，git 依赖） | |
| path_provider | `path_provider_ohos`（官方 flutter_packages） | federated 自动注册 |
| shared_preferences | `shared_preferences_ohos`（官方） | federated |
| url_launcher | `url_launcher_ohos`（官方） | federated |
| http / archive / lpinyin | 纯 Dart，天然支持 | 无需处理 |

## 四、已知坑 / 风险
- **Flutter 版本对齐**：主项目 3.29.3 + 用了 `withValues`（3.27+）。用 ohos 的 3.35.x-dev 分支可直接编译；若被迫用 3.22.x-ohos 稳定分支，需把全部 `.withValues(alpha: x)` 退回 `.withOpacity(x)`。
- **插件版本 skew**：ohos fork 多基于旧版本，`flutter pub get` 可能报版本冲突，逐个 `dependency_overrides` 钉版本。
- **dev 分支稳定性**：oh-3.35.x-dev 非稳定版，遇引擎/构建怪问题属正常，必要时退到稳定分支 + 改 withValues。
- **签名**：sideload 用 DevEco debug 签名；不上架不需要 AppGallery 发布证书。

## 五、当前状态
- [ ] 本人装好 DevEco + HarmonyOS SDK（**卡这步**）
- [ ] clone flutter-ohos 分支 + flutter doctor 通过
- [ ] `flutter create --platforms ohos .`
- [ ] 插件 override 对齐 + `flutter pub get` 通过
- [ ] `flutter build hap` 出包 + 真机 sideload 验证
