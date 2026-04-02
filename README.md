# TRELLIS.2 ComfyUI on RunPod

Generate 3D `.glb` models from images using Microsoft's TRELLIS.2-4B on RunPod GPU instances. Bypass HuggingFace Pro daily limits (~10 models/day) and generate ~90 models/hour.

## What's Included

| File | Purpose |
|------|---------|
| `setup.sh` | One-time pod setup — installs ComfyUI node + CUDA wheels |
| `s3.sh` | S3 commands: upload models/images, download results (no GPU needed) |
| `workflow.json` | Standard workflow (1024 voxels, 12 steps, 200K faces, ~40s) |
| `workflow-fast.json` | Fast workflow (512 voxels, 50K faces, 512px tex, ~6s) |
| `workflow-hq.json` | High quality workflow (1024 voxels, 20 steps, 2M faces, 4K tex, ~90s) |
| `batch.py` | Batch processing — queue a folder of images via ComfyUI API |
| `download.sh` | Alternative: pull `.glb` files via SSH/rsync |

## Setup

### Prerequisites

Configure AWS CLI with your RunPod S3 credentials:

```bash
aws configure --profile runpod
# Access Key ID: <your RunPod API key>
# Secret Access Key: <same RunPod API key>
# Region: us-il-1
# Output format: json
```

### 1. Create a Network Volume

Go to [RunPod](https://runpod.io) > Storage > create a **Network Volume** in **IL-1** region (50 GB).

### 2. Upload Models to Volume (no GPU needed)

From your local machine:

```bash
./s3.sh setup-models
```

Downloads ~17 GB from HuggingFace to a local cache (`.model-cache/`, resumable), then syncs to the network volume via S3. Re-running skips already-downloaded files.

### 3. Install ComfyUI Node (needs GPU pod once)

1. Deploy a pod in **IL-1**: **L40S** spot ($0.26/hr, 48 GB VRAM) with **ComfyUI** community template
2. Attach your network volume, container disk 20 GB
3. In the pod terminal:

```bash
git clone https://github.com/johnhkchen/trellis-comfyui.git /workspace/trellis-setup
bash /workspace/trellis-setup/setup.sh
```

Models are already on the volume, so this only installs the node + wheels (~2 min). Stop the pod when done.

## Usage

### Workflow: Upload, Process, Download

```bash
# 1. Upload images to network volume (free — no GPU)
./s3.sh upload ./my-images/

# 2. Start GPU pod, process in pod terminal:
python3 /workspace/trellis-setup/batch.py /workspace/ComfyUI/input/

# 3. Stop GPU pod, download results (free — no GPU)
./s3.sh download ./generated/
```

GPU time is spent **only** on inference. All file transfer goes through S3.

### Interactive Mode

1. Start your GPU pod
2. Open ComfyUI in browser (RunPod provides the URL)
3. Drag a workflow `.json` onto the canvas
4. Load an image, click **Queue Prompt**
5. `.glb` appears in the 3D preview and in `/workspace/ComfyUI/output/`

### S3 Commands

All free — no GPU pod needed:

```bash
./s3.sh setup-models            # One-time: download TRELLIS.2 weights (~17 GB)
./s3.sh upload ./images/        # Upload images to network volume
./s3.sh download ./generated/   # Download .glb results
./s3.sh ls                      # List root of volume
./s3.sh ls ComfyUI/output/      # List generated files
```

Uses the `runpod` AWS CLI profile by default. Override with `AWS_PROFILE=other ./s3.sh ...`

## GPU Options

| GPU | VRAM | Cost (IL-1 spot) | Speed (1024 voxels) | Notes |
|-----|------|-------------------|---------------------|-------|
| L40S | 48 GB | ~$0.26/hr | ~35s per model | Best value, plenty of VRAM |
| RTX 4090 | 24 GB | ~$0.20-0.30/hr | ~40s per model | Tight at 1024 but works |
| A100 80GB | 80 GB | ~$1.20/hr | ~17s per model | Can do 1536 resolution |
| H100 | 80 GB | ~$2.00/hr | ~17s per model | Fastest |

## Cost Breakdown

Generating 100 models on L40S spot:
- GPU time: 100 models x 35s = ~58 min = ~$0.25
- File transfer: free (S3 API to network volume)
- Network volume: ~$0.07/day for 50 GB

**Total: ~$0.30 for 100 models** vs HuggingFace Pro limit of 10/day.

## Workflow Presets

Drag any of these into ComfyUI. All settings are tweakable in the node UI.

| Workflow | Resolution | Steps | Faces | Texture | Speed (L40S) | Use case |
|----------|-----------|-------|-------|---------|-------------|----------|
| `workflow-fast.json` | 512 | 12 | 50K | 512px | ~6s | Bulk generation, mobile |
| `workflow.json` | 1024 | 12 | 200K | 1024px | ~35s | General purpose |
| `workflow-hq.json` | 1024 | 20 | 2M | 4096px | ~80s | Hero/showcase assets |

**Key settings to tweak** (in the Generate node):
- `resolution`: `512` (fast) or `1024_cascade` (quality)
- `ss_steps` / `shape_steps` / `tex_steps`: more steps = better quality, slower (12-20)
- `guidance`: 7.5 default. Lower = more creative, higher = more faithful to input
- `seed_mode`: `randomize` for variety, `fixed` to reproduce exact results

**Post-process node:**
- `target_faces`: lower = smaller file (50K for mobile, 200K standard, 2M for hero)
- `texture_size`: 512 / 1024 / 2048 / 4096
- `remesher`: `Cumesh` (best quality)

## Pipeline Integration

Generated `.glb` files feed directly into [glb-optimizer](https://github.com/johnhkchen/glb-optimizer) for LOD generation, Blender remesh, billboard impostors, compression, and stress testing.

```
[Image] → TRELLIS.2 (RunPod) → .glb → GLB Optimizer (local) → LODs + Billboards → Scene
```
