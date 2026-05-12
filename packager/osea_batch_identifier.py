#!/usr/bin/env python3
"""Minimal local batch bird image identifier for OSEA.

This tool is intentionally small: choose OSEA's ONNX model and bird_info.json,
drop in images or folders, run local batch inference, then export CSV.

Expected default model files:
  models/osea/bird_model.onnx
  models/osea/bird_info.json
"""

from __future__ import annotations

import argparse
import csv
import json
import queue
import threading
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    _TkBase = tk.Tk
except ImportError:
    tk = None  # type: ignore[assignment]
    ttk = None  # type: ignore[assignment]
    filedialog = None  # type: ignore[assignment]
    messagebox = None  # type: ignore[assignment]
    _TkBase = object  # type: ignore[assignment,misc]


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}
MODEL_URL = "https://huggingface.co/sunjiao/osea/resolve/main/bird_model.onnx"
INFO_URL = "https://huggingface.co/sunjiao/osea/resolve/main/bird_info.json"
EBIRD_API = "https://api.ebird.org/v2"
EBIRD_CACHE_DIR = Path.home() / ".cache" / "osea_ebird"
EBIRD_CACHE_TTL = 7 * 24 * 3600  # 7 天


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_model_path() -> Path:
    return repo_root() / "models/osea/bird_model.onnx"


def default_info_path() -> Path:
    return repo_root() / "models/osea/bird_info.json"


@dataclass
class Prediction:
    rank: int
    index: int
    score: float
    sci: str = ""
    en: str = ""
    zh: str = ""
    code: str = ""

    @property
    def label(self) -> str:
        names = [name for name in [self.zh, self.en, self.sci] if name]
        return " / ".join(names) if names else f"class_{self.index}"


@dataclass
class ImageResult:
    image: Path
    status: str = "pending"
    error: str = ""
    predictions: list[Prediction] = field(default_factory=list)
    elapsed_ms: int = 0
    sharpness: float = 0.0
    exposure: float = 0.0
    stars: int = 0

    def top(self, rank: int = 1) -> Prediction | None:
        if len(self.predictions) < rank:
            return None
        return self.predictions[rank - 1]


def require_runtime() -> tuple[Any, Any, Any]:
    missing: list[str] = []
    try:
        import numpy as np
    except ImportError:
        np = None
        missing.append("numpy")
    try:
        import onnxruntime as ort
    except ImportError:
        ort = None
        missing.append("onnxruntime")
    try:
        from PIL import Image, ImageOps
    except ImportError:
        Image = None
        ImageOps = None
        missing.append("pillow")

    if missing:
        raise RuntimeError(
            "缺少依赖："
            + ", ".join(missing)
            + "\n请先运行：python3 -m pip install onnxruntime pillow numpy"
        )
    return np, ort, (Image, ImageOps)


def load_bird_info(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        rows = data
    elif isinstance(data, dict):
        for key in ["birds", "species", "classes", "labels", "data"]:
            value = data.get(key)
            if isinstance(value, list):
                rows = value
                break
        else:
            # Some label files are {"0": {...}, "1": {...}}.
            indexed: list[tuple[int, Any]] = []
            for key, value in data.items():
                try:
                    indexed.append((int(key), value))
                except (TypeError, ValueError):
                    continue
            if not indexed:
                raise ValueError("无法识别 bird_info.json 结构")
            rows = [value for _, value in sorted(indexed)]
    else:
        raise ValueError("无法识别 bird_info.json 结构")

    normalized: list[dict[str, Any]] = []
    for row in rows:
        if isinstance(row, str):
            normalized.append({"sci": row})
            continue
        if not isinstance(row, dict):
            normalized.append({})
            continue
        normalized.append(
            {
                "sci": row.get("sci")
                or row.get("scientific_name")
                or row.get("scientificName")
                or row.get("latin")
                or row.get("name")
                or "",
                "en": row.get("en")
                or row.get("english")
                or row.get("common_name")
                or row.get("commonName")
                or "",
                "zh": row.get("zh")
                or row.get("cn")
                or row.get("chinese")
                or row.get("中文名")
                or "",
                "code": row.get("code") or row.get("ebird_code") or "",
            }
        )
    return normalized


class EbirdFilter:
    """Fetch eBird species list for a region and build a location prior.

    After calling fetch(), call build_prior(n_classes) to get a float32 array
    of logit offsets indexed to the model's output classes.  Local species get
    +boost/2; non-local get -boost/2.  Adding this to raw logits before
    softmax nudges results toward locally recorded birds without ignoring the
    model's visual evidence.
    """

    def __init__(self, region: str, api_key: str, labels: list[dict[str, Any]]):
        self.region = region.strip()
        self.api_key = api_key.strip()
        self.labels = labels
        # Index: lowercase scientific name → model output index
        self._sci_to_idx: dict[str, int] = {
            lab.get("sci", "").lower(): i
            for i, lab in enumerate(labels)
            if lab.get("sci")
        }
        self.local_sci: set[str] = set()
        self.matched: int = 0
        self.total_ebird: int = 0

    # ------------------------------------------------------------------ public

    def fetch(self) -> str:
        """Pull region species list from eBird (cached 7 days). Returns status."""
        codes = self._fetch_region_codes()
        self.total_ebird = len(codes)
        sci_names = self._codes_to_sci(codes)
        self.local_sci = {s.lower() for s in sci_names}
        self.matched = sum(1 for s in self.local_sci if s in self._sci_to_idx)
        return (
            f"eBird [{self.region}]：{self.total_ebird} 种 → "
            f"{self.matched} 种与模型匹配"
        )

    def build_prior(self, n_classes: int, boost: float = 3.0) -> Any:
        """Return float32 logit-offset array of length n_classes."""
        import numpy as np
        prior = np.full(n_classes, -boost / 2, dtype=np.float32)
        for sci_lower, idx in self._sci_to_idx.items():
            if sci_lower in self.local_sci:
                prior[idx] = boost / 2
        return prior

    # ----------------------------------------------------------------- private

    def _fetch_region_codes(self) -> list[str]:
        cache_key = f"spplist_{self.region}.json"
        cached = self._load_cache(cache_key)
        if cached is not None:
            return cached
        url = f"{EBIRD_API}/product/spplist/{self.region}"
        req = urllib.request.Request(url, headers={"X-eBirdApiToken": self.api_key})
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read())
        except Exception as exc:
            raise RuntimeError(f"eBird spplist 请求失败：{exc}") from exc
        self._save_cache(cache_key, data)
        return data

    def _fetch_taxonomy(self) -> list[dict[str, Any]]:
        cache_key = "ebird_taxonomy.json"
        cached = self._load_cache(cache_key)
        if cached is not None:
            return cached
        url = f"{EBIRD_API}/ref/taxonomy/ebird?fmt=json&cat=species"
        req = urllib.request.Request(url, headers={"X-eBirdApiToken": self.api_key})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
        except Exception as exc:
            raise RuntimeError(f"eBird taxonomy 请求失败：{exc}") from exc
        self._save_cache(cache_key, data)
        return data

    def _codes_to_sci(self, codes: list[str]) -> list[str]:
        taxonomy = self._fetch_taxonomy()
        code_to_sci = {entry["speciesCode"]: entry["sciName"] for entry in taxonomy}
        return [code_to_sci[c] for c in codes if c in code_to_sci]

    def _cache_path(self, key: str) -> Path:
        EBIRD_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        return EBIRD_CACHE_DIR / key

    def _load_cache(self, key: str) -> Any:
        path = self._cache_path(key)
        if not path.exists():
            return None
        if time.time() - path.stat().st_mtime > EBIRD_CACHE_TTL:
            return None
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None

    def _save_cache(self, key: str, data: Any) -> None:
        self._cache_path(key).write_text(json.dumps(data), encoding="utf-8")


class OseaIdentifier:
    def __init__(
        self,
        model_path: Path,
        info_path: Path,
        top_k: int = 5,
        location_prior: Any = None,
    ):
        self.model_path = model_path
        self.info_path = info_path
        self.top_k = top_k
        self.np, ort, image_modules = require_runtime()
        self.Image, self.ImageOps = image_modules
        self.labels = load_bird_info(info_path)
        self.location_prior = location_prior  # float32 ndarray or None
        self.session = ort.InferenceSession(
            str(model_path),
            providers=["CPUExecutionProvider"],
        )
        self.input = self.session.get_inputs()[0]
        self.input_name = self.input.name
        self.height, self.width = self._infer_hw(self.input.shape)

    def _infer_hw(self, shape: list[Any]) -> tuple[int, int]:
        dims = [dim for dim in shape if isinstance(dim, int)]
        if len(dims) >= 3:
            return dims[-2], dims[-1]
        return 224, 224

    def preprocess(self, image_path: Path) -> Any:
        img = self.Image.open(image_path)
        img = self.ImageOps.exif_transpose(img).convert("RGB")
        scale = max(self.width / img.width, self.height / img.height)
        resized = img.resize(
            (max(self.width, round(img.width * scale)), max(self.height, round(img.height * scale))),
            self.Image.Resampling.BICUBIC,
        )
        left = (resized.width - self.width) // 2
        top = (resized.height - self.height) // 2
        cropped = resized.crop((left, top, left + self.width, top + self.height))

        arr = self.np.asarray(cropped).astype("float32") / 255.0
        mean = self.np.array([0.485, 0.456, 0.406], dtype="float32")
        std = self.np.array([0.229, 0.224, 0.225], dtype="float32")
        arr = (arr - mean) / std
        arr = arr.transpose(2, 0, 1)[None, :, :, :]
        return arr

    def predict(self, image_path: Path) -> ImageResult:
        started = time.perf_counter()
        result = ImageResult(image=image_path, status="running")
        try:
            result.sharpness, result.exposure = self.quality_score(image_path)
            x = self.preprocess(image_path)
            outputs = self.session.run(None, {self.input_name: x})
            logits = self.np.asarray(outputs[0]).reshape(-1).astype("float32")
            if self.location_prior is not None:
                n = min(len(logits), len(self.location_prior))
                logits[:n] = logits[:n] + self.location_prior[:n]
            scores = self._softmax(logits)
            top_indices = scores.argsort()[-self.top_k :][::-1]
            preds: list[Prediction] = []
            for rank, index in enumerate(top_indices.tolist(), start=1):
                label = self.labels[index] if 0 <= index < len(self.labels) else {}
                preds.append(
                    Prediction(
                        rank=rank,
                        index=index,
                        score=float(scores[index]),
                        sci=str(label.get("sci", "") or ""),
                        en=str(label.get("en", "") or ""),
                        zh=str(label.get("zh", "") or ""),
                        code=str(label.get("code", "") or ""),
                    )
                )
            result.predictions = preds
            result.stars = self.star_rating(preds[0].score if preds else 0, result.sharpness, result.exposure)
            result.status = "ok"
        except Exception as exc:
            result.status = "failed"
            result.error = str(exc)
        result.elapsed_ms = round((time.perf_counter() - started) * 1000)
        return result

    def quality_score(self, image_path: Path) -> tuple[float, float]:
        img = self.Image.open(image_path)
        img = self.ImageOps.exif_transpose(img).convert("L")
        img.thumbnail((512, 512))
        arr = self.np.asarray(img).astype("float32") / 255.0
        if arr.size == 0:
            return 0.0, 0.0
        gy, gx = self.np.gradient(arr)
        sharpness = float(self.np.mean(gx * gx + gy * gy))
        exposure = float(self.np.mean(arr))
        return sharpness, exposure

    def star_rating(self, top_score: float, sharpness: float, exposure: float) -> int:
        exposure_ok = 0.16 <= exposure <= 0.88
        sharp_ok = sharpness >= 0.0025
        if top_score >= 0.60 and sharp_ok and exposure_ok:
            return 3
        if top_score >= 0.35 and (sharp_ok or exposure_ok):
            return 2
        if top_score >= 0.15:
            return 1
        return 0

    def _softmax(self, values: Any) -> Any:
        values = values - self.np.max(values)
        exp = self.np.exp(values)
        total = self.np.sum(exp)
        if not self.np.isfinite(total) or total <= 0:
            return exp
        return exp / total


def collect_images(paths: list[Path]) -> list[Path]:
    images: list[Path] = []
    seen: set[str] = set()
    for path in paths:
        path = path.expanduser().resolve()
        candidates = path.rglob("*") if path.is_dir() else [path]
        for item in candidates:
            if not item.is_file() or item.suffix.lower() not in IMAGE_EXTS:
                continue
            key = str(item.resolve())
            if key in seen:
                continue
            seen.add(key)
            images.append(item)
    return sorted(images)


def write_csv(
    results: list[ImageResult],
    output_path: Path,
    top_k: int,
    location: str = "",
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["file", "location", "status", "stars", "sharpness", "exposure", "error", "elapsed_ms"]
    for rank in range(1, top_k + 1):
        fields.extend(
            [
                f"rank{rank}_score",
                f"rank{rank}_zh",
                f"rank{rank}_en",
                f"rank{rank}_sci",
                f"rank{rank}_code",
            ]
        )
    with output_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for result in results:
            row: dict[str, Any] = {
                "file": str(result.image),
                "location": location,
                "status": result.status,
                "stars": result.stars,
                "sharpness": f"{result.sharpness:.5f}",
                "exposure": f"{result.exposure:.3f}",
                "error": result.error,
                "elapsed_ms": result.elapsed_ms,
            }
            for rank in range(1, top_k + 1):
                pred = result.top(rank)
                row[f"rank{rank}_score"] = f"{pred.score:.5f}" if pred else ""
                row[f"rank{rank}_zh"] = pred.zh if pred else ""
                row[f"rank{rank}_en"] = pred.en if pred else ""
                row[f"rank{rank}_sci"] = pred.sci if pred else ""
                row[f"rank{rank}_code"] = pred.code if pred else ""
            writer.writerow(row)


class BatchIdentifierApp(_TkBase):
    def __init__(self) -> None:
        super().__init__()
        self.title("鸟瘾 OSEA 批量识别")
        self.geometry("1180x720")
        self.model_var = tk.StringVar(value=str(default_model_path()))
        self.info_var = tk.StringVar(value=str(default_info_path()))
        self.status_var = tk.StringVar(value="请选择图片或文件夹")
        self.top_k_var = tk.IntVar(value=5)
        self.images: list[Path] = []
        self.results: list[ImageResult] = []
        self._worker: threading.Thread | None = None
        self._queue: queue.Queue[ImageResult | str] = queue.Queue()
        self._build_ui()
        self.after(100, self._poll_queue)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill=tk.BOTH, expand=True)

        model_frame = ttk.LabelFrame(root, text="OSEA 模型")
        model_frame.pack(fill=tk.X)
        self._path_row(model_frame, "模型", self.model_var, self._choose_model)
        self._path_row(model_frame, "标签", self.info_var, self._choose_info)
        buttons = ttk.Frame(model_frame)
        buttons.pack(fill=tk.X, padx=8, pady=(0, 8))
        ttk.Button(buttons, text="下载模型文件", command=self._download_model_files).pack(side=tk.LEFT)
        ttk.Label(
            buttons,
            text="依赖：python3 -m pip install onnxruntime pillow numpy",
            foreground="#666",
        ).pack(side=tk.LEFT, padx=12)

        toolbar = ttk.Frame(root)
        toolbar.pack(fill=tk.X, pady=10)
        ttk.Button(toolbar, text="添加图片", command=self._add_images).pack(side=tk.LEFT)
        ttk.Button(toolbar, text="添加文件夹", command=self._add_folder).pack(side=tk.LEFT, padx=6)
        ttk.Button(toolbar, text="清空", command=self._clear).pack(side=tk.LEFT)
        ttk.Label(toolbar, text="Top").pack(side=tk.LEFT, padx=(18, 4))
        ttk.Spinbox(toolbar, from_=1, to=20, width=4, textvariable=self.top_k_var).pack(side=tk.LEFT)
        ttk.Button(toolbar, text="开始识别", command=self._start).pack(side=tk.LEFT, padx=12)
        ttk.Button(toolbar, text="导出 CSV", command=self._export_csv).pack(side=tk.LEFT)

        columns = ("file", "status", "top1", "score1", "top2", "top3", "time", "error")
        self.table = ttk.Treeview(root, columns=columns, show="headings", height=22)
        headings = {
            "file": "文件",
            "status": "状态",
            "top1": "Top 1",
            "score1": "分数",
            "top2": "Top 2",
            "top3": "Top 3",
            "time": "耗时",
            "error": "错误",
        }
        widths = {
            "file": 320,
            "status": 70,
            "top1": 230,
            "score1": 70,
            "top2": 210,
            "top3": 210,
            "time": 70,
            "error": 220,
        }
        for col in columns:
            self.table.heading(col, text=headings[col])
            self.table.column(col, width=widths[col], anchor=tk.W)
        self.table.pack(fill=tk.BOTH, expand=True)

        bottom = ttk.Frame(root)
        bottom.pack(fill=tk.X, pady=(8, 0))
        ttk.Label(bottom, textvariable=self.status_var).pack(side=tk.LEFT)

    def _path_row(self, parent: ttk.Frame, label: str, variable: tk.StringVar, command: Any) -> None:
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, padx=8, pady=4)
        ttk.Label(row, text=label, width=6).pack(side=tk.LEFT)
        ttk.Entry(row, textvariable=variable).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(row, text="选择", command=command).pack(side=tk.LEFT, padx=(6, 0))

    def _choose_model(self) -> None:
        path = filedialog.askopenfilename(filetypes=[("ONNX model", "*.onnx"), ("All files", "*")])
        if path:
            self.model_var.set(path)

    def _choose_info(self) -> None:
        path = filedialog.askopenfilename(filetypes=[("JSON", "*.json"), ("All files", "*")])
        if path:
            self.info_var.set(path)

    def _download_model_files(self) -> None:
        target_dir = default_model_path().parent
        target_dir.mkdir(parents=True, exist_ok=True)
        try:
            self.status_var.set("正在下载 OSEA 模型和 bird_info.json...")
            self.update_idletasks()
            urllib.request.urlretrieve(MODEL_URL, default_model_path())
            urllib.request.urlretrieve(INFO_URL, default_info_path())
            self.model_var.set(str(default_model_path()))
            self.info_var.set(str(default_info_path()))
            self.status_var.set("模型文件已下载")
        except Exception as exc:
            messagebox.showerror("下载失败", str(exc))
            self.status_var.set("下载失败")

    def _add_images(self) -> None:
        paths = filedialog.askopenfilenames(
            filetypes=[("Images", "*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff"), ("All files", "*")]
        )
        self._append_paths([Path(path) for path in paths])

    def _add_folder(self) -> None:
        path = filedialog.askdirectory()
        if path:
            self._append_paths([Path(path)])

    def _append_paths(self, paths: list[Path]) -> None:
        existing = {str(path.resolve()) for path in self.images}
        for image in collect_images(paths):
            if str(image.resolve()) not in existing:
                self.images.append(image)
        self.results = [ImageResult(image=image) for image in self.images]
        self._refresh_table()
        self.status_var.set(f"已载入 {len(self.images)} 张图片")

    def _clear(self) -> None:
        if self._worker and self._worker.is_alive():
            messagebox.showinfo("正在识别", "请等待当前识别结束后再清空。")
            return
        self.images = []
        self.results = []
        self._refresh_table()
        self.status_var.set("已清空")

    def _start(self) -> None:
        if self._worker and self._worker.is_alive():
            return
        if not self.images:
            messagebox.showinfo("没有图片", "请先添加图片或文件夹。")
            return
        model_path = Path(self.model_var.get()).expanduser()
        info_path = Path(self.info_var.get()).expanduser()
        if not model_path.exists() or not info_path.exists():
            messagebox.showerror("缺少模型", "请先选择或下载 bird_model.onnx 和 bird_info.json。")
            return
        self.results = [ImageResult(image=image, status="pending") for image in self.images]
        self._refresh_table()
        self.status_var.set("正在加载模型...")
        self._worker = threading.Thread(
            target=self._run_batch,
            args=(model_path, info_path, max(1, int(self.top_k_var.get()))),
            daemon=True,
        )
        self._worker.start()

    def _run_batch(self, model_path: Path, info_path: Path, top_k: int) -> None:
        try:
            identifier = OseaIdentifier(model_path, info_path, top_k=top_k)
            self._queue.put("model_loaded")
            for image in self.images:
                self._queue.put(identifier.predict(image))
            self._queue.put("done")
        except Exception as exc:
            self._queue.put(f"fatal:{exc}")

    def _poll_queue(self) -> None:
        try:
            while True:
                item = self._queue.get_nowait()
                if item == "model_loaded":
                    self.status_var.set("模型已加载，正在批量识别...")
                elif item == "done":
                    ok = sum(1 for result in self.results if result.status == "ok")
                    self.status_var.set(f"识别完成：{ok}/{len(self.results)} 成功")
                elif isinstance(item, str) and item.startswith("fatal:"):
                    messagebox.showerror("识别失败", item.removeprefix("fatal:"))
                    self.status_var.set("识别失败")
                elif isinstance(item, ImageResult):
                    for index, result in enumerate(self.results):
                        if result.image == item.image:
                            self.results[index] = item
                            break
                    self._refresh_table()
        except queue.Empty:
            pass
        self.after(120, self._poll_queue)

    def _refresh_table(self) -> None:
        for item in self.table.get_children():
            self.table.delete(item)
        for result in self.results:
            p1 = result.top(1)
            p2 = result.top(2)
            p3 = result.top(3)
            self.table.insert(
                "",
                tk.END,
                values=(
                    str(result.image),
                    result.status,
                    p1.label if p1 else "",
                    f"{p1.score:.3f}" if p1 else "",
                    p2.label if p2 else "",
                    p3.label if p3 else "",
                    f"{result.elapsed_ms} ms" if result.elapsed_ms else "",
                    result.error,
                ),
            )

    def _export_csv(self) -> None:
        if not self.results:
            messagebox.showinfo("没有结果", "没有可导出的识别结果。")
            return
        path = filedialog.asksaveasfilename(
            defaultextension=".csv",
            filetypes=[("CSV", "*.csv"), ("All files", "*")],
        )
        if not path:
            return
        write_csv(self.results, Path(path), max(1, int(self.top_k_var.get())))
        self.status_var.set(f"已导出 {path}")


def run_cli(args: argparse.Namespace) -> int:
    images = collect_images([Path(path) for path in args.input])
    if not images:
        print("No images found.")
        return 1

    location_prior = None
    location_str = ""
    if getattr(args, "location", None) and getattr(args, "ebird_key", None):
        labels = load_bird_info(Path(args.info))
        ebird = EbirdFilter(args.location, args.ebird_key, labels)
        try:
            status = ebird.fetch()
            print(status)
            location_prior = ebird.build_prior(n_classes=len(labels))
            location_str = args.location
        except Exception as exc:
            print(f"eBird 加载失败（跳过地点过滤）：{exc}")

    identifier = OseaIdentifier(
        Path(args.model), Path(args.info),
        top_k=args.top_k,
        location_prior=location_prior,
    )
    results = [identifier.predict(image) for image in images]
    write_csv(results, Path(args.output), args.top_k, location=location_str)
    ok = sum(1 for result in results if result.status == "ok")
    print(f"Done: {ok}/{len(results)} images. CSV: {args.output}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Batch identify bird images with local OSEA ONNX model.")
    parser.add_argument("--model", default=str(default_model_path()))
    parser.add_argument("--info", default=str(default_info_path()))
    parser.add_argument("--input", nargs="*", help="Image files or folders. If omitted, open GUI.")
    parser.add_argument("--output", default="osea_predictions.csv")
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--location", default="", help="eBird region code, e.g. CN-53 or US-NY")
    parser.add_argument("--ebird-key", default="", help="eBird API key")
    args = parser.parse_args()

    if args.input:
        return run_cli(args)
    if tk is None:
        print("错误：当前 Python 没有 tkinter，无法启动 GUI。请用 SwiftUI 版外壳或换有 Tk 的 Python。")
        return 1
    try:
        app = BatchIdentifierApp()
        app.mainloop()
    except Exception as exc:
        try:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("启动失败", str(exc))
            root.destroy()
        except Exception:
            print(f"启动失败: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
