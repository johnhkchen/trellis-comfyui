#!/usr/bin/env bash
#
# Download generated .glb files from a RunPod instance.
#
# Usage:
#   ./download.sh <runpod-ip> [output-dir]
#
# Examples:
#   ./download.sh 123.45.67.89
#   ./download.sh 123.45.67.89 ./models
#   RUNPOD_SSH_KEY=~/.ssh/runpod ./download.sh 123.45.67.89
#
set -euo pipefail

RUNPOD_IP="${1:?Usage: ./download.sh <runpod-ip> [output-dir]}"
OUTPUT_DIR="${2:-./generated}"
SSH_KEY="${RUNPOD_SSH_KEY:-~/.ssh/id_ed25519}"
REMOTE_DIR="/workspace/ComfyUI/output"

mkdir -p "$OUTPUT_DIR"

echo "Downloading .glb files from $RUNPOD_IP:$REMOTE_DIR → $OUTPUT_DIR/"
rsync -avz --include='*.glb' --exclude='*' \
    -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    "root@${RUNPOD_IP}:${REMOTE_DIR}/" \
    "$OUTPUT_DIR/"

echo ""
echo "Downloaded files:"
ls -lh "$OUTPUT_DIR"/*.glb 2>/dev/null || echo "  (none)"
