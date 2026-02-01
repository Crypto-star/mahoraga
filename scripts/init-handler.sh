#!/usr/bin/env bash
# init-handler.sh - UserPromptSubmit hook handler for Mahoraga
# Initializes session state when /mahoraga command is detected

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logger.sh"

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

PROMPT=$(echo "$INPUT" | "$JQ_BIN" -r '.prompt // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Check if mahoraga command (but not status command)
case "$PROMPT" in
    *mahoraga:mahoraga-status*|*mahoraga-status*) exit 0 ;;
    *mahoraga*) ;;
    *) exit 0 ;;
esac

# Extract quoted task using bash regex
TASK=""
if [[ "$PROMPT" =~ \"([^\"]+)\" ]]; then
    TASK="${BASH_REMATCH[1]}"
elif [[ "$PROMPT" =~ \'([^\']+)\' ]]; then
    TASK="${BASH_REMATCH[1]}"
fi

# No task = skip initialization
[ -z "$TASK" ] && exit 0

# Sanitize task - remove newlines and control characters
TASK=$(echo "$TASK" | tr '\n\r' '  ' | tr -d '\000-\037')

# Setup directory
MAHORAGA_DIR=$(get_mahoraga_dir "$CWD" "false")
ensure_dir "$MAHORAGA_DIR"

# Initialize logger
init_logger "$MAHORAGA_DIR"

# Parse options from prompt
MAX_ROT=10
NO_IMM=false
SESSION_ONLY=false

case "$PROMPT" in
    *"--max-rotations"*)
        MAX_ROT=$(echo "$PROMPT" | grep -oE '\-\-max-rotations\s+[0-9]+' | grep -oE '[0-9]+' | head -1)
        [ -z "$MAX_ROT" ] && MAX_ROT=10
        ;;
esac

case "$PROMPT" in
    *"--no-immunity"*) NO_IMM=true ;;
esac

case "$PROMPT" in
    *"--session-only"*) SESSION_ONLY=true ;;
esac

# Timestamp and session ID
TS=$(get_timestamp)
SID=$(get_unix_timestamp)

# Create state.json
echo "{}" | "$JQ_BIN" \
    --arg task "$TASK" \
    --arg ts "$TS" \
    --arg sid "$SID" \
    --argjson max_rot "$MAX_ROT" \
    --argjson no_imm "$NO_IMM" \
    --argjson session_only "$SESSION_ONLY" \
    '{
        active: true,
        task: $task,
        iteration: 0,
        rotation_count: 0,
        max_rotations: $max_rot,
        no_immunity: $no_imm,
        session_only: $session_only,
        started_at: $ts,
        last_rotation_at: $ts,
        session_id: $sid
    }' > "${MAHORAGA_DIR}/state.json"

# Create immunity.json
echo '{"forbidden_patterns":[],"pattern_categories":{}}' > "${MAHORAGA_DIR}/immunity.json"

# Create wheel.json
echo '{"rotation_count":0,"current_strategy":"initial","last_strategy":null,"refactoring_triggered":false,"adaptations":[]}' > "${MAHORAGA_DIR}/wheel.json"

# Create empty recent_output.log for validator
: > "${MAHORAGA_DIR}/recent_output.log"

# Log session start
log_init "$TASK" "$MAX_ROT"

exit 0
