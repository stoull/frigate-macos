FROM python:3.11 AS build

RUN apt-get update && apt-get install --no-install-recommends -y cmake libgl1 git && rm -rf /var/lib/apt/lists/*

WORKDIR /yolov9
RUN git clone --depth 1 https://github.com/WongKinYiu/yolov9.git .

# 1) 先装 CPU 版 PyTorch，避免 requirements.txt 拉 CUDA 大包
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# 2) 装其余依赖（带完整子依赖，避免 traitlets 等缺失）
RUN grep -viE '^(torch|torchvision)' requirements.txt > requirements-no-torch.txt && \
    pip install --no-cache-dir -r requirements-no-torch.txt

# 3) ONNX 导出工具（onnxsim 勿用 uv 装）
RUN pip install --no-cache-dir onnx==1.18.0 onnxruntime onnxsim==0.4.36 onnxscript

ARG MODEL_SIZE=t
ARG IMG_SIZE=320

ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt

RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py

RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --simplify --include onnx

FROM scratch
ARG MODEL_SIZE=t
ARG IMG_SIZE=320
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
