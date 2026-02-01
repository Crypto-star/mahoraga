#!/usr/bin/env bash
# stop-handler.sh - Stop hook handler for Mahoraga

# Find jq
JQ_CMD=""
for p in /usr/bin/jq /usr/local/bin/jq; do
    [ -x "$p" ] && JQ_CMD="$p" && break
done
[ -z "$JQ_CMD" ] && exit 0

# Read stdin
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Parse cwd
CWD=$(echo "$INPUT" | "$JQ_CMD" -r '.cwd // "."' 2>/dev/null)
[ -z "$CWD" ] && CWD="."

# Check if Mahoraga is active
MAHORAGA_DIR="${CWD}/.mahoraga"
[ ! -f "${MAHORAGA_DIR}/state.json" ] && exit 0

STATE=$(cat "${MAHORAGA_DIR}/state.json" 2>/dev/null)
ACTIVE=$(echo "$STATE" | "$JQ_CMD" -r '.active // false' 2>/dev/null)

# If already inactive or completed, allow exit
[ "$ACTIVE" != "true" ] && exit 0

# Check for completion markers
COMPLETED=$(echo "$STATE" | "$JQ_CMD" -r '.completed // false' 2>/dev/null)
[ "$COMPLETED" = "true" ] && exit 0

STATUS=$(echo "$STATE" | "$JQ_CMD" -r '.status // ""' 2>/dev/null)
[ "$STATUS" = "completed" ] && exit 0

# Get state values
TASK=$(echo "$STATE" | "$JQ_CMD" -r '.task // ""' 2>/dev/null)
ROT=$(echo "$STATE" | "$JQ_CMD" -r '.rotation_count // 0' 2>/dev/null)
MAX_ROT=$(echo "$STATE" | "$JQ_CMD" -r '.max_rotations // 10' 2>/dev/null)

# Check if max rotations reached
if [ "$ROT" -ge "$MAX_ROT" ]; then
    echo "$STATE" | "$JQ_CMD" '.active = false' > "${MAHORAGA_DIR}/state.json.tmp" 2>/dev/null
    mv "${MAHORAGA_DIR}/state.json.tmp" "${MAHORAGA_DIR}/state.json" 2>/dev/null
    exit 0
fi

# Check recent history - look at last 5 entries
# Allow completion if: last entry is SUCCESS, or more successes than failures
SHOULD_BLOCK=false

if [ -f "${MAHORAGA_DIR}/history.log" ]; then
    RECENT=$(tail -5 "${MAHORAGA_DIR}/history.log")
    LAST_ENTRY=$(echo "$RECENT" | tail -1)

    # If last entry is a failure, block
    if echo "$LAST_ENTRY" | grep -q "FAILURE"; then
        SHOULD_BLOCK=true
    else
        # Count successes vs failures in recent entries
        SUCCESS_COUNT=$(echo "$RECENT" | grep -c "SUCCESS" || true)
        FAILURE_COUNT=$(echo "$RECENT" | grep -c "FAILURE" || true)

        # Ensure they're numbers
        case "$SUCCESS_COUNT" in ''|*[!0-9]*) SUCCESS_COUNT=0 ;; esac
        case "$FAILURE_COUNT" in ''|*[!0-9]*) FAILURE_COUNT=0 ;; esac

        # Block only if more failures than successes AND no success after failure
        if [ "$FAILURE_COUNT" -gt "$SUCCESS_COUNT" ]; then
            # Check if there's any success after the last failure
            LAST_FAILURE_LINE=$(echo "$RECENT" | grep -n "FAILURE" | tail -1 | cut -d: -f1)
            LAST_SUCCESS_LINE=$(echo "$RECENT" | grep -n "SUCCESS" | tail -1 | cut -d: -f1)

            case "$LAST_FAILURE_LINE" in ''|*[!0-9]*) LAST_FAILURE_LINE=0 ;; esac
            case "$LAST_SUCCESS_LINE" in ''|*[!0-9]*) LAST_SUCCESS_LINE=0 ;; esac

            if [ "$LAST_SUCCESS_LINE" -lt "$LAST_FAILURE_LINE" ]; then
                SHOULD_BLOCK=true
            fi
        fi
    fi
fi

# If should not block, mark as completed and allow exit
if [ "$SHOULD_BLOCK" = "false" ]; then
    echo "$STATE" | "$JQ_CMD" '.active = false | .completed = true' > "${MAHORAGA_DIR}/state.json.tmp" 2>/dev/null
    mv "${MAHORAGA_DIR}/state.json.tmp" "${MAHORAGA_DIR}/state.json" 2>/dev/null
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$TS] Task completed successfully." >> "${MAHORAGA_DIR}/history.log"
    exit 0
fi

# Block and continue
ITER=$(echo "$STATE" | "$JQ_CMD" -r '.iteration // 0' 2>/dev/null)
NEW_ITER=$((ITER + 1))
echo "$STATE" | "$JQ_CMD" ".iteration = $NEW_ITER" > "${MAHORAGA_DIR}/state.json.tmp" 2>/dev/null
mv "${MAHORAGA_DIR}/state.json.tmp" "${MAHORAGA_DIR}/state.json" 2>/dev/null

IMM_COUNT=0
if [ -f "${MAHORAGA_DIR}/immunity.json" ]; then
    IMM_COUNT=$(cat "${MAHORAGA_DIR}/immunity.json" | "$JQ_CMD" '.forbidden_patterns | length' 2>/dev/null || echo "0")
    case "$IMM_COUNT" in ''|*[!0-9]*) IMM_COUNT=0 ;; esac
fi

cat << EOF
{
  "decision": "block",
  "reason": "Mahoraga: Recent failure needs resolution. Rotation $ROT/$MAX_ROT. Blocked patterns: $IMM_COUNT. Fix the issue before completing."
}
EOF

exit 0
