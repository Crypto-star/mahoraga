#!/usr/bin/env bash
# stop-handler.sh - Stop hook handler for Mahoraga
# Uses multi-factor validation to determine if task is truly complete

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/lib/immunity.sh"
source "${SCRIPT_DIR}/lib/validator.sh"

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

TRANSCRIPT_PATH=$(echo "$INPUT" | "$JQ_BIN" -r '.transcript_path // ""' 2>/dev/null)

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

# Check if already marked complete
STATE=$(cat "${MAHORAGA_DIR}/state.json" 2>/dev/null)
COMPLETED=$(echo "$STATE" | "$JQ_BIN" -r '.completed // false' 2>/dev/null)
[ "$COMPLETED" = "true" ] && exit 0

STATUS=$(echo "$STATE" | "$JQ_BIN" -r '.status // ""' 2>/dev/null)
[ "$STATUS" = "completed" ] && exit 0

# Get state values
TASK=$(get_current_task)
ROTATION=$(get_rotation_count)
MAX_ROT=$(get_max_rotations)

# Check if max rotations reached - allow exit
if [ "$ROTATION" -ge "$MAX_ROT" ]; then
    deactivate_mahoraga
    log_complete "Session ended (max rotations reached: $ROTATION)"
    exit 0
fi

# Run multi-factor validation
VALIDATION_RESULT=$(validate_completion "$TRANSCRIPT_PATH" "$MAHORAGA_DIR")
VALIDATION_STATUS=$?

if [ "$VALIDATION_STATUS" -eq 0 ]; then
    # Validation passed - allow completion
    deactivate_mahoraga
    log_complete "Task validated and completed"

    # Parse and display validation summary
    MANDATORY_PASSED=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.mandatory.passed // 0' 2>/dev/null)
    MANDATORY_REQUIRED=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.mandatory.required // 1' 2>/dev/null)
    BONUS_SCORE=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.bonus.score // 0' 2>/dev/null)
    BONUS_AVAILABLE=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.bonus.available // 4' 2>/dev/null)

    cat << EOF

---

## 🛞 Mahoraga: Task Complete

**Validation Summary:**
- Mandatory checks: $MANDATORY_PASSED/$MANDATORY_REQUIRED ✓
- Bonus checks: $BONUS_SCORE/$BONUS_AVAILABLE

**Session Statistics:**
- Rotations: $ROTATION
- Immunity patterns: $(immunity_count)
- Task: $TASK

---

EOF
    exit 0
fi

# Validation failed - block completion
log_validation "fail" "Blocking completion - validation failed"

# Parse validation details for better error message
MANDATORY_PASSED=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.mandatory.passed // 0' 2>/dev/null)
MANDATORY_REQUIRED=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.mandatory.required // 1' 2>/dev/null)
BONUS_SCORE=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.bonus.score // 0' 2>/dev/null)
BONUS_REQUIRED=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.bonus.required // 1' 2>/dev/null)
DETAILS=$(echo "$VALIDATION_RESULT" | "$JQ_BIN" -r '.details // ""' 2>/dev/null)

# Determine actual failure reason
if [ "$MANDATORY_PASSED" -lt "$MANDATORY_REQUIRED" ]; then
    FAILURE_REASON="Recent errors detected in output"
elif [ "$BONUS_SCORE" -lt "$BONUS_REQUIRED" ]; then
    FAILURE_REASON="Bonus validation score too low ($BONUS_SCORE/$BONUS_REQUIRED required)"
else
    FAILURE_REASON="Validation checks incomplete"
fi

cat << EOF
{
  "decision": "block",
  "reason": "🛞 Mahoraga: Validation incomplete\n\nRotation: $ROTATION/$MAX_ROT\nMandatory: $MANDATORY_PASSED/$MANDATORY_REQUIRED\nBonus: $BONUS_SCORE (need $BONUS_REQUIRED)\n\nReason: $FAILURE_REASON\nDetails: $DETAILS"
}
EOF

exit 0
