# Plain Ubuntu instead of nvidia/cuda: PyTorch's wheels ship their own CUDA libraries,
# so the CUDA runtime in the old base image was ~2-3 GB of duplicate weight in every pull.
FROM ubuntu:24.04

# NVIDIA_* vars were inherited from the nvidia/cuda base; RunPod needs them to expose the GPU
ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    PIP_NO_CACHE_DIR=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget curl ca-certificates nano aria2 \
    python3 python3-pip python3-venv python3-dev build-essential \
       libgl1 libglib2.0-0 dotnet-sdk-8.0 dotnet-sdk-10.0 \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --break-system-packages "huggingface_hub[cli]" hf_transfer jupyterlab

# PyTorch in its own layer, BEFORE SwarmUI/ComfyUI. It's the biggest chunk of the image and
# rarely changes, so the weekly rebuild can reuse this layer instead of re-shipping it.
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130

# Everything below gets refreshed on each build (CACHEBUST is set by the workflow)
ARG CACHEBUST=1
RUN git clone --depth 1 https://github.com/mcmonkeyprojects/SwarmUI /opt/SwarmUI \
 && git clone --depth 1 https://github.com/comfyanonymous/ComfyUI /opt/SwarmUI/dlbackend/ComfyUI \
 && ln -s /opt/venv /opt/SwarmUI/dlbackend/ComfyUI/venv \
 && /opt/venv/bin/pip install -r /opt/SwarmUI/dlbackend/ComfyUI/requirements.txt
WORKDIR /opt/SwarmUI
RUN chmod +x launch-linux.sh launchtools/*.sh

# Pre-build Swarm so boot is fast. Writing last_build is essential: without it, Swarm's
# launcher thinks the build is stale and throws it away and rebuilds on EVERY boot.
RUN dotnet build src/SwarmUI.csproj --configuration Release -o src/bin/live_release \
 && git rev-parse HEAD > src/bin/last_build \
 && rm -rf /root/.nuget/packages src/obj

COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE 7801 8888
CMD ["/start.sh"]
