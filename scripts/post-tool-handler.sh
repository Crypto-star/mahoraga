#!/usr/bin/env bash
# post-tool-handler.sh - PostToolUseFailure hook handler for Mahoraga

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find jq
JQ_CMD=""
for p in /usr/bin/jq /usr/local/bin/jq; do
    [ -x "$p" ] && JQ_CMD="$p" && break
done
[ -z "$JQ_CMD" ] && exit 0

# Read stdin
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Parse fields
CWD=$(echo "$INPUT" | "$JQ_CMD" -r '.cwd // "."' 2>/dev/null)
[ -z "$CWD" ] && CWD="."

TOOL_NAME=$(echo "$INPUT" | "$JQ_CMD" -r '.tool_name // ""' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | "$JQ_CMD" -r '.tool_input // "{}"' 2>/dev/null)
ERROR_MSG=$(echo "$INPUT" | "$JQ_CMD" -r '.error // ""' 2>/dev/null)
IS_INTERRUPT=$(echo "$INPUT" | "$JQ_CMD" -r '.is_interrupt // false' 2>/dev/null)

# Skip user interrupts
[ "$IS_INTERRUPT" = "true" ] && exit 0

# Check if Mahoraga is active
MAHORAGA_DIR="${CWD}/.mahoraga"
[ ! -f "${MAHORAGA_DIR}/state.json" ] && exit 0

ACTIVE=$(cat "${MAHORAGA_DIR}/state.json" | "$JQ_CMD" -r '.active // false' 2>/dev/null)
[ "$ACTIVE" != "true" ] && exit 0

# Extract command - sanitize for JSON
case "$TOOL_NAME" in
    Bash)
        CMD=$(echo "$TOOL_INPUT" | "$JQ_CMD" -r '.command // ""' 2>/dev/null | head -c 100)
        ;;
    Write|Edit)
        CMD=$(echo "$TOOL_INPUT" | "$JQ_CMD" -r '.file_path // ""' 2>/dev/null)
        ;;
    *)
        CMD="other"
        ;;
esac

# Sanitize CMD for JSON (remove quotes and special chars)
CMD=$(echo "$CMD" | tr -d '"\\' | tr "'" " " | head -c 80)

# Categorize error
ERROR_LC=$(echo "$ERROR_MSG" | tr '[:upper:]' '[:lower:]')
case "$ERROR_LC" in
    *"permission denied"*|*"access denied"*) ERROR_TYPE="permission" ;;
    *"not found"*|*"no such file"*) ERROR_TYPE="file_not_found" ;;
    *"module"*|*"import"*|*"package"*) ERROR_TYPE="dependency" ;;
    *"timeout"*|*"connection"*) ERROR_TYPE="network" ;;
    *"syntax"*|*"parse"*) ERROR_TYPE="syntax" ;;
    *) ERROR_TYPE="unknown" ;;
esac

# Create signature (simplified)
SIG="${TOOL_NAME}:${CMD}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Log to history (mark as UNRESOLVED)
echo "[$TS] FAILURE [UNRESOLVED]: $TOOL_NAME - $ERROR_TYPE - $CMD" >> "${MAHORAGA_DIR}/history.log"

# Add to immunity database safely
if [ -f "${MAHORAGA_DIR}/immunity.json" ]; then
    # Read current immunity
    CURRENT=$(cat "${MAHORAGA_DIR}/immunity.json" 2>/dev/null)

    # Validate it's proper JSON
    if echo "$CURRENT" | "$JQ_CMD" '.' >/dev/null 2>&1; then
        # Build new pattern as proper JSON
        NEW_IMMUNITY=$(echo "$CURRENT" | "$JQ_CMD" \
            --arg sig "$SIG" \
            --arg tool "$TOOL_NAME" \
            --arg err "$ERROR_TYPE" \
            --arg ts "$TS" \
            '.forbidden_patterns += [{"signature": $sig, "tool": $tool, "error_type": $err, "timestamp": $ts}]' 2>/dev/null)

        # Only write if jq succeeded
        if [ -n "$NEW_IMMUNITY" ]; then
            echo "$NEW_IMMUNITY" > "${MAHORAGA_DIR}/immunity.json"
        fi
    fi
fi

# Increment rotation count
STATE=$(cat "${MAHORAGA_DIR}/state.json" 2>/dev/null)
if echo "$STATE" | "$JQ_CMD" '.' >/dev/null 2>&1; then
    ROT=$(echo "$STATE" | "$JQ_CMD" -r '.rotation_count // 0' 2>/dev/null)
    NEW_ROT=$((ROT + 1))
    NEW_STATE=$(echo "$STATE" | "$JQ_CMD" ".rotation_count = $NEW_ROT | .last_rotation_at = \"$TS\"" 2>/dev/null)
    if [ -n "$NEW_STATE" ]; then
        echo "$NEW_STATE" > "${MAHORAGA_DIR}/state.json"
    fi
fi

exit 0
