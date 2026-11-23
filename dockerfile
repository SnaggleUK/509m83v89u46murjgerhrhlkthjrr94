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

# SageAttention 2 (faster attention kernels for ComfyUI; enabled with --use-sage-attention).
# There's no official Linux wheel, and community wheels break whenever torch changes, so we
# compile it here against the exact torch above. The CUDA compiler is installed, used and
# deleted inside this one RUN so it never ends up in the image (only the ~50 MB result does).
# GitHub's runners have no GPU, so the target cards are listed explicitly:
# 8.0 A100 | 8.6 RTX 3090/A40/A6000 | 8.9 RTX 4090/L40S | 9.0 H100/H200 | 10.0 B200 | 12.0 RTX 5090/PRO 6000
# Sits right after PyTorch so it's cached too - the slow compile only reruns when torch does.
ARG SAGE_ARCHS="8.0;8.6;8.9;9.0;10.0;12.0"
RUN wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
 && dpkg -i cuda-keyring_1.1-1_all.deb && rm cuda-keyring_1.1-1_all.deb \
 && apt-get update && apt-get install -y --no-install-recommends cuda-nvcc-13-0 cuda-libraries-dev-13-0 \
 && /opt/venv/bin/pip install setuptools wheel ninja packaging \
 && git clone --depth 1 https://github.com/thu-ml/SageAttention /tmp/sage \
 && cd /tmp/sage \
 && CUDA_HOME=/usr/local/cuda-13.0 PATH=/usr/local/cuda-13.0/bin:$PATH \
    TORCH_CUDA_ARCH_LIST="$SAGE_ARCHS" MAX_JOBS=2 EXT_PARALLEL=1 NVCC_APPEND_FLAGS="--threads 2" \
    /opt/venv/bin/pip install --no-build-isolation . \
 && cd / && rm -rf /tmp/sage \
 && apt-get purge -y --auto-remove cuda-nvcc-13-0 cuda-libraries-dev-13-0 cuda-keyring \
 && rm -rf /var/lib/apt/lists/* /usr/local/cuda* /root/.cache \
 && /opt/venv/bin/python -c "import sageattention; print('sageattention OK')"

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
