#!/usr/bin/env bash
# state.sh - State management for Mahoraga
# Usage: source state.sh

# =============================================================================
# State File Paths
# =============================================================================

STATE_FILE=""
IMMUNITY_FILE=""
WHEEL_FILE=""

# =============================================================================
# Initialization
# =============================================================================

# Initialize state management with directory
init_state() {
    local mahoraga_dir="$1"

    ensure_dir "$mahoraga_dir"

    STATE_FILE="${mahoraga_dir}/state.json"
    IMMUNITY_FILE="${mahoraga_dir}/immunity.json"
    WHEEL_FILE="${mahoraga_dir}/wheel.json"

    # Initialize state file if not exists
    if [ ! -f "$STATE_FILE" ]; then
        local plugin_root
        plugin_root=$(get_plugin_root)
        cp "${plugin_root}/templates/state.template.json" "$STATE_FILE"
    fi

    # Initialize immunity file if not exists
    if [ ! -f "$IMMUNITY_FILE" ]; then
        local plugin_root
        plugin_root=$(get_plugin_root)
        cp "${plugin_root}/templates/immunity.template.json" "$IMMUNITY_FILE"
    fi

    # Initialize wheel file if not exists
    if [ ! -f "$WHEEL_FILE" ]; then
        local plugin_root
        plugin_root=$(get_plugin_root)
        cp "${plugin_root}/templates/wheel.template.json" "$WHEEL_FILE"
    fi

    export STATE_FILE IMMUNITY_FILE WHEEL_FILE
}

# =============================================================================
# State Operations
# =============================================================================

# Check if Mahoraga is active
is_mahoraga_active() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    json_get "$STATE_FILE" ".active" "false"
}

# Activate Mahoraga with task
activate_mahoraga() {
    local task="$1"
    local max_rotations="${2:-10}"
    local no_immunity="${3:-false}"
    local session_only="${4:-false}"
    local session_id="${5:-$(get_unix_timestamp)}"

    local timestamp
    timestamp=$(get_timestamp)

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg task "$task" \
       --arg max "$max_rotations" \
       --arg ts "$timestamp" \
       --arg sid "$session_id" \
       --argjson ni "$no_immunity" \
       --argjson so "$session_only" \
       '.active = true |
        .task = $task |
        .iteration = 0 |
        .rotation_count = 0 |
        .max_rotations = ($max | tonumber) |
        .no_immunity = $ni |
        .session_only = $so |
        .started_at = $ts |
        .last_rotation_at = $ts |
        .session_id = $sid' \
       "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"

    log_init "$task" "$max_rotations"
}

# Deactivate Mahoraga
deactivate_mahoraga() {
    json_set "$STATE_FILE" ".active" "false"
    log_complete "Mahoraga session ended"
}

# Get current task
get_current_task() {
    json_get "$STATE_FILE" ".task" ""
}

# Get current rotation count
get_rotation_count() {
    json_get "$STATE_FILE" ".rotation_count" "0"
}

# Get max rotations
get_max_rotations() {
    json_get "$STATE_FILE" ".max_rotations" "10"
}

# Check if immunity is disabled (--no-immunity)
is_immunity_disabled() {
    json_get "$STATE_FILE" ".no_immunity" "false"
}

# Increment iteration
increment_iteration() {
    local current
    current=$(json_get "$STATE_FILE" ".iteration" "0")
    json_set "$STATE_FILE" ".iteration" "$((current + 1))" "false"
}

# Increment rotation count
increment_rotation() {
    local current
    current=$(get_rotation_count)
    local new_count=$((current + 1))

    local timestamp
    timestamp=$(get_timestamp)

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg ts "$timestamp" \
       ".rotation_count = $new_count | .last_rotation_at = \$ts" \
       "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"

    echo "$new_count"
}

# =============================================================================
# State Summary
# =============================================================================

# Get full state summary for status command
get_state_summary() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "{}"
        return
    fi
    cat "$STATE_FILE"
}

# Get immunity summary
get_immunity_summary() {
    if [ ! -f "$IMMUNITY_FILE" ]; then
        echo "{\"count\": 0, \"categories\": {}}"
        return
    fi

    local count
    count=$(jq '.forbidden_patterns | length' "$IMMUNITY_FILE")

    local categories
    categories=$(jq '.pattern_categories' "$IMMUNITY_FILE")

    local recent
    recent=$(jq -r '.forbidden_patterns[-1] // {} | .tool + ": " + (.command // "unknown")' "$IMMUNITY_FILE")

    jq -n --argjson count "$count" \
          --argjson categories "$categories" \
          --arg recent "$recent" \
          '{count: $count, categories: $categories, recent: $recent}'
}

# Get wheel summary
get_wheel_summary() {
    if [ ! -f "$WHEEL_FILE" ]; then
        echo "{}"
        return
    fi
    cat "$WHEEL_FILE"
}
