# macOS Frigate + YOLOv9 模型导出

在 macOS（Apple Silicon）上运行 Frigate，并用 `apple-silicon-detector` 调用 Neural Engine 做目标检测。本目录包含 Docker Compose 配置，以及将 YOLOv9 导出为 ONNX 的 Dockerfile。

## 目录结构

```
macOS-Frigate/
├── docker-compose.yml          # Frigate 容器
├── config/
│   ├── config.yml              # Frigate 配置（含 ZMQ detector）
│   └── model_cache/
│       └── yolo.onnx           # 检测模型（需自行导出，见下文）
├── export-yolov9.Dockerfile    # YOLOv9 → ONNX 导出脚本
└── README.md
```

---

## export-yolov9.Dockerfile 说明

Frigate **不会**自动下载 `yolo.onnx`，需要自行准备 ONNX 模型。本 Dockerfile 在隔离的 Linux 容器里完成导出，避免在 Mac 上手动配 Python / PyTorch 环境。

### 它做什么

1. 克隆 [YOLOv9](https://github.com/WongKinYiu/yolov9) 源码
2. 安装 **CPU 版** PyTorch（不下载 NVIDIA CUDA 包，适合在 Mac 上构建）
3. 下载预训练权重 `yolov9-{t|s|m|c|e}-converted.pt`
4. 运行 `export.py`，生成简化后的 ONNX 文件

### 默认参数

| 参数 | 默认值 | 含义 |
|------|--------|------|
| `MODEL_SIZE` | `t` | 模型规格：`t`（最小最快）/ `s` / `m` / `c` / `e` |
| `IMG_SIZE` | `320` | 输入分辨率，须与 `config.yml` 里 `model.width/height` 一致 |

默认输出文件：`yolov9-t-320.onnx`

### 与官方脚本的区别

针对在 Mac 上用 Docker 构建时遇到的常见问题做了调整：

- 使用 CPU 版 PyTorch，避免下载数 GB 的 `nvidia-*` 包
- 用 `pip install onnxsim` 代替 `uv` 安装 `onnx-simplifier`（包名不兼容）
- 安装完整 Python 子依赖，避免 `traitlets` 等模块缺失

---

## 使用方法

### 前置条件

- 已安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)（Mac Apple Silicon 版）

### 1. 导出模型

在 `macOS-Frigate` 目录下执行：

```bash
cd macOS-Frigate

docker build \
  --build-arg MODEL_SIZE=t \
  --build-arg IMG_SIZE=320 \
  --output . \
  -f export-yolov9.Dockerfile .
```

构建完成后，当前目录会出现 `yolov9-t-320.onnx`（首次约 5～15 分钟，视网络而定）。

### 2. 放入 Frigate 配置目录

```bash
cp yolov9-t-320.onnx config/model_cache/yolo.onnx
```

`config.yml` 中已配置：

```yaml
model:
  path: /config/model_cache/yolo.onnx
  width: 320
  height: 320
```

若保留原文件名，只需把 `path` 改为 `/config/model_cache/yolov9-t-320.onnx`。

### 3. 更换模型规格（可选）

例如导出 640 输入的 `s` 版：

```bash
docker build \
  --build-arg MODEL_SIZE=s \
  --build-arg IMG_SIZE=640 \
  --output . \
  -f export-yolov9.Dockerfile .
```

同时修改 `config.yml` 中 `model.width`、`model.height` 为 `640`。

---

## 启动 Frigate

1. **宿主机**启动 `apple-silicon-detector`（监听 `:5555`）：

   ```bash
   cd apple-silicon-detector && make run
   ```

2. **再启动** Frigate：

   ```bash
   docker compose up -d
   ```

3. 打开 Web UI：`http://localhost:8971`

---

## 常见问题

| 现象 | 处理 |
|------|------|
| 构建时长时间下载 `nvidia-*` | 确认使用的是本目录的 `export-yolov9.Dockerfile`，而非官方带 `uv` 的原始脚本 |
| `onnx-simplifier` / `onnxsim` 安装失败 | 本 Dockerfile 已改用 `pip install onnxsim==0.4.36` |
| `ModuleNotFoundError: traitlets` | 已改为完整安装 requirements 子依赖；请用最新版 Dockerfile 重建 |
| Frigate 连不上检测器 | 先启动 `apple-silicon-detector`，再启动 Frigate；确认 `endpoint: tcp://host.docker.internal:5555` |
| 检测无结果 / 框错位 | 确认 `model.width/height` 与导出时的 `IMG_SIZE` 一致 |

---

## 参考链接

- [Frigate Object Detectors — Apple Silicon](https://docs.frigate.video/configuration/object_detectors/#apple-silicon-detector)
- [apple-silicon-detector](https://github.com/frigate-nvr/apple-silicon-detector)
- [YOLOv9 官方仓库](https://github.com/WongKinYiu/yolov9)
