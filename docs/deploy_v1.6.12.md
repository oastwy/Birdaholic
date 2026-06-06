# 部署清单：v1.6.12 服务器端改动

> ⚠️ **关键**：仓库里的 `server/upload_server.py` 是旧版，**没有 `_compress_image`**。
> **不要** `scp` 本地文件覆盖线上 `/data/server/upload_server.py`，否则会丢图片压缩功能。
> 正确做法：在**线上文件**里手工/脚本插入下面 3 个反馈端点。

---

## 1. 反馈 / 纠错 API（修复纠错审核 404）

### 1.1 在线上 `/data/server/upload_server.py` 顶部 import 区加入
```python
import secrets      # 如果已存在可跳过
import threading
```

### 1.2 在常量区（`USERS_FILE = ...` 附近）加入
```python
FEEDBACK_FILE = Path("/data/server/feedback.json")
_feedback_lock = threading.Lock()
```

### 1.3 在 `_require_admin(...)` 函数之后，粘贴整段反馈端点
（完整代码见仓库 `server/upload_server.py` 中
`# ── 用户反馈 / 纠错 ──` 到 `admin_feedback_resolve` 结束的区块，
共三个端点：`POST /api/feedback`、`GET /api/admin/feedback`、
`POST /api/admin/feedback/resolve`，外加 `_resolve_user_soft / _load_feedback / _save_feedback` 三个辅助函数。）

### 1.4 重启并自检
```bash
systemctl restart birdaholic-upload.service
systemctl status birdaholic-upload.service --no-pager | head
# 自检（用 role=admin 的 token）
curl -s "https://birding.today/api/admin/feedback?token=<ADMIN_TOKEN>" | head
# 应返回 [] 或反馈数组，而不是 404
# 顺手确认压缩函数还在：
grep -c "_compress_image" /data/server/upload_server.py   # 必须 >0
```

---

## 2. APK 国内直连下载（不再依赖 GitHub）

### 2.1 放置 APK
```bash
mkdir -p /data/download
cp /path/to/Birdaholic_v1.6.12_android.apk /data/download/
ln -sf /data/download/Birdaholic_v1.6.12_android.apk \
       /data/download/Birdaholic_latest_android.apk   # 可选：稳定下载链接
```

### 2.2 nginx 加 location（`/etc/nginx/sites-available/birding.today` 的 server 块内）
```nginx
location /download/ {
    alias /data/download/;
    autoindex off;
    add_header Content-Disposition "attachment";
}
```
```bash
nginx -t && systemctl reload nginx
# 自检
curl -sI https://birding.today/download/Birdaholic_v1.6.12_android.apk | head
```

### 2.3 改 download.html（服务器上）
主下载按钮指向国内直连：
`https://birding.today/download/Birdaholic_v1.6.12_android.apk`
保留 GitHub Release 作为备用链接。版本号替换：
```bash
sed -i -E 's#v1\.6\.[0-9]+#v1.6.12#g' /data/.../download.html
```

---

## 3. 数据质量（非代码，需人工）

- 难度筛选：当前数据包 108 张图都是难度 1，只有 3 张 2/3 星 → 筛选「看起来无效」。
  需在服务器给图片打难度分（`/api/set_image_difficulty`）才有区分度。
- 发现脏数据：闪卡里出现过**战斗机照片**（误标成某鸟种）。需在服务器
  `/data/species/<误标物种>/` 里找出并删除该图，或走纠错审核流程剔除。
