#!/usr/bin/env bash
# post-success-handler.sh - PostToolUse hook handler for Mahoraga
# Logs successful tool uses to help track when failures are resolved

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

# Check if Mahoraga is active
MAHORAGA_DIR="${CWD}/.mahoraga"
[ ! -f "${MAHORAGA_DIR}/state.json" ] && exit 0

ACTIVE=$(cat "${MAHORAGA_DIR}/state.json" | "$JQ_CMD" -r '.active // false' 2>/dev/null)
[ "$ACTIVE" != "true" ] && exit 0

# Log success (this helps the stop handler know failures were resolved)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[$TS] SUCCESS: $TOOL_NAME completed" >> "${MAHORAGA_DIR}/history.log"

exit 0
