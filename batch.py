#!/usr/bin/env python3
"""
Batch image-to-3D generation via ComfyUI API.

Usage:
    # On RunPod, after setup.sh:
    python3 batch.py /path/to/images/

    # Or with specific output directory:
    python3 batch.py /path/to/images/ --output /workspace/ComfyUI/output/

    # Customize generation settings:
    python3 batch.py /path/to/images/ --resolution 512 --faces 100000

This queues each image through the TRELLIS.2 ComfyUI workflow and waits
for completion. Results are .glb files in the output directory.
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

COMFYUI_URL = os.environ.get("COMFYUI_URL", "http://127.0.0.1:8188")


def upload_image(filepath):
    """Upload an image to ComfyUI and return the filename."""
    import mimetypes
    boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
    filename = os.path.basename(filepath)
    mime_type = mimetypes.guess_type(filepath)[0] or "image/png"

    with open(filepath, "rb") as f:
        file_data = f.read()

    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="image"; filename="{filename}"\r\n'
        f"Content-Type: {mime_type}\r\n\r\n"
    ).encode() + file_data + f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(
        f"{COMFYUI_URL}/upload/image",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())
    return result.get("name", filename)


def build_prompt(image_name, resolution="1024_cascade", target_faces=200000,
                 texture_size=1024, seed=42, output_name="Trellis2Mesh"):
    """Build a ComfyUI prompt (workflow) for TRELLIS.2 image-to-3D."""
    return {
        "6": {
            "class_type": "LoadImage",
            "inputs": {"image": image_name},
        },
        "7": {
            "class_type": "Trellis2PreProcessImage",
            "inputs": {"image": ["6", 0], "padding": 0},
        },
        "8": {
            "class_type": "Trellis2LoadModel",
            "inputs": {},
        },
        "10": {
            "class_type": "Trellis2MeshWithVoxelGenerator",
            "inputs": {
                "pipeline": ["8", 0],
                "image": ["7", 0],
                "seed": seed,
                "seed_mode": "randomize",
                "resolution": resolution,
                "ss_steps": 12,
                "shape_steps": 12,
                "tex_steps": 12,
                "ss_guidance": 7.5,
                "shape_guidance": 7.5,
                "tex_guidance": 7.5,
                "max_faces": 999999,
            },
        },
        "12": {
            "class_type": "Trellis2PostProcessAndUnWrapAndRasterizer",
            "inputs": {
                "mesh": ["10", 0],
                "bvh": ["10", 1],
                "target_faces": target_faces,
                "texture_size": texture_size,
                "remesher": "Cumesh",
            },
        },
        "14": {
            "class_type": "Trellis2ExportMesh",
            "inputs": {
                "trimesh": ["12", 0],
                "filename": output_name,
                "format": "glb",
                "overwrite": True,
            },
        },
    }


def queue_prompt(prompt):
    """Queue a prompt and return the prompt_id."""
    data = json.dumps({"prompt": prompt}).encode()
    req = urllib.request.Request(
        f"{COMFYUI_URL}/prompt",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())
    return result["prompt_id"]


def wait_for_completion(prompt_id, timeout=300):
    """Poll until the prompt is complete or errors out."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            resp = urllib.request.urlopen(f"{COMFYUI_URL}/history/{prompt_id}")
            history = json.loads(resp.read())
            if prompt_id in history:
                status = history[prompt_id].get("status", {})
                if status.get("completed", False):
                    return True
                if status.get("status_str") == "error":
                    print(f"  ERROR: {history[prompt_id].get('error', 'unknown')}")
                    return False
        except urllib.error.URLError:
            pass
        time.sleep(2)
    print(f"  TIMEOUT after {timeout}s")
    return False


def main():
    parser = argparse.ArgumentParser(description="Batch TRELLIS.2 image-to-3D generation")
    parser.add_argument("input_dir", help="Directory of input images (.png, .jpg, .webp)")
    parser.add_argument("--output", default=None, help="Output directory (default: ComfyUI/output/)")
    parser.add_argument("--resolution", default="1024_cascade", choices=["512", "1024_cascade", "1536_cascade"],
                        help="Voxel resolution (default: 1024_cascade)")
    parser.add_argument("--faces", type=int, default=200000, help="Target face count (default: 200000)")
    parser.add_argument("--texture-size", type=int, default=1024, help="Texture resolution (default: 1024)")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout per model in seconds (default: 300)")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    if not input_dir.is_dir():
        print(f"Error: {input_dir} is not a directory")
        sys.exit(1)

    # Find all images
    image_exts = {".png", ".jpg", ".jpeg", ".webp"}
    images = sorted([f for f in input_dir.iterdir() if f.suffix.lower() in image_exts])

    if not images:
        print(f"No images found in {input_dir}")
        sys.exit(1)

    print(f"Found {len(images)} images to process")
    print(f"Resolution: {args.resolution}, Target faces: {args.faces}")
    print()

    # Check ComfyUI is reachable
    try:
        urllib.request.urlopen(f"{COMFYUI_URL}/system_stats")
    except urllib.error.URLError:
        print(f"Error: Cannot reach ComfyUI at {COMFYUI_URL}")
        print("Make sure ComfyUI is running and COMFYUI_URL is set correctly.")
        sys.exit(1)

    results = []
    for i, img_path in enumerate(images):
        name = img_path.stem
        print(f"[{i+1}/{len(images)}] Processing: {img_path.name}")

        # Upload image
        try:
            uploaded_name = upload_image(str(img_path))
        except Exception as e:
            print(f"  Upload failed: {e}")
            results.append((name, "upload_error"))
            continue

        # Build and queue prompt
        prompt = build_prompt(
            uploaded_name,
            resolution=args.resolution,
            target_faces=args.faces,
            texture_size=args.texture_size,
            output_name=name,
        )

        try:
            prompt_id = queue_prompt(prompt)
        except Exception as e:
            print(f"  Queue failed: {e}")
            results.append((name, "queue_error"))
            continue

        # Wait for completion
        start = time.time()
        success = wait_for_completion(prompt_id, timeout=args.timeout)
        elapsed = time.time() - start

        if success:
            print(f"  Done in {elapsed:.1f}s → {name}.glb")
            results.append((name, "ok"))
        else:
            results.append((name, "error"))

    # Summary
    print()
    print("=" * 50)
    ok = sum(1 for _, s in results if s == "ok")
    print(f"Complete: {ok}/{len(results)} succeeded")
    for name, status in results:
        icon = "+" if status == "ok" else "x"
        print(f"  [{icon}] {name}: {status}")


if __name__ == "__main__":
    main()
