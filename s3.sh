#!/usr/bin/env bash
#
# Upload images / download .glb files via RunPod S3 API.
# No GPU pod needed for file transfer — works directly with the network volume.
#
# Usage:
#   ./s3.sh upload ./images/          # Upload images before starting GPU pod
#   ./s3.sh download [output-dir]     # Download .glb results after processing
#   ./s3.sh ls [path]                 # List files on the volume
#
# Environment:
#   RUNPOD_BUCKET   - S3 bucket name (default: hl1vwr8frk)
#   RUNPOD_REGION   - Region (default: us-il-1)
#   RUNPOD_ENDPOINT - S3 endpoint (default: https://s3api-us-il-1.runpod.io)
#
set -euo pipefail

BUCKET="${RUNPOD_BUCKET:-hl1vwr8frk}"
REGION="${RUNPOD_REGION:-us-il-1}"
ENDPOINT="${RUNPOD_ENDPOINT:-https://s3api-${REGION}.runpod.io}"
S3_BASE="s3://${BUCKET}"

# Paths on the network volume (mounted at /workspace in the pod)
IMAGES_PATH="ComfyUI/input"
OUTPUT_PATH="ComfyUI/output"

s3() {
    aws s3 "$@" --region "$REGION" --endpoint-url "$ENDPOINT"
}

cmd_upload() {
    local input_dir="${1:?Usage: ./s3.sh upload <image-dir>}"

    if [ ! -d "$input_dir" ]; then
        echo "Error: $input_dir is not a directory"
        exit 1
    fi

    local count
    count=$(find "$input_dir" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) | wc -l | tr -d ' ')
    echo "Uploading $count images to ${S3_BASE}/${IMAGES_PATH}/"
    echo "  (no GPU pod needed — writing directly to network volume)"
    echo ""

    s3 sync "$input_dir" "${S3_BASE}/${IMAGES_PATH}/" \
        --exclude '*' \
        --include '*.png' --include '*.jpg' --include '*.jpeg' --include '*.webp'

    echo ""
    echo "Done. Start your GPU pod and run:"
    echo "  python3 /workspace/trellis-setup/batch.py /workspace/${IMAGES_PATH}/"
}

cmd_download() {
    local output_dir="${1:-./generated}"
    mkdir -p "$output_dir"

    echo "Downloading .glb files from ${S3_BASE}/${OUTPUT_PATH}/ → $output_dir/"
    echo "  (no GPU pod needed — reading directly from network volume)"
    echo ""

    s3 sync "${S3_BASE}/${OUTPUT_PATH}/" "$output_dir/" \
        --exclude '*' \
        --include '*.glb'

    echo ""
    echo "Downloaded files:"
    ls -lh "$output_dir"/*.glb 2>/dev/null || echo "  (none)"
}

cmd_ls() {
    local path="${1:-}"
    s3 ls "${S3_BASE}/${path}"
}

case "${1:-help}" in
    upload)   shift; cmd_upload "$@" ;;
    download) shift; cmd_download "$@" ;;
    ls)       shift; cmd_ls "$@" ;;
    *)
        echo "Usage: ./s3.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  upload <image-dir>   Upload images to network volume (no GPU needed)"
        echo "  download [out-dir]   Download .glb results (no GPU needed)"
        echo "  ls [path]            List files on the network volume"
        echo ""
        echo "Environment:"
        echo "  RUNPOD_BUCKET=$BUCKET"
        echo "  RUNPOD_REGION=$REGION"
        echo "  RUNPOD_ENDPOINT=$ENDPOINT"
        ;;
esac
