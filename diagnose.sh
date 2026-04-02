#!/usr/bin/env bash
#
# Diagnose TRELLIS.2 ComfyUI node installation issues on RunPod.
# Run this on the pod and paste the output.
#
set -uo pipefail

echo "=== DIAGNOSE TRELLIS.2 ComfyUI Node ==="
echo ""

# 1. Find ComfyUI
echo "--- ComfyUI Location ---"
for d in /workspace/runpod-slim/ComfyUI /workspace/ComfyUI; do
    [ -d "$d" ] && echo "FOUND: $d"
done
COMFY=$(ls -d /workspace/runpod-slim/ComfyUI /workspace/ComfyUI 2>/dev/null | head -1)
echo "Using: $COMFY"
echo ""

# 2. Check node directory
echo "--- Node Directory ---"
ls -la "$COMFY/custom_nodes/" 2>/dev/null | grep -i trellis
echo ""

# 3. Check __init__.py exists
NODE="$COMFY/custom_nodes/ComfyUI-Trellis2"
echo "--- Node Files ---"
if [ -d "$NODE" ]; then
    echo "__init__.py: $(ls -la "$NODE/__init__.py" 2>/dev/null || echo 'MISSING')"
    echo "File count: $(find "$NODE" -type f | wc -l | tr -d ' ')"
else
    echo "NODE DIR MISSING: $NODE"
fi
echo ""

# 4. Python / torch info
echo "--- Python & Torch ---"
PYTHON="$COMFY/.venv-cu128/bin/python"
[ -f "$PYTHON" ] || PYTHON=$(which python3)
echo "Python: $PYTHON"
$PYTHON --version 2>&1
$PYTHON -c "import torch; print(f'Torch: {torch.__version__}, CUDA: {torch.cuda.is_available()}, Device: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')" 2>&1
echo ""

# 5. Check CUDA wheels
echo "--- CUDA Wheels ---"
for pkg in cumesh nvdiffrast nvdiffrec_render flex_gemm o_voxel; do
    $PYTHON -c "import $pkg; print('OK: $pkg')" 2>&1 || echo "FAIL: $pkg"
done
echo ""

# 6. Check other deps
echo "--- Python Dependencies ---"
for pkg in meshlib pymeshlab cv2 scipy rembg requests open3d; do
    $PYTHON -c "import $pkg" 2>/dev/null && echo "OK: $pkg" || echo "MISSING: $pkg"
done
echo ""

# 7. Try importing the node
echo "--- Import Test ---"
cd "$COMFY"
$PYTHON -c "
import sys, traceback
sys.path.insert(0, '.')
sys.path.insert(0, 'custom_nodes/ComfyUI-Trellis2')
try:
    exec(open('custom_nodes/ComfyUI-Trellis2/__init__.py').read())
    print('IMPORT: OK')
except Exception as e:
    print(f'IMPORT FAILED: {e}')
    traceback.print_exc()
" 2>&1
echo ""

# 8. Check ComfyUI log for trellis errors
echo "--- ComfyUI Log (trellis/error) ---"
LOG="$COMFY/user/comfyui.log"
if [ -f "$LOG" ]; then
    grep -i "trellis\|error.*import\|ModuleNotFound\|cannot import" "$LOG" 2>/dev/null | tail -20
    echo "(from $LOG)"
else
    echo "Log not found at $LOG"
fi
echo ""
echo "=== END DIAGNOSIS ==="
