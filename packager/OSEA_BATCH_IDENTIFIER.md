# OSEA 批量鸟图识别工具

这是鸟瘾的最小版 Mac 本地鸟图识别工具。它不把模型打进仓库，只读取本地的 OSEA ONNX 模型和标签文件。

## 准备

安装依赖：

```bash
python3 -m pip install onnxruntime pillow numpy
```

模型默认放在：

```text
models/osea/bird_model.onnx
models/osea/bird_info.json
```

也可以在工具界面里点击“下载模型文件”，或手动从 Hugging Face 的 `sunjiao/osea` 下载这两个文件。

## 图形界面

双击：

```text
packager/run_osea_batch_identifier.command
```

然后添加图片或文件夹，点击“开始识别”，最后可导出 CSV。

## 命令行批处理

```bash
python3 packager/osea_batch_identifier.py \
  --input /path/to/images \
  --output /path/to/osea_predictions.csv \
  --top-k 5
```

如果模型不在默认位置，可以加：

```bash
--model /path/to/bird_model.onnx --info /path/to/bird_info.json
```
