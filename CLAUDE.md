# SwarmUI RunPod template — notes for Claude

The owner's RunPod image for SwarmUI + ComfyUI. GitHub Actions builds it and pushes it to
`ghcr.io/snaggleuk/509m83v89u46murjgerhrhlkthjrr94:latest`. A push to `main` triggers a build,
and so does the weekly Monday 04:00 UTC schedule. **Merging to main publishes the image that
RunPod pulls.** The owner has said (Nov 2026): don't ask before merging. Work on a branch, then merge
it to main yourself once the change is ready, and tell them it's building.

## Files
- `dockerfile`: the image (lowercase name, so don't rename it).
- `start.sh`: runs at pod boot. It symlinks `Models/Output/Data` into `/workspace/swarm` (the
  persistent volume), starts Jupyter on port 8888 (password = `JUPYTER_PASSWORD` env), then SwarmUI on 7801.
- `.github/workflows/build.yml`: buildx with the GHA layer cache. `CACHEBUST=run_id` forces a
  fresh clone of SwarmUI/ComfyUI every build; everything above that line is cached.

## Layer order matters (for boot speed and pull size)
1. apt + dotnet, then 2. PyTorch, then 3. SageAttention. These are cached and rarely change.
4. After `ARG CACHEBUST`: SwarmUI + ComfyUI are cloned fresh each build, then Swarm is pre-built.
   Writing `src/bin/last_build` is essential, or Swarm rebuilds itself on every boot.
Don't put anything slow or rarely-changing below `CACHEBUST`.

## PyTorch is frozen on purpose (Nov 2026)
- `ARG TORCH_VERSION=2.15.0`, `TORCH_CUDA=cu132`, `CUDA_PKG=13-2`.
- We moved from cu130 because PyTorch stopped building for CUDA 13.0 (late Sept 2026).
- `/opt/torch-lock.txt` + `ENV PIP_CONSTRAINT` lock torch/torchvision for every later pip
  install (ComfyUI requirements, custom nodes). This stops anything from silently upgrading torch,
  which would break the compiled SageAttention.

### How to upgrade PyTorch
1. Pick a version that exists on `https://download.pytorch.org/whl/<cuXXX>` for cp312 (Ubuntu 24.04 = Python 3.12).
2. Change all three ARGs together: `TORCH_VERSION`, `TORCH_CUDA` (e.g. `cu134`) and `CUDA_PKG`
   (the NVIDIA apt suffix, e.g. `13-4`; it must match torch's CUDA major.minor).
3. Expect the SageAttention compile to rerun (~15–20 min on GitHub's runner).
4. Check RunPod host drivers support that CUDA version (CUDA 13.x needs driver 580+).
5. Do it on a branch, merge it (no need to ask), then watch the Actions run and report the result.

## SageAttention 2 (added Nov 2026)
- This is compiled from source (`thu-ml/SageAttention`) inside the image against the frozen torch.
  There's no official Linux wheel, and community wheels break on torch changes.
- The CUDA compiler is installed, used and deleted in the same `RUN` so the image doesn't grow by GBs.
- GitHub runners have no GPU, so the target architectures come from `ARG SAGE_ARCHS="8.6;8.9;12.0"`:
  - 8.6 = Ampere (RTX A4500, 3090, A40, A6000), 8.9 = Ada (RTX 4090, L40S),
    12.0 = Blackwell (RTX PRO 4500/6000 Blackwell, RTX 5090).
  - The owner mostly uses the **RTX 4090 (8.9)** and the **RTX PRO 4500 Blackwell (12.0)**. Their "4500"
    means the Blackwell one; leaving 12.0 out once caused "no kernel image is available".
  - To support more cards add 8.0 (A100), 9.0 (H100) or 10.0 (B200). Each one adds compile time.
  - Check a card's compute capability with:
    `python -c "import torch; print(torch.cuda.get_device_capability())"`
- torch 2.15+ requires C++20; Sage's setup.py hardcodes `-std=c++17`, so the Dockerfile seds it to
  c++20 before building (first build failed on exactly this, Nov 2026).
- The build ends with `import sageattention` so a broken compile fails the build loudly.
- **Turning it on** is a runtime setting, not something in this repo: SwarmUI → Server → Backends →
  ComfyUI Self-Starting → ExtraArgs `--use-sage-attention`. That's stored in
  `/workspace/swarm/Data` on the owner's volume. Remove the flag to turn it off.
- Expected gain: ~10–25% on Flux-type image models, less on SDXL, and much more on video models.
  Output differs slightly from stock attention.

## Owner preferences
- Fast pod boot and a small image are priorities. Keep heavy work at build time, not in `start.sh`.
- Explain trade-offs plainly. Challenge ideas rather than just agreeing.

## Image tags and rollback (Nov 2026)
- Every build pushes `:latest` and a dated tag `:YYYY-MM-DD-<run_id>`.
- If a weekly rebuild breaks (bad upstream SwarmUI/ComfyUI commit), point the RunPod template's
  image at the last good dated tag until it's fixed. Find the tags on the repo's Packages page.
