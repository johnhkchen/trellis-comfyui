# TRELLIS.2 ComfyUI on RunPod

Generate 3D `.glb` models from images using Microsoft's TRELLIS.2-4B on RunPod GPU instances. Bypass HuggingFace Pro daily limits (~10 models/day) and generate ~90 models/hour.

Uses [PozzettiAndrea/ComfyUI-TRELLIS2](https://github.com/PozzettiAndrea/ComfyUI-TRELLIS2) node (pip-installable, no binary wheel issues).

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | One-time pod setup — installs node + deps into ComfyUI venv |
| `workflow.json` | ComfyUI workflow — drag into browser UI |
| `s3.sh` | S3 commands: upload images, download results, setup models (no GPU needed) |
| `batch.py` | Queue a folder of images via ComfyUI API |
| `diagnose.sh` | Debug node installation issues |

## Setup

### Prerequisites

Configure AWS CLI with RunPod S3 credentials:

```bash
aws configure --profile runpod
# Access Key ID: <your RunPod API key>
# Secret Access Key: <same RunPod API key>
# Region: us-il-1
# Output format: json
```

### 1. Create a Network Volume

[RunPod](https://runpod.io) > Storage > **Network Volume** in **IL-1** region (50 GB).

### 2. Deploy a Pod

In IL-1, select:
- GPU: **RTX 4090** or **L40S** spot
- Template: **ComfyUI** (RunPod slim community template)
- Container disk: **20 GB**
- Attach your network volume

### 3. Install (run once on the pod)

```bash
git clone https://github.com/johnhkchen/trellis-comfyui.git /workspace/trellis-setup
bash /workspace/trellis-setup/setup.sh
```

Restart ComfyUI after install (Manager > Restart, or restart the pod).

Models auto-download from HuggingFace on first generation (~17 GB, cached in HF cache on the volume).

### 4. Generate

1. Open ComfyUI in browser
2. Drag `workflow.json` onto the canvas
3. Upload an image to the LoadImage node
4. Click **Queue Prompt**
5. `.glb` appears in 3D preview + `/workspace/runpod-slim/ComfyUI/output/`

### 5. Download Results

```bash
# From your local machine (no GPU needed):
./s3.sh download ./generated/
```

## S3 Commands

All free — no GPU pod needed:

```bash
./s3.sh upload ./images/        # Upload input images
./s3.sh download ./generated/   # Download .glb results
./s3.sh ls                      # List volume root
./s3.sh ls runpod-slim/ComfyUI/output/   # List outputs
```

Uses `runpod` AWS CLI profile. Override with `AWS_PROFILE=other ./s3.sh ...`

## Workflow Settings

All tweakable directly in the ComfyUI node UI:

**Shape generation:**
- `ss_guidance` / `shape_guidance`: 7.5 default (lower = creative, higher = faithful)
- `ss_steps` / `shape_steps`: 12 default (more = better, slower)
- `max_tokens`: 49152 for 1024 voxels

**Texture generation:**
- `tex_guidance`: 7.5 default
- `tex_steps`: 12 default

**Export:**
- `decimation_target`: 200K default (50K for mobile, 2M for hero assets)
- `texture_size`: 1024 default (512 for mobile, 4096 for hero)

## GPU Options

| GPU | VRAM | Spot Cost (IL-1) | Speed (1024 voxels) |
|-----|------|------------------|---------------------|
| RTX 4090 | 24 GB | ~$0.20-0.30/hr | ~40s per model |
| L40S | 48 GB | ~$0.26/hr | ~35s per model |
| A100 80GB | 80 GB | ~$1.20/hr | ~17s per model |

## Pipeline

```
[Image] → TRELLIS.2 (RunPod) → .glb → GLB Optimizer (local) → LODs + Billboards → Scene
```

Generated `.glb` files feed into [glb-optimizer](https://github.com/johnhkchen/glb-optimizer) for LOD generation, Blender remesh, billboard impostors, and stress testing.
