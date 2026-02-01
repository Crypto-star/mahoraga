#!/usr/bin/env bash
# init-handler.sh - UserPromptSubmit hook handler for Mahoraga

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

PROMPT=$(echo "$INPUT" | "$JQ_CMD" -r '.prompt // ""' 2>/dev/null)
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

# Sanitize task - remove newlines and control characters, escape for JSON
TASK=$(echo "$TASK" | tr '\n\r' '  ' | tr -d '\000-\037')

# Setup directory
MAHORAGA_DIR="${CWD}/.mahoraga"
mkdir -p "$MAHORAGA_DIR" 2>/dev/null || exit 0

# Timestamp and session ID
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
SID=$(date +%s 2>/dev/null || echo "0")

# Parse options from prompt
MAX_ROT=10
NO_IMM=false

case "$PROMPT" in
    *"--max-rotations"*)
        MAX_ROT=$(echo "$PROMPT" | grep -oE '\-\-max-rotations\s+[0-9]+' | grep -oE '[0-9]+' | head -1)
        [ -z "$MAX_ROT" ] && MAX_ROT=10
        ;;
esac

case "$PROMPT" in
    *"--no-immunity"*) NO_IMM=true ;;
esac

# Create state.json using jq for proper escaping
echo "{}" | "$JQ_CMD" \
    --arg task "$TASK" \
    --arg ts "$TS" \
    --arg sid "$SID" \
    --argjson max_rot "$MAX_ROT" \
    --argjson no_imm "$NO_IMM" \
    '{
        active: true,
        task: $task,
        iteration: 0,
        rotation_count: 0,
        max_rotations: $max_rot,
        no_immunity: $no_imm,
        session_only: false,
        started_at: $ts,
        session_id: $sid
    }' > "${MAHORAGA_DIR}/state.json"

# Create immunity.json
echo '{"forbidden_patterns":[],"pattern_categories":{}}' > "${MAHORAGA_DIR}/immunity.json"

# Create wheel.json
echo '{"rotation_count":0,"current_strategy":"initial","adaptations":[]}' > "${MAHORAGA_DIR}/wheel.json"

# Create history.log - also sanitize task for logging
TASK_LOG=$(echo "$TASK" | head -c 100)
echo "[$TS] Session started: $TASK_LOG" > "${MAHORAGA_DIR}/history.log"

exit 0
