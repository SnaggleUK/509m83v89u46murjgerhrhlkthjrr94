FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    HF_HUB_ENABLE_HF_TRANSFER=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget curl ca-certificates nano aria2 \
    python3 python3-pip python3-venv python3-dev build-essential \
    libgl1 libglib2.0-0 dotnet-sdk-8.0 \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --break-system-packages --no-cache-dir "huggingface_hub[cli]" hf_transfer

RUN git clone --depth 1 https://github.com/mcmonkeyprojects/SwarmUI /opt/SwarmUI
WORKDIR /opt/SwarmUI

# Install ComfyUI (the engine) for NVIDIA GPUs, using Swarm's own installer script
RUN chmod +x launch-linux.sh launchtools/*.sh && ./launchtools/comfy-install-linux.sh nv python3

# Pre-build Swarm so boot is fast
RUN dotnet build src/SwarmUI.csproj --configuration Release -o src/bin/live_release

COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE 7801
CMD ["/start.sh"]
