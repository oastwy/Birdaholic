# 鸟瘾综合征 Birdaholic

鸟类闪卡学习 App，支持鸟图、鸟鸣识别训练，结合 eBird 地点筛选当地鸟种。

## 下载安装

**Android**：下载测试包 [`Birdaholic_v1.3.3_android.apk`](releases/Birdaholic_v1.3.3_android.apk)。
校验值见 [`Birdaholic_v1.3.3_android.apk.sha256`](releases/Birdaholic_v1.3.3_android.apk.sha256)。

**iOS 内测**：通过 TestFlight 加入：https://testflight.apple.com/join/RbF8btWg

## 主要功能

- 本地/服务器数据包管理鸟图和鸟鸣
- eBird 地点筛选，按国家/地区限制鸟种名录
- 学习模式（直接显示答案）和复习模式（点击后显示答案）
- 图片闪卡、音频闪卡、多选题三种题型
- 整包 ZIP 下载 + 按地区逐物种下载，支持断点续传
- 管理员上传模式，可推送图片/音频到服务器

## v1.3.3 更新说明

- 内置“中国常见鸟 100”数据包，安装后不填 API key 也能直接开始学习。
- 内置中国完整鸟类名录，可按中文名、英文名或拉丁名搜索并逐物种下载服务器媒体。
- 数据包管理移入设置页，底部导航更简洁；数据包名称显示为短名。
- 下载任务支持取消，已完成部分保留，后续可继续下载。
- 支持启用多个数据包叠加浏览和学习，单独下载的鸟种不会混进中国包。
- 图片题增加难度筛选；管理员可给图片设置 1-5 分难度，默认 1 分。
- 闪卡页补充图片和音频作者致谢显示。

## 技术栈

Flutter · Dart · eBird API · Xeno-Canto · iNaturalist
