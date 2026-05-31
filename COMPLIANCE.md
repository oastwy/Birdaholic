# 鸟瘾综合征 Birdaholic — 合规说明

> 最后更新：2026-05-29 · 版本 1.6.0

本文档记录 App 正式发布前的合规自查与处理，供应用商店上架、备案核验、内部留档使用。

## 基本信息

| 项目 | 内容 |
|---|---|
| App 名称 | 鸟瘾综合征（Birdaholic） |
| 运营者 / 备案主体 | 伍洋（自然人，个人备案） |
| 品牌名 | 奇趣自然团队 |
| ICP 备案号 | 粤ICP备2026057758号-2A |
| 服务器 | 腾讯云（中国境内），域名 birding.today |
| 商业性质 | 完全免费、无广告、非商业 |
| 第三方 SDK | 无（无统计/广告/推送/社交 SDK） |

## 权限清单（最终 APK / IPA）

### Android
- `INTERNET` — 网络请求
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` — 仅"按位置查询附近鸟种"时使用
- `READ_EXTERNAL_STORAGE`（maxSdkVersion=32）— 读取用户选择的数据包文件

### iOS
- `NSLocationWhenInUseUsageDescription` — 仅使用时定位，无后台
- `NSPhotoLibraryUsageDescription` — 选择上传的照片
- 已移除：相机、麦克风、后台定位、相册写入、明文加载（NSAllowsArbitraryLoads）

## 个人信息处理

- 学习记录、收藏、笔记、设置：**仅存本机** SharedPreferences，不上传。
- 上传媒体（照片/录音 + 署名/描述）：**用户主动触发**，发往自有服务器（境内）。
- 位置坐标：仅在用户主动用"按位置查询"时，由**用户设备直接发往 eBird（美国）**，我方不接收、不存储 → 已在隐私政策列为数据出境。

## 数据出境

| 第三方 | 出境内容 | 触发 | 地区 |
|---|---|---|---|
| eBird (Cornell Lab) | 位置坐标 / 地区代码 + 用户自有 API Key | 用户主动使用"按位置/地区查询" | 美国 |
| GitHub | 仅请求版本号，无个人信息 | 检查更新 | 美国 |

eBird 功能为可选；不配置 eBird API Key 即无任何数据出境。

## 数据来源与许可

| 来源 | 用途 | 许可 |
|---|---|---|
| eBird | 名录、物种代码、省级名录 | eBird API 条款，非商业用途，已署名 |
| AviList | 分类系统 | CC BY 4.0 |
| 郑光美《中国鸟类分类与分布名录》 | 中国名录 | 学术引用 |
| Xeno-canto | 录音 | CC BY-SA / BY-NC 等 |
| iNaturalist | 照片 | CC BY-NC / BY-SA 等 |
| Wikimedia Commons | 照片 | CC0 / CC BY / BY-SA |
| 用户贡献 | 照片/录音 | CC BY-NC 4.0（仅受邀用户上传，管理员审核后公开） |

## eBird API 合规处理

- ✅ 非商用（条款要求）
- ✅ 全程署名 eBird.org（省份下载界面 + 数据声明页 + 隐私政策）
- ✅ 不分享 API Key：每用户填写并使用自己的 key，本地直连
- ⚠️ 内置 34 省名录由开发者 key 预拉取并打包 → 已发邮件向 eBird 报备非商用再分发（见 `docs/ebird_permission_email.md`）

## 合规自查清单

- [x] 首次启动隐私政策 + 用户协议同意框（不同意退出）
- [x] 隐私政策含：收集清单、第三方共享清单、数据出境、账号注销
- [x] 用户协议含：CC BY-NC 4.0 上传授权、受邀上传与管理员审核、行为规范、免责、争议解决
- [x] 全站 HTTPS（已消除明文 HTTP）
- [x] 最小必要权限，移除未使用权限
- [x] 无第三方 SDK
- [x] ICP 备案号 App 内展示
- [x] 运营主体（伍洋）三处一致：备案 / App内声明 /（待确认）商店账号
- [ ] **待办**：应用商店开发者账号需为"伍洋"实名，与备案主体一致
- [ ] **待办**：eBird 邮件报备回复留档
