#!/usr/bin/env bash
set -euo pipefail

echo "-----------------------------------"
echo " Matrix DB V3 Unified Dispatcher"
echo " Date: $(date)"
echo "-----------------------------------"

TARGET_URL="${TARGET_SCRIPT_URL:-}"
EXECUTION_MODE="${EXECUTION_MODE:-UNKNOWN}"

echo " Detected Execution Mode: $EXECUTION_MODE"
echo " Target Dispatch URL: $TARGET_URL"
echo "-----------------------------------"

if [ -z "$TARGET_URL" ]; then
    echo "WARNING: TARGET_SCRIPT_URL is empty. The workflow did not determine a script to run. Skipping execution."
    exit 0
fi

export GITHUB_ENV
echo "DEBUG: GITHUB_ENV is set to: ${GITHUB_ENV:-unset}"

if [[ "$EXECUTION_MODE" == "LEGACY" ]] || [[ "$TARGET_URL" == *".git"* ]]; then
    echo "Initiating Legacy Mode: Git Repository Architecture"

    TEMP_DIR="fetched_repo"
    rm -rf "$TEMP_DIR"

    echo "Cloning repository: $TARGET_URL"
    git clone --depth 1 "$TARGET_URL" "$TEMP_DIR"

    cd "$TEMP_DIR"
    echo "Entered repository directory: $(pwd)"

    SCRIPT_TO_RUN=""
    if [ -n "$SLOT_NAME" ] && [ -f "${SLOT_NAME}.sh" ]; then
        echo "Found dynamically requested script: ${SLOT_NAME}.sh"
        SCRIPT_TO_RUN="./${SLOT_NAME}.sh"
    else
        for name in "one.sh" "two.sh" "three.sh" "four.sh" "five.sh" "six.sh" "seven.sh" "eight.sh" "nine.sh" "ten.sh" "eleven.sh" "twelve.sh" "thirteen.sh" "fourteen.sh" "fifteen.sh" "sixteen.sh" "seventeen.sh" "eighteen.sh"; do
            if [ -f "$name" ]; then
                echo "Found standard legacy script: $name"
                SCRIPT_TO_RUN="./$name"
                break
            fi
        done
    fi

    if [ -z "$SCRIPT_TO_RUN" ]; then
        echo "Standard script name not found. Searching for any .sh file..."
        FOUND_SH=$(find . -maxdepth 1 -name "*.sh" | head -n 1)
        if [ -n "$FOUND_SH" ]; then
            echo "Fallback: Found script $(basename "$FOUND_SH"). Using it."
            SCRIPT_TO_RUN="$FOUND_SH"
        fi
    fi

    if [ -z "$SCRIPT_TO_RUN" ]; then
        echo "ERROR: No suitable script found in legacy repository."
        ls -R .
        exit 1
    fi

    chmod +x "$SCRIPT_TO_RUN"
    echo "Executing $SCRIPT_TO_RUN (Legacy) inside $(pwd)..."
    "$SCRIPT_TO_RUN"

elif [[ "$EXECUTION_MODE" == "DYNAMIC" ]] || [[ "$TARGET_URL" == *"api/farm/payload"* ]]; then
    echo "Initiating Dynamic Mode: Matrix DB Payload Architecture"

    TEMP_DIR="fetched_payload"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    cd "$TEMP_DIR"
    echo "Entered dynamic build directory: $(pwd)"

    if [ -z "${ORCHESTRATOR_TOKEN:-}" ]; then
        echo "WARNING: ORCHESTRATOR_TOKEN is missing. Payload download will likely fail."
    fi

    echo "Downloading dynamic payload from Matrix DB..."

    MAX_RETRIES=10
    RETRY_DELAY=45
    ATTEMPT=1

    fetch_payload() {
        PAYLOAD=$(curl -s --fail -H "Authorization: Bearer $ORCHESTRATOR_TOKEN" "$TARGET_URL")

        if [ $? -eq 0 ] && [[ "$PAYLOAD" != *"\"error\""* ]]; then
            return 0
        fi

        if [ $ATTEMPT -ge $MAX_RETRIES ]; then
            echo "ERROR: Failed to fetch payload from Matrix DB after $MAX_RETRIES attempts!"
            echo "$PAYLOAD" | jq -r '.error' || echo "$PAYLOAD"
            exit 1
        fi

        echo "WARNING: Matrix DB server busy or returned an error. Retrying in $RETRY_DELAY seconds (Attempt $ATTEMPT of $MAX_RETRIES)..."
        sleep $RETRY_DELAY
        ATTEMPT=$((ATTEMPT + 1))

        fetch_payload
    }

    fetch_payload

    echo "Extracting dynamic payload files..."
    echo "$PAYLOAD" | jq -r '."Dockerfile"' > Dockerfile
    echo "$PAYLOAD" | jq -r '."config.json"' > config.json
    echo "$PAYLOAD" | jq -r '."accounts.json"' > accounts.json

    SCRIPT_NAME=$(echo "$PAYLOAD" | jq -r 'keys[] | select(test("\\.sh$"))')

    if [ -z "$SCRIPT_NAME" ]; then
        echo "ERROR: No .sh script found in Matrix DB payload!"
        exit 1
    fi

    echo "$PAYLOAD" | jq -r '."'"$SCRIPT_NAME"'"' > "$SCRIPT_NAME"
    chmod +x "$SCRIPT_NAME"

    echo "Executing $SCRIPT_NAME (Dynamic) inside $(pwd)..."
    ./"$SCRIPT_NAME"

else
    echo "ERROR: Could not determine Execution Mode or Target URL format."
    echo "TARGET_URL: $TARGET_URL"
    echo "EXECUTION_MODE: $EXECUTION_MODE"
    exit 1
fi

if [ -f "${GITHUB_ENV:-}" ]; then
    echo "DEBUG: Execution finished. Outer wrapper completed securely."
fi
