# Handoff：全球鸟类媒体采集流水线

> 交接给 Codex 继续。截至交接时，脚本已写好部署到服务器，**图片采集+压缩已验证可用**，音频/文字/manifest 写入尚未完整验证。

## 目标

为 `world_birds.json`（11,227 种）每个物种采集并压缩后存入服务器 `/data/species/`：
- **鸣声**：xeno-canto（最佳 song+call，转码压缩 + 频谱图）
- **图片**：iNaturalist（**仅 CC 授权**，压缩 JPG）
- **文字**：Wikipedia（中文优先，英文兜底）

最终目的：让 App 可以从服务器下载全球任意鸟种的媒体。预计总占用 **5–8 GB**（服务器 /data 目前 43GB 空闲，够）。

## 脚本位置与设计

- **脚本**：`root@your-server-ip:/data/server/ingest_world_birds.py`（本地副本在仓库 `/tmp` 或可从服务器拉）
- **运行方式**：服务器端直接跑，文件直落 `/data/species/{Genus_species}/{images,audio,audio_spectrograms}/` + 写 `manifest.json`
- **断点续传**：`is_complete(key)` 判断 manifest 已有 images+audio 就跳过；可反复跑
- **CLI**：
  ```
  --xeno-key   xeno-canto API key（音频必需）
  --start N    起始下标（默认 0）
  --limit N    本批数量（0=全部）
  --delay S    每种间隔秒（默认 1.0，限速用）
  --sources    image,audio,text（可只跑部分）
  --overwrite  强制重抓
  ```
- **压缩参数**（脚本顶部常量）：
  - 图片：长边 ≤1600，JPEG q82，目标 ≤500KB
  - 音频：截前 **30 秒**，单声道 AAC **64kbps**（`-t 30 -ac 1 -c:a aac -b:a 64k`）
  - 频谱图：`showspectrumpic=s=900x334` JPEG q:v 5

## 已验证 / 未验证状态

| 模块 | 状态 |
|---|---|
| iNat 图片下载 + CC 许可过滤 + Pillow 压缩 | ✅ **已验证**：鸵鸟 `Struthio_camelus.jpg` 已生成，241KB（压缩生效） |
| manifest.json 写入 | ⚠️ **存疑**：测试后鸵鸟目录有图但**没看到 manifest.json**，需排查（可能进程没跑完 `ingest_one` 收尾，或路径/权限问题）。**Codex 首要任务：跑单种确认 manifest 正常落盘** |
| xeno-canto 音频 + 频谱图 | ❌ **未测**：缺 xeno-canto API key（用户的那个 key 是 **eBird** 的，xeno 要单独注册一个 key） |
| Wikipedia 文字 | ❌ **未验证**：逻辑写了（zh→en，REST summary API），需实跑确认 `extract` 能拿到 |

## Codex 接手步骤

1. **拿 xeno-canto API key**（向用户要，或 https://xeno-canto.org 注册）。eBird key 不能用。
2. **排查 manifest 写入**：
   ```
   ssh root@your-server-ip
   cd /data/server
   python3 ingest_world_birds.py --start 1 --limit 1 --sources image,text --overwrite
   cat /data/species/<那一种>/manifest.json   # 确认有 images / description 字段
   ```
   若没写 manifest，检查 `ingest_one()` 末尾的 `mp.write_text(...)` 是否被异常打断。
3. **测全流程小批**（带 xeno key，5 种）：
   ```
   python3 ingest_world_birds.py --xeno-key XXXX --start 0 --limit 5
   ```
   确认 images/audio/audio_spectrograms 三个目录都有文件、manifest 字段齐全、许可署名正确。
4. **正式全量**（后台 + 日志 + 可续传）：
   ```
   nohup python3 ingest_world_birds.py --xeno-key XXXX --delay 1.0 > /data/ingest.log 2>&1 &
   tail -f /data/ingest.log
   ```
   中断后再跑同样命令会自动跳过已完成的。预计 11,227 种 × (网络+转码) ≈ 数小时到一两天。
5. **跑完收尾**：
   - 刷新搜索索引：服务器有 `update_index()`（在 upload_server.py），跑一次或 `systemctl restart birdaholic-upload`
   - 确认新写入的 `spectrogram_url` / `url` 都是 `https://birding.today`（脚本里 `PUBLIC_BASE` 已是 https）

## 合规要点（务必保持）

- **iNat 仅 CC**：脚本已过滤 `license_code` 必须以 `cc` 开头，空值（保留所有权利）跳过。**不要放宽**，否则侵权。
- **xeno-canto**：保存 `rec`（录音者）+ XC 链接 + `lic`。
- **Wikipedia**：CC BY-SA，保存 `description_source` 链接。
- **不要用 eBird/Macaulay 的图**：默认版权所有，不可批量下载。
- App 是**非商业**用途，CC-BY-NC 等也可用，但仍需署名。

## 服务器环境

- `ffmpeg`：有 `aac` + `libfdk_aac` ✅
- `Pillow 12.2.0` + `pillow-heif` ✅
- `/data/server/world_birds.json`：11,227 种（字段 sci/en/zh/order/family/code）
- `/data/species/{key}/manifest.json` 结构：`{sci, cn, en, order, family, images:[{file,url,contributor,contributor_url,source,license}], audio:[{file,url,type,contributor,...,spectrogram,spectrogram_url}], description, ...}`
- 磁盘：50G 盘，43G 空闲

## 已知优化点（可选，Codex 酌情）

- 音频 30 秒截断已能砍体积；若仍大可降到 48kbps 或 20 秒
- iNat `order_by=votes` 取第一张 CC 图；可加多张备选
- 可加 GBIF 作为图片兜底（但必须逐条查 license）
- 可加并发（线程池）提速，但注意各 API 限速礼貌（iNat 建议 ≤1 req/s，xeno 类似）

## 相关已完成上下文（同一服务器，别覆盖）

- `/data/server/upload_server.py`：`/api/upload` 已重新接上 `_compress_image`（HEIC/PNG→JPG）；频谱图生成已改 900x334 JPG
- 全站媒体 URL 已是 https://birding.today（之前 935 频谱图 + 图片已批量转 JPG，547MB→32MB）
- 内置包 `china_common_100_v1.2`（41.5MB）
