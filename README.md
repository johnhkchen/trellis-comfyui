# TRELLIS.2 ComfyUI on RunPod

Generate 3D `.glb` models from images using Microsoft's TRELLIS.2-4B on RunPod GPU instances.

## Quick Start

### 1. Create a RunPod Pod

1. Go to [RunPod](https://runpod.io) > Pods > Deploy
2. Select **RTX 4090** (24 GB, ~$0.40/hr) — use FP8 model variant
3. Use template: **RunPod ComfyUI** (community template)
4. Set container disk to **60 GB**
5. Set volume disk to **50 GB** (persists models between sessions)
6. Deploy and wait for it to start

### 2. Run Setup Script

Open a terminal in the pod (or use the web terminal) and run:

```bash
curl -sSL https://raw.githubusercontent.com/YOUR_REPO/trellis-comfyui/main/setup.sh | bash
```

Or clone this repo and run:

```bash
git clone https://github.com/YOUR_REPO/trellis-comfyui.git /tmp/trellis-setup
bash /tmp/trellis-setup/setup.sh
```

This installs the TRELLIS.2 ComfyUI node, downloads ~17 GB of models, and restarts ComfyUI.

### 3. Load the Workflow

1. Open ComfyUI in your browser (RunPod provides the URL)
2. Drag and drop `workflow.json` from this repo onto the canvas
3. Load an image into the "Load Image" node
4. Click **Queue Prompt**
5. The `.glb` file appears in `ComfyUI/output/`

### 4. Download Results

From the pod terminal:
```bash
# List generated files
ls /workspace/ComfyUI/output/*.glb

# Or use the download helper
python3 /tmp/trellis-setup/download.py
```

From your local machine (with RunPod CLI or rsync via SSH).

## GPU Options

| GPU | VRAM | Model | Cost | Speed (1024 voxels) |
|-----|------|-------|------|-------------------|
| RTX 4090 | 24 GB | FP8 variant | ~$0.40/hr | ~35-50s per model |
| A100 40GB | 40 GB | BF16 full | ~$1.10/hr | ~20-30s per model |
| A100 80GB | 80 GB | BF16 full | ~$1.60/hr | ~17s per model |
| H100 | 80 GB | BF16 full | ~$2.50/hr | ~17s per model |

## Output

Each generation produces a `.glb` file with:
- Textured mesh with PBR materials (base color, roughness, metallic)
- Decimated to target face count (default 200K faces)
- Ready for import into Blender, three.js, or GLB Optimizer
