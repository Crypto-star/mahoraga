#!/usr/bin/env bash
# post-tool-handler.sh - PostToolUseFailure hook handler for Mahoraga
# Logs failures to immunity database, spins wheel, and provides guidance

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/lib/immunity.sh"
source "${SCRIPT_DIR}/lib/wheel.sh"

# Find jq (required)
if ! command -v jq &>/dev/null; then
    for p in /usr/bin/jq /usr/local/bin/jq /snap/bin/jq; do
        [ -x "$p" ] && alias jq="$p" && break
    done
fi

# Read stdin
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Parse fields
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$CWD" ] && CWD="."

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
ERROR_MSG=$(echo "$INPUT" | jq -r '.error // ""' 2>/dev/null)
IS_INTERRUPT=$(echo "$INPUT" | jq -r '.is_interrupt // false' 2>/dev/null)

# Skip user interrupts
[ "$IS_INTERRUPT" = "true" ] && exit 0

# Check if Mahoraga is active
MAHORAGA_DIR="${CWD}/.mahoraga"
[ ! -d "$MAHORAGA_DIR" ] && exit 0
[ ! -f "${MAHORAGA_DIR}/state.json" ] && exit 0

# Initialize state management
init_state "$MAHORAGA_DIR"
init_logger "$MAHORAGA_DIR"

# Check if session is active
if [ "$(is_mahoraga_active)" != "true" ]; then
    exit 0
fi

# Extract command using library function
CMD=$(extract_command_from_tool "$TOOL_NAME" "$TOOL_INPUT" 100)
[ -z "$CMD" ] && CMD="unknown"

# Categorize error using library function
ERROR_TYPE=$(categorize_error "$ERROR_MSG")

# Log the failure
log_failure "$TOOL_NAME" "$ERROR_MSG"

# Add to immunity database (unless in no-immunity mode)
if [ "$(is_immunity_disabled)" != "true" ]; then
    PATTERN_ID=$(immunity_add "$TOOL_NAME" "$CMD" "$ERROR_TYPE" "$ERROR_MSG")
fi

# Spin the wheel (increment rotation, track adaptation)
NEW_ROTATION=$(spin_wheel "failure: $TOOL_NAME - $ERROR_TYPE")

# Check if guidance should be shown
if [ "$(should_show_guidance "$NEW_ROTATION")" = "true" ]; then
    GUIDANCE=$(generate_guidance_message "$NEW_ROTATION")

    # Output guidance to be shown to the user
    if [ -n "$GUIDANCE" ]; then
        echo "$GUIDANCE"
    fi
fi

# Check if max rotations reached
MAX_ROT=$(get_max_rotations)
if [ "$NEW_ROTATION" -ge "$MAX_ROT" ]; then
    log_error "Maximum rotations ($MAX_ROT) reached"
    deactivate_mahoraga

    cat << EOF

---

## 🛞 Mahoraga: Maximum Rotations Reached

After $MAX_ROT adaptation attempts, this task requires human guidance.

**Review the session:**
- Check \`.mahoraga/history.log\` for attempt history
- Check \`.mahoraga/immunity.json\` for blocked patterns
- Consider adjusting the task requirements

**Options:**
1. Reset immunity: \`rm .mahoraga/immunity.json\`
2. Increase max rotations: \`/mahoraga "task" --max-rotations 15\`
3. Observe mode: \`/mahoraga "task" --no-immunity\`

---

EOF
fi

exit 0
