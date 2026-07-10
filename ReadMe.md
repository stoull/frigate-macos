# Mac 上使用 Frigate

在 Apple Silicon Mac 上通过 Docker 运行 [Frigate](https://frigate.video/)，并用 [apple-silicon-detector](https://github.com/frigate-nvr/apple-silicon-detector) 调用 Neural Engine 做目标检测。整体流程如下：

1. 通过 Docker 用 `docker-compose.yml` 跑 Frigate
2. 使用 `config/config.yml` 配置摄像头与检测参数
3. 在宿主机安装并启动 `apple-silicon-detector`（硬件加速）
4. 用 `yolov9-export` 导出 ONNX 模型，放到 `config/model_cache/`
5. 按顺序启动 detector → Frigate，即可自主运行

---

## 前置条件

- Mac（Apple Silicon：M1 / M2 / M3 / M4）
- [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)（Apple Silicon 版）
- 可访问的 RTSP 摄像头流（本仓库示例为 `rtsp://hutpi.local:8554/picam`，请按实际环境修改）

---

## 步骤 1：通过 Docker 运行 Frigate

本仓库的 `docker-compose.yml` 已针对 macOS 做好适配：

- 使用 `ghcr.io/blakeblackshear/frigate:stable-standard-arm64` 镜像（ARM64）
- 将 `./config` 挂载为容器内 `/config`（配置与模型）
- 将 `./storage` 挂载为录像存储目录
- 通过 `host.docker.internal` 让容器访问宿主机上的 ZMQ 检测器
- Web UI 端口：`8971`（鉴权）、`5001`（无鉴权调试）

首次启动前创建录像目录：

```bash
mkdir -p storage
```

启动 Frigate（**请先完成步骤 3 的 detector 启动**，否则检测会失败）：

```bash
docker compose up -d
```

查看日志：

```bash
docker compose logs -f frigate
```

停止：

```bash
docker compose down
```

---

## 步骤 2：配置 Frigate（config.yml）

配置文件路径：`config/config.yml`。主要需关注以下几项。

### 检测器（ZMQ）

Frigate 在 Docker 容器内运行，检测推理在宿主机 Mac 上完成，通过 ZMQ 通信：

```yaml
detectors:
  apple-silicon:
    type: zmq
    endpoint: tcp://host.docker.internal:5555
```

### 模型

`model` 必须在根级别（不能写在 `detectors` 下面）：

```yaml
model:
  model_type: yolo-generic
  width: 320    # 须与导出 ONNX 时的 imgsize 一致
  height: 320
  input_tensor: nchw
  input_dtype: float
  path: /config/model_cache/yolov9-t-320.onnx
  labelmap_path: /labelmap/coco-80.txt
```

### 摄像头

按你的 RTSP 地址修改 `cameras` 段，例如：

```yaml
cameras:
  picam:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://你的摄像头地址:8554/stream
          input_args: preset-rtsp-restream
          roles:
            - detect
            - record
```

修改配置后重启 Frigate：

```bash
docker compose restart frigate
```

更多选项见 [Frigate 官方文档](https://docs.frigate.video/configuration/)。

---

## 步骤 3：配置 Apple Silicon 硬件加速（apple-silicon-detector）

Docker 容器内无法直接使用 Mac 的 Neural Engine。需要在**宿主机**单独运行 [apple-silicon-detector](https://github.com/frigate-nvr/apple-silicon-detector)，由它通过 CoreML 调用 Neural Engine 做推理。

### 方式 A：下载 App（推荐，无需终端）

1. 在 [Releases](https://github.com/frigate-nvr/apple-silicon-detector/releases) 下载 `FrigateDetector.app.zip`
2. 解压后打开 `FrigateDetector.app`（首次：右键 → 打开，绕过 Gatekeeper）
3. 终端窗口会自动创建 venv、安装依赖并启动检测器（默认监听 `tcp://*:5555`）

### 方式 B：源码编译

```bash
git clone https://github.com/frigate-nvr/apple-silicon-detector
cd apple-silicon-detector
make install
make run
```

### 验证

确认检测器在 `:5555` 监听后再启动 Frigate。启动顺序很重要：

1. **先**启动 `apple-silicon-detector`
2. **再** `docker compose up -d`

自定义端口示例：

```bash
make run ENDPOINT="tcp://*:5555"
```

---

## 步骤 4：导出 YOLOv9 ONNX 模型

Frigate **不会**自动下载检测模型，需自行导出 ONNX 并放入 `config/model_cache/`。

本仓库 `yolov9-export/` 目录提供了在 Docker 中导出模型的 Dockerfile，无需在 Mac 上手动配置 PyTorch 环境。

### 导出

在项目根目录执行：

```bash
docker build \
  --build-arg MODEL_SIZE=t \
  --build-arg IMG_SIZE=320 \
  --output . \
  -f yolov9-export/export-yolov9.Dockerfile .
```

构建完成后，根目录会生成 `yolov9-t-320.onnx`（首次约 5～15 分钟，视网络而定）。

### 放入 model_cache

```bash
mkdir -p config/model_cache
cp yolov9-t-320.onnx config/model_cache/
```

确保 `config.yml` 中 `model.path` 与文件名一致（当前为 `/config/model_cache/yolov9-t-320.onnx`），且 `width` / `height` 与导出时的 `IMG_SIZE` 相同。

### 更换模型规格（可选）

例如导出 640 输入的 `s` 版：

```bash
docker build \
  --build-arg MODEL_SIZE=s \
  --build-arg IMG_SIZE=640 \
  --output . \
  -f yolov9-export/export-yolov9.Dockerfile .
```

同时把 `config.yml` 里 `model.width`、`model.height` 改为 `640`，并更新 `model.path`。

更多细节见 [yolov9-export/README.md](yolov9-export/README.md)。

---

## 步骤 5：启动与访问

按以下顺序操作：

```bash
# 1. 宿主机：启动 apple-silicon-detector（App 或 make run）

# 2. 项目根目录：启动 Frigate
docker compose up -d

# 3. 打开 Web UI
open http://localhost:8971    # 鉴权 UI（推荐）
# 或
open http://localhost:5001    # 无鉴权调试 UI
```

首次访问 `8971` 会提示创建管理员账号。配置完成后，Frigate 会自主拉流、检测、录像，无需额外干预。

---

## 目录结构

```
frigate-macos/
├── ReadMe.md
├── docker-compose.yml          # Frigate 容器定义
├── config/
│   ├── config.yml              # Frigate 主配置
│   └── model_cache/
│       └── yolov9-t-320.onnx   # 检测模型（需自行导出）
├── storage/                    # 录像与快照（运行时生成）
└── yolov9-export/
    ├── export-yolov9.Dockerfile
    └── README.md
```

---

## 常见问题

| 现象 | 处理 |
|------|------|
| Frigate 连不上检测器 | 先启动 `apple-silicon-detector`，再启动 Frigate；确认 `endpoint: tcp://host.docker.internal:5555` |
| 检测无结果 / 框错位 | 确认 `model.width/height` 与导出时的 `IMG_SIZE` 一致 |
| 端口 5000 被占用 | macOS 上常被 AirPlay 占用；本仓库已改用 `5001:5000` |
| 模型导出失败 | 确认使用本仓库 `yolov9-export/export-yolov9.Dockerfile`，见 [yolov9-export/README.md](yolov9-export/README.md) |
| RTSP 连不上 | 检查摄像头地址、网络与 `ffmpeg.inputs` 配置 |

---

## 参考链接

- [Frigate 文档 — Apple Silicon Detector](https://docs.frigate.video/configuration/object_detectors/#apple-silicon-detector)
- [apple-silicon-detector](https://github.com/frigate-nvr/apple-silicon-detector)
- [YOLOv9](https://github.com/WongKinYiu/yolov9)
