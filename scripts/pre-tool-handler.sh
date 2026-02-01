#!/usr/bin/env bash
# pre-tool-handler.sh - PreToolUse hook handler for Mahoraga
# Checks immunity database and blocks forbidden patterns with time-decay and context awareness

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/lib/immunity.sh"

# Find jq binary
JQ_BIN=""
if command -v jq &>/dev/null; then
    JQ_BIN="jq"
else
    for p in /usr/bin/jq /usr/local/bin/jq /snap/bin/jq; do
        [ -x "$p" ] && JQ_BIN="$p" && break
    done
fi
[ -z "$JQ_BIN" ] && exit 0

# Read stdin
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Parse fields
CWD=$(echo "$INPUT" | "$JQ_BIN" -r '.cwd // "."' 2>/dev/null)
[ -z "$CWD" ] && CWD="."

TOOL_NAME=$(echo "$INPUT" | "$JQ_BIN" -r '.tool_name // ""' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | "$JQ_BIN" -c '.tool_input // {}' 2>/dev/null)

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
CMD=$(extract_command_from_tool "$TOOL_NAME" "$TOOL_INPUT" 200)

# Skip if no command extracted
[ -z "$CMD" ] && exit 0

# Check if immunity is disabled (--no-immunity mode)
if [ "$(is_immunity_disabled)" = "true" ]; then
    # Observe mode - log but don't block
    BLOCK_REASON=$(immunity_check "$TOOL_NAME" "$CMD")
    if [ $? -eq 1 ]; then
        log_observe "$TOOL_NAME" "$BLOCK_REASON"
    fi
    exit 0
fi

# Check immunity database with time-decay and context awareness
BLOCK_REASON=$(immunity_check "$TOOL_NAME" "$CMD")
if [ $? -eq 1 ]; then
    # Immunity triggered - block the action
    log_block "$TOOL_NAME" "$BLOCK_REASON"

    # Get current rotation for context
    ROTATION=$(get_rotation_count)
    MAX_ROT=$(get_max_rotations)

    cat << EOF
{
  "decision": "block",
  "reason": "🛞 Mahoraga Immunity: $BLOCK_REASON\n\nRotation: $ROTATION/$MAX_ROT\nTry a different approach - this exact pattern has failed before."
}
EOF
    exit 0
fi

# Allow the action
exit 0
