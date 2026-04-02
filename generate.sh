#!/usr/bin/env bash
#
# Generate a .glb from an image via RunPod serverless TRELLIS.2 endpoint.
#
# Usage:
#   ./generate.sh image.png                    # outputs image.glb
#   ./generate.sh image.png output.glb         # custom output name
#   ./generate.sh ./images/                    # batch: all images in dir
#
# Environment:
#   RUNPOD_API_KEY   - your RunPod API key (required)
#   RUNPOD_ENDPOINT  - endpoint URL (default: https://api.runpod.ai/v2/76ml8szhlkd1ee)
#   TEXTURE_SIZE     - texture resolution (default: 1024)
#   MESH_SIMPLIFY    - simplification ratio (default: 0.95)
#
set -euo pipefail

ENDPOINT="${RUNPOD_ENDPOINT:-https://api.runpod.ai/v2/76ml8szhlkd1ee}"
API_KEY="${RUNPOD_API_KEY:?Set RUNPOD_API_KEY to your RunPod API key}"
TEXTURE_SIZE="${TEXTURE_SIZE:-1024}"
MESH_SIMPLIFY="${MESH_SIMPLIFY:-0.95}"
POLL_INTERVAL=5

generate_one() {
    local input_file="$1"
    local output_file="${2:-$(basename "${input_file%.*}").glb}"
    local fname
    fname=$(basename "$input_file")

    echo "[$fname] Encoding..."
    local tmpjson
    tmpjson=$(mktemp /tmp/trellis-XXXXXX.json)
    trap "rm -f $tmpjson" RETURN

    python3 -c "
import base64, json
with open('$input_file', 'rb') as f:
    b64 = base64.b64encode(f.read()).decode()
payload = {
    'input': {
        'image': b64,
        'texture_size': $TEXTURE_SIZE,
        'mesh_simplify': $MESH_SIMPLIFY
    }
}
with open('$tmpjson', 'w') as f:
    json.dump(payload, f)
"

    echo "[$fname] Submitting to TRELLIS.2..."
    local response
    response=$(curl -sS "$ENDPOINT/run" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d @"$tmpjson")
    rm -f "$tmpjson"

    local job_id
    job_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

    if [ -z "$job_id" ]; then
        echo "[$fname] ERROR: Failed to submit job"
        echo "  Response: $response"
        return 1
    fi

    echo "[$fname] Job: $job_id — polling..."

    # Poll for completion
    while true; do
        local status_response
        status_response=$(curl -sS "$ENDPOINT/status/$job_id" \
            -H "Authorization: Bearer $API_KEY")

        local status
        status=$(echo "$status_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)

        case "$status" in
            COMPLETED)
                echo "[$fname] Extracting .glb..."
                echo "$status_response" | python3 -c "
import sys, json, base64
data = json.load(sys.stdin)
output = data.get('output', {})
# Try common output field names
glb_b64 = output.get('glb') or output.get('model') or output.get('mesh') or output.get('result', '')
if isinstance(glb_b64, str) and len(glb_b64) > 100:
    with open('$output_file', 'wb') as f:
        f.write(base64.b64decode(glb_b64))
    print(f'  Saved: $output_file')
elif isinstance(output, dict):
    # Maybe it's a URL
    url = output.get('glb_url') or output.get('model_url') or output.get('url', '')
    if url:
        print(f'  Download URL: {url}')
    else:
        print(f'  Unknown output format. Keys: {list(output.keys())}')
        # Dump for debugging
        with open('${output_file}.json', 'w') as f:
            json.dump(data, f, indent=2)
        print(f'  Full response saved to ${output_file}.json')
else:
    print(f'  Unexpected output type: {type(output)}')
    with open('${output_file}.json', 'w') as f:
        json.dump(data, f, indent=2)
    print(f'  Full response saved to ${output_file}.json')
"
                return 0
                ;;
            FAILED)
                echo "[$fname] FAILED"
                echo "$status_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Error: {d.get(\"error\", \"unknown\")}')" 2>/dev/null
                return 1
                ;;
            IN_QUEUE|IN_PROGRESS)
                printf "."
                sleep "$POLL_INTERVAL"
                ;;
            *)
                echo "[$fname] Unknown status: $status"
                sleep "$POLL_INTERVAL"
                ;;
        esac
    done
}

# Main
input="$1"

if [ -d "$input" ]; then
    # Batch mode
    echo "Batch processing directory: $input"
    echo ""
    count=0
    for img in "$input"/*.png "$input"/*.jpg "$input"/*.jpeg "$input"/*.webp; do
        [ -f "$img" ] || continue
        count=$((count + 1))
        output="./generated/$(basename "${img%.*}").glb"
        mkdir -p ./generated
        generate_one "$img" "$output"
        echo ""
    done
    echo "Done: $count files processed"
else
    # Single file
    generate_one "$input" "${2:-$(basename "${input%.*}").glb}"
fi
