#!/usr/bin/env bash
# immunity.sh - Immunity database operations for Mahoraga
# Usage: source immunity.sh

# =============================================================================
# Configuration
# =============================================================================

# Immunity expires after 10 minutes (600 seconds)
IMMUNITY_EXPIRY_SECONDS=600

# =============================================================================
# Immunity Operations
# =============================================================================

# Add a pattern to the immunity database
# Args: tool, command, error_type, error_message
immunity_add() {
    local tool="$1"
    local command="$2"
    local error_type="$3"
    local error_message="$4"

    local timestamp
    timestamp=$(get_timestamp)

    local rotation
    rotation=$(get_rotation_count)

    local category
    category=$(categorize_error "$error_message")

    # Generate unique ID
    local id
    id=$(generate_hash "${tool}:${command}:${timestamp}")
    id="${id:0:8}"

    # Create the pattern entry
    local pattern_json
    pattern_json=$(jq -n \
        --arg id "$id" \
        --arg tool "$tool" \
        --arg cmd "$command" \
        --arg err_type "$error_type" \
        --arg err_msg "$error_message" \
        --arg cat "$category" \
        --arg ts "$timestamp" \
        --argjson rot "$rotation" \
        '{
            id: $id,
            tool: $tool,
            command: $cmd,
            error_type: $err_type,
            error_message: $err_msg,
            category: $cat,
            logged_at: $ts,
            rotation: $rot
        }')

    # Add to immunity database
    local tmp_file="${IMMUNITY_FILE}.tmp"
    jq --argjson pattern "$pattern_json" \
       --arg cat "$category" \
       '.forbidden_patterns += [$pattern] |
        .pattern_categories[$cat] = ((.pattern_categories[$cat] // 0) + 1)' \
       "$IMMUNITY_FILE" > "$tmp_file" && mv "$tmp_file" "$IMMUNITY_FILE"

    log_immunity_add "$id" "$tool: $command ($category)"

    echo "$id"
}

# Check if an approach is blocked by immunity
# Args: tool, command
# Returns: 0 = allowed, 1 = blocked
immunity_check() {
    local tool="$1"
    local command="$2"

    # If no immunity file, allow
    if [ ! -f "$IMMUNITY_FILE" ]; then
        return 0
    fi

    local current_time
    current_time=$(get_unix_timestamp)

    # Get matching patterns for this tool as compact JSON lines (one per line)
    local matches
    matches=$(jq -c --arg t "$tool" \
        '.forbidden_patterns[] | select(.tool == $t)' \
        "$IMMUNITY_FILE" 2>/dev/null)

    if [ -z "$matches" ]; then
        return 0  # No immunity entries for this tool
    fi

    # Check each pattern (each line is a compact JSON object)
    while IFS= read -r pattern; do
        if [ -z "$pattern" ]; then
            continue
        fi

        local pattern_command
        pattern_command=$(echo "$pattern" | jq -r '.command')

        local logged_at
        logged_at=$(echo "$pattern" | jq -r '.logged_at')

        # Check age
        local age_seconds
        age_seconds=$(get_age_seconds "$logged_at")

        # Check if immunity has expired
        if [ "$age_seconds" -gt "$IMMUNITY_EXPIRY_SECONDS" ]; then
            log_debug "Immunity expired for pattern (age: ${age_seconds}s)"
            continue  # Expired, check next pattern
        fi

        # Check for exact or similar match
        if is_similar_command "$command" "$pattern_command"; then
            # Check if context has changed
            if context_changed_since "$logged_at"; then
                log_debug "Context changed, allowing retry"
                continue  # Context changed, allow
            fi

            # Immunity applies - block
            local pattern_id
            pattern_id=$(echo "$pattern" | jq -r '.id')

            local error_type
            error_type=$(echo "$pattern" | jq -r '.error_type')

            echo "BLOCKED by pattern $pattern_id: Previous failure with $error_type (${age_seconds}s ago)"
            return 1
        fi
    done <<< "$matches"

    return 0  # No matching immunity
}

# Check if two commands are similar enough to be blocked
is_similar_command() {
    local cmd1="$1"
    local cmd2="$2"

    # Exact match
    if [ "$cmd1" = "$cmd2" ]; then
        return 0
    fi

    # Extract base command (first word)
    local base1
    base1=$(echo "$cmd1" | awk '{print $1}')
    local base2
    base2=$(echo "$cmd2" | awk '{print $1}')

    # If base commands are different, not similar
    if [ "$base1" != "$base2" ]; then
        return 1
    fi

    # For specific commands, check more carefully
    case "$base1" in
        pip|pip3)
            # pip install X and pip install X are similar
            # pip install X and pip install Y are different
            # Use awk for POSIX compatibility (no grep -P)
            local pkg1 pkg2
            pkg1=$(echo "$cmd1" | awk '/install/ {for(i=1;i<=NF;i++) if($i=="install" && $(i+1)) print $(i+1)}')
            pkg2=$(echo "$cmd2" | awk '/install/ {for(i=1;i<=NF;i++) if($i=="install" && $(i+1)) print $(i+1)}')
            [ "$pkg1" = "$pkg2" ]
            ;;
        npm|yarn|pnpm)
            # Similar logic for node package managers
            local pkg1 pkg2
            pkg1=$(echo "$cmd1" | awk '/(install|add)/ {for(i=1;i<=NF;i++) if($i=="install" || $i=="add") {if($(i+1)) print $(i+1)}}')
            pkg2=$(echo "$cmd2" | awk '/(install|add)/ {for(i=1;i<=NF;i++) if($i=="install" || $i=="add") {if($(i+1)) print $(i+1)}}')
            [ "$pkg1" = "$pkg2" ]
            ;;
        *)
            # For other commands, only exact match
            [ "$cmd1" = "$cmd2" ]
            ;;
    esac
}

# Check if context has changed since a timestamp
# Context changes include: file modifications, env changes
context_changed_since() {
    local timestamp="$1"

    # Check if any files in current directory were modified after the timestamp
    local modified_count=0

    if [ "$MAHORAGA_PLATFORM" = "macos" ]; then
        # macOS: create reference file with timestamp, use -newer
        local ts_formatted
        ts_formatted=$(echo "$timestamp" | sed 's/-//g;s/://g;s/T//;s/Z//' | cut -c1-12)
        touch -t "$ts_formatted" /tmp/mahoraga_ts_check 2>/dev/null || return 0
        modified_count=$(find . -maxdepth 2 -newer /tmp/mahoraga_ts_check -type f 2>/dev/null | wc -l | tr -d ' ')
        rm -f /tmp/mahoraga_ts_check
    elif [ "$MAHORAGA_PLATFORM" = "windows" ]; then
        # Windows/Git Bash: Use reference file approach (similar to macOS)
        # Create a temp file with the reference timestamp
        local ts_formatted
        ts_formatted=$(echo "$timestamp" | sed 's/-//g;s/://g;s/T//;s/Z//' | cut -c1-12)
        touch -t "$ts_formatted" /tmp/mahoraga_ts_check 2>/dev/null || return 0
        modified_count=$(find . -maxdepth 2 -newer /tmp/mahoraga_ts_check -type f 2>/dev/null | wc -l | tr -d ' ')
        rm -f /tmp/mahoraga_ts_check
    else
        # Linux: use -newermt with ISO timestamp
        modified_count=$(find . -maxdepth 2 -newermt "$timestamp" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi

    # If files were modified, context changed
    if [ "$modified_count" -gt 0 ]; then
        log_debug "Context changed: $modified_count files modified since $timestamp"
        return 0
    fi

    return 1  # No context change
}

# Get count of forbidden patterns
immunity_count() {
    if [ ! -f "$IMMUNITY_FILE" ]; then
        echo "0"
        return
    fi
    jq '.forbidden_patterns | length' "$IMMUNITY_FILE"
}

# Get most common error category
get_dominant_category() {
    if [ ! -f "$IMMUNITY_FILE" ]; then
        echo "unknown"
        return
    fi

    jq -r '.pattern_categories | to_entries | max_by(.value) | .key // "unknown"' "$IMMUNITY_FILE"
}

# Clear expired immunity entries
cleanup_expired_immunity() {
    if [ ! -f "$IMMUNITY_FILE" ]; then
        return
    fi

    local current_time
    current_time=$(get_unix_timestamp)

    # This is complex in bash, so we'll just note it for now
    # In practice, immunity_check skips expired entries anyway
    log_debug "Cleanup expired immunity entries (handled at check time)"
}

# Reset all immunity (for /mahoraga:reset command)
immunity_reset() {
    if [ -f "$IMMUNITY_FILE" ]; then
        local plugin_root
        plugin_root=$(get_plugin_root)
        cp "${plugin_root}/templates/immunity.template.json" "$IMMUNITY_FILE"
        log_info "Immunity database reset"
    fi
}
