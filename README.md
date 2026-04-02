# TRELLIS.2 ComfyUI on RunPod

Generate 3D `.glb` models from images using Microsoft's TRELLIS.2-4B on RunPod GPU instances. Bypass HuggingFace Pro daily limits (~10 models/day) and generate ~90 models/hour.

## What's Included

| File | Purpose |
|------|---------|
| `setup.sh` | One-time setup on RunPod — installs node, wheels, downloads ~17 GB of models |
| `workflow.json` | ComfyUI workflow — drag into browser UI for interactive use |
| `batch.py` | Batch processing — queue a folder of images via ComfyUI API |
| `download.sh` | Pull generated `.glb` files from RunPod to your local machine |

## Quick Start

### 1. Create a RunPod Pod

1. Go to [RunPod](https://runpod.io) > Pods > Deploy
2. Select **RTX 4090** (24 GB, ~$0.40/hr)
3. Use template: **RunPod ComfyUI** (community template)
4. Set container disk to **60 GB**
5. Set volume disk to **50 GB** (persists models between sessions)
6. Deploy and wait for it to start

### 2. Run Setup

Open the pod's web terminal and run:

```bash
git clone https://github.com/johnhkchen/trellis-comfyui.git /tmp/trellis-setup
bash /tmp/trellis-setup/setup.sh
```

Takes ~10 minutes (mostly downloading 17 GB of model weights). Only needed once if you use a persistent volume.

### 3. Generate Models

**Interactive (single models):**

1. Open ComfyUI in your browser (RunPod provides the URL)
2. Drag `workflow.json` onto the canvas
3. Load an image into the "Load Image" node
4. Click **Queue Prompt**
5. `.glb` appears in the 3D preview and in `/workspace/ComfyUI/output/`

**Batch (multiple images):**

```bash
# Upload images to the pod, then:
python3 /tmp/trellis-setup/batch.py /workspace/images/

# With custom settings:
python3 /tmp/trellis-setup/batch.py /workspace/images/ \
    --resolution 1024_cascade \
    --faces 200000 \
    --texture-size 1024
```

### 4. Download Results

From your local machine:

```bash
./download.sh <runpod-ip>
# or with custom output dir:
./download.sh <runpod-ip> ./my-models
```

Requires SSH access to the pod (RunPod provides this). Set `RUNPOD_SSH_KEY` if your key isn't at `~/.ssh/id_ed25519`.

## GPU Options

| GPU | VRAM | Cost | Speed (1024 voxels) | Notes |
|-----|------|------|---------------------|-------|
| RTX 4090 | 24 GB | ~$0.40/hr | ~40s per model | Best value |
| A100 40GB | 40 GB | ~$1.10/hr | ~25s per model | Comfortable headroom |
| A100 80GB | 80 GB | ~$1.60/hr | ~17s per model | Can do 1536 resolution |
| H100 | 80 GB | ~$2.50/hr | ~17s per model | Fastest |

## Workflow Settings

The default workflow generates at **1024 voxel** resolution with these settings:

- Structured latent steps: 12
- Shape steps: 12
- Texture steps: 12
- Guidance scale: 7.5 (all stages)
- Post-processing: 200K target faces, 1024px textures, CuMesh remesher
- Output: `.glb` with PBR materials (base color, roughness, metallic)

Edit the node values in ComfyUI to adjust. Lower resolution (`512`) is faster but lower quality.

## Pipeline Integration

The generated `.glb` files can be fed directly into [glb-optimizer](https://github.com/johnhkchen/glb-optimizer) for LOD generation, compression, and stress testing before use in production scenes.
