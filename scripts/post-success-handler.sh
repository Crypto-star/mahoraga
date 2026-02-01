#!/usr/bin/env bash
# post-success-handler.sh - PostToolUse hook handler for Mahoraga
# Logs successful tool uses to track resolution of failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/state.sh"

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

# Extract command for logging context
CMD=$(extract_command_from_tool "$TOOL_NAME" "$TOOL_INPUT" 50)
[ -z "$CMD" ] && CMD="(no details)"

# Log success
log_info "SUCCESS: $TOOL_NAME completed - $CMD"

# Increment iteration counter
increment_iteration

exit 0
