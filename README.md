# TRELLIS.2 ComfyUI on RunPod

Generate 3D `.glb` models from images using Microsoft's TRELLIS.2-4B on RunPod. Bypass HuggingFace Pro daily limits (~10 models/day) and generate ~90 models/hour.

## How It Works

1. **CPU instance** (cheap) — install ComfyUI, node, download 17GB models to network volume
2. **GPU pod** (only when generating) — start ComfyUI, models are already there
3. **Local machine** — upload images, download .glb results via S3

GPU time is spent only on inference. Setup and file transfer cost almost nothing.

## Setup

### 1. Create a Network Volume

[RunPod](https://runpod.io) > Storage > **Network Volume** in **EU-RO-1** (50 GB).

### 2. Install on a CPU Instance

Deploy a **CPU** pod in the same region, attach the volume, then:

```bash
git clone https://github.com/johnhkchen/trellis-comfyui.git /workspace/trellis-setup
bash /workspace/trellis-setup/setup.sh
```

This installs ComfyUI + TRELLIS.2 node + downloads ~17 GB of models. Stop the CPU instance when done.

### 3. Generate on a GPU Pod

Deploy a **GPU** pod (same region, same volume):
- **RTX 4090** or **L40S** spot
- Container disk: 20 GB
- Attach your network volume

```bash
bash /workspace/trellis-setup/start-gpu.sh
```

Open ComfyUI in the browser, drag `workflow.json` onto the canvas, upload an image, Queue Prompt.

## File Transfer

### S3 Setup (one-time)

```bash
aws configure --profile runpod
# Access Key ID: <your RunPod API key>
# Secret Access Key: <same key>
# Region: eu-ro-1
# Output: json
```

### Commands

```bash
./s3.sh upload ./images/        # Upload input images (no GPU needed)
./s3.sh download ./generated/   # Download .glb results (no GPU needed)
./s3.sh ls                      # List volume
```

## Workflow Settings

All tweakable in the ComfyUI node UI:

- **Shape**: `ss_guidance`/`shape_guidance` 7.5, `steps` 12, `max_tokens` 49152 (=1024 voxels)
- **Texture**: `tex_guidance` 7.5, `tex_steps` 12
- **Export**: `decimation_target` 200K, `texture_size` 1024

## GPU Options (EU-RO-1 spot)

| GPU | VRAM | Cost | Speed |
|-----|------|------|-------|
| RTX 4090 | 24 GB | ~$0.20-0.30/hr | ~40s/model |
| L40S | 48 GB | ~$0.26/hr | ~35s/model |
| A100 80GB | 80 GB | ~$1.20/hr | ~17s/model |

## Pipeline

```
[Image] → TRELLIS.2 (RunPod GPU) → .glb → GLB Optimizer (local Mac) → LODs + Billboards → Scene
```
