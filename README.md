# TRELLIS.2 ComfyUI on RunPod

Generate 3D `.glb` models from images using Microsoft's TRELLIS.2-4B on RunPod GPU instances. Bypass HuggingFace Pro daily limits (~10 models/day) and generate ~90 models/hour.

## What's Included

| File | Purpose |
|------|---------|
| `setup.sh` | One-time setup on RunPod — installs node, wheels, downloads ~17 GB of models |
| `workflow.json` | ComfyUI workflow — drag into browser UI for interactive use |
| `batch.py` | Batch processing — queue a folder of images via ComfyUI API |
| `s3.sh` | Upload images / download results via S3 API (no GPU pod needed) |
| `download.sh` | Alternative: pull `.glb` files via SSH/rsync |

## Quick Start

### 1. Create a Network Volume

Go to [RunPod](https://runpod.io) > Storage > create a **Network Volume** in **IL-1** region (50 GB).

### 2. One-time: Download Models to Volume (no GPU needed)

From your local machine, download TRELLIS.2 weights directly to the network volume via S3:

```bash
./s3.sh setup-models    # Downloads ~17 GB from HuggingFace → network volume
```

This runs locally, no GPU pod needed. The models land on the volume and persist forever.

### 3. One-time: Install ComfyUI Node (needs GPU pod briefly)

Start a GPU pod (RTX 4090 spot, ~$0.20/hr) attached to your volume, then:

```bash
git clone https://github.com/johnhkchen/trellis-comfyui.git /workspace/trellis-setup
bash /workspace/trellis-setup/setup.sh
```

Since models are already on the volume, this only installs the ComfyUI node + wheels (~2 min). Stop the pod when done.

### 4. Workflow: Upload, Process, Download

```bash
# Step 1: Upload images (free — no GPU pod)
./s3.sh upload ./my-images/

# Step 2: Start GPU pod, process in pod terminal:
python3 /workspace/trellis-setup/batch.py /workspace/ComfyUI/input/

# Step 3: Stop GPU pod, download results (free — no GPU pod)
./s3.sh download ./generated/
```

GPU time is spent **only** on inference. All file transfer goes through S3 for free.

**Or use ComfyUI interactively:**

1. Open ComfyUI in your browser (RunPod provides the URL)
2. Drag `workflow.json` onto the canvas
3. Load an image, click **Queue Prompt**
4. `.glb` appears in the 3D preview

### S3 Commands

All free — no GPU pod needed:

```bash
./s3.sh setup-models            # One-time: download TRELLIS.2 weights (~17 GB)
./s3.sh upload ./images/        # Upload images to network volume
./s3.sh download ./generated/   # Download .glb results
./s3.sh ls                      # List root of volume
./s3.sh ls ComfyUI/output/      # List generated files
```

Set `RUNPOD_BUCKET` if your bucket ID differs from the default.

## GPU Options

| GPU | VRAM | Cost (spot) | Speed (1024 voxels) | Notes |
|-----|------|-------------|---------------------|-------|
| RTX 4090 | 24 GB | ~$0.20-0.30/hr | ~40s per model | Best value |
| A100 40GB | 40 GB | ~$0.80/hr | ~25s per model | Comfortable headroom |
| A100 80GB | 80 GB | ~$1.20/hr | ~17s per model | Can do 1536 resolution |
| H100 | 80 GB | ~$2.00/hr | ~17s per model | Fastest |

## Cost Breakdown

Generating 100 models on RTX 4090 spot:
- GPU time: 100 models x 40s = ~67 min = ~$0.25
- Upload/download: free (S3 API to network volume)
- Network volume storage: ~$0.07/day for 50 GB

**Total: ~$0.30 for 100 models** vs HuggingFace Pro limit of 10/day.

## Workflow Settings

Default settings in `workflow.json`:

- Resolution: 1024 voxels (cascade)
- Steps: 12/12/12 (structured latent / shape / texture)
- Guidance: 7.5 (all stages)
- Post-processing: 200K target faces, 1024px textures, CuMesh remesher
- Output: `.glb` with PBR materials (base color, roughness, metallic)

## Pipeline Integration

Generated `.glb` files feed directly into [glb-optimizer](https://github.com/johnhkchen/glb-optimizer) for LOD generation, Blender remesh, billboard impostors, compression, and stress testing.

```
[Image] → TRELLIS.2 (RunPod) → .glb → GLB Optimizer (local) → LODs + Billboards → Scene
```
