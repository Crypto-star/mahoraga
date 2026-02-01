#!/usr/bin/env bash
# pre-tool-handler.sh - PreToolUse hook handler for Mahoraga
# Checks immunity database and blocks forbidden patterns

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find jq
JQ_CMD=""
for p in /usr/bin/jq /snap/jq/6/usr/bin/jq /usr/local/bin/jq; do
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

# Check if Mahoraga is active
MAHORAGA_DIR="${CWD}/.mahoraga"
[ ! -f "${MAHORAGA_DIR}/state.json" ] && exit 0

# Check if session is active
ACTIVE=$(echo "$MAHORAGA_DIR/state.json" | xargs cat 2>/dev/null | "$JQ_CMD" -r '.active // false' 2>/dev/null)
[ "$ACTIVE" != "true" ] && exit 0

# Extract command for immunity check
case "$TOOL_NAME" in
    Bash)
        CMD=$(echo "$TOOL_INPUT" | "$JQ_CMD" -r '.command // ""' 2>/dev/null)
        ;;
    Write|Edit)
        CMD=$(echo "$TOOL_INPUT" | "$JQ_CMD" -r '.file_path // ""' 2>/dev/null)
        ;;
    *)
        CMD=$(echo "$TOOL_INPUT" | head -c 100)
        ;;
esac

# Check immunity database
if [ -f "${MAHORAGA_DIR}/immunity.json" ]; then
    # Create signature
    SIG="${TOOL_NAME}:${CMD}"

    # Check if this pattern is forbidden
    FORBIDDEN=$(cat "${MAHORAGA_DIR}/immunity.json" | "$JQ_CMD" -r '.forbidden_patterns[]?.signature // empty' 2>/dev/null | grep -F "$SIG" | head -1)

    if [ -n "$FORBIDDEN" ]; then
        # Check if no_immunity mode
        NO_IMM=$(cat "${MAHORAGA_DIR}/state.json" | "$JQ_CMD" -r '.no_immunity // false' 2>/dev/null)

        if [ "$NO_IMM" != "true" ]; then
            # Block the action
            cat << EOF
{
  "decision": "block",
  "reason": "Mahoraga: This approach was tried before and failed. Try a different method."
}
EOF
            exit 0
        fi
    fi
fi

# Allow the action
exit 0
