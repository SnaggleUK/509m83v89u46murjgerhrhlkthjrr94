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
# Frozen on purpose: SageAttention below is compiled against this exact torch, so bumping it
# means a ~20 min recompile. To upgrade, change these three values together.
# (PyTorch has dropped CUDA 13.0 builds; 13.2 is their current default.)
ARG TORCH_VERSION=2.15.0
ARG TORCH_CUDA=cu132
ARG CUDA_PKG=13-2
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install "torch==${TORCH_VERSION}" torchvision --index-url https://download.pytorch.org/whl/${TORCH_CUDA} \
 && /opt/venv/bin/pip freeze | grep -E '^(torch|torchvision)==' > /opt/torch-lock.txt
# Every later pip install obeys this lock, so ComfyUI's requirements (or a custom node) can't
# silently swap torch for a newer one and break SageAttention.
ENV PIP_CONSTRAINT=/opt/torch-lock.txt

# SageAttention 2 (faster attention kernels for ComfyUI; enabled with --use-sage-attention).
# There's no official Linux wheel, and community wheels break whenever torch changes, so we
# compile it here against the exact torch above. torch 2.15+ headers need C++20 but Sage's
# setup.py still says C++17, hence the sed below (harmless once upstream catches up). The CUDA compiler is installed, used and
# deleted inside this one RUN so it never ends up in the image (only the ~50 MB result does).
# GitHub's runners have no GPU, so the target cards are listed explicitly. Only the two
# families actually used, to keep the compile short:
#   8.6 = Ampere (RTX A4500, 3090, A40, A6000)   8.9 = Ada (RTX 4090, RTX 4500 Ada, L40S)
# Other cards (A100, H100, 5090...) still work, just without SageAttention - add 8.0 / 9.0 / 12.0 here if needed.
ARG SAGE_ARCHS="8.6;8.9"
RUN wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
 && dpkg -i cuda-keyring_1.1-1_all.deb && rm cuda-keyring_1.1-1_all.deb \
 && apt-get update && apt-get install -y --no-install-recommends cuda-nvcc-${CUDA_PKG} cuda-libraries-dev-${CUDA_PKG} \
 && /opt/venv/bin/pip install setuptools wheel ninja packaging \
 && git clone --depth 1 https://github.com/thu-ml/SageAttention /tmp/sage \
 && cd /tmp/sage \
 && sed -i 's/-std=c++17/-std=c++20/g' setup.py \
 && CUDA_HOME=/usr/local/cuda PATH=/usr/local/cuda/bin:$PATH \
    TORCH_CUDA_ARCH_LIST="$SAGE_ARCHS" MAX_JOBS=4 \
    /opt/venv/bin/pip install --no-build-isolation . \
 && cd / && rm -rf /tmp/sage \
 && apt-get purge -y --auto-remove cuda-nvcc-${CUDA_PKG} cuda-libraries-dev-${CUDA_PKG} cuda-keyring \
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
