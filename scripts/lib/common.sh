#!/usr/bin/env bash
# common.sh - Shared utilities and platform detection for Mahoraga
# Usage: source common.sh

# Don't use set -e in library files to prevent cascading failures
set -uo pipefail

# =============================================================================
# Platform Detection
# =============================================================================

detect_platform() {
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

MAHORAGA_PLATFORM=$(detect_platform)
export MAHORAGA_PLATFORM

# =============================================================================
# Directory and Path Utilities
# =============================================================================

# Get the plugin root directory
get_plugin_root() {
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        echo "$CLAUDE_PLUGIN_ROOT"
    else
        # Fallback: derive from script location
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        echo "$(dirname "$(dirname "$script_dir")")"
    fi
}

# Get the Mahoraga state directory
# Default: $CWD/.mahoraga
# With --session-only: ~/.claude/mahoraga/session-<id>
get_mahoraga_dir() {
    local cwd="${1:-$(pwd)}"
    local session_only="${2:-false}"
    local session_id="${3:-$(date +%s)}"

    if [ "$session_only" = "true" ]; then
        echo "${HOME}/.claude/mahoraga/session-${session_id}"
    else
        echo "${cwd}/.mahoraga"
    fi
}

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

# =============================================================================
# JSON Utilities (jq wrappers)
# =============================================================================

# Check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is required but not installed." >&2
        echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
        exit 1
    fi
}

# Safe JSON read with default
json_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"

    if [ -f "$file" ]; then
        local value
        value=$(jq -r "$path // empty" "$file" 2>/dev/null || echo "")
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            echo "$value"
        else
            echo "$default"
        fi
    else
        echo "$default"
    fi
}

# Safe JSON write
json_set() {
    local file="$1"
    local path="$2"
    local value="$3"
    local is_string="${4:-true}"

    if [ ! -f "$file" ]; then
        echo "{}" > "$file"
    fi

    local tmp_file="${file}.tmp"
    if [ "$is_string" = "true" ]; then
        jq --arg v "$value" "$path = \$v" "$file" > "$tmp_file" && mv "$tmp_file" "$file"
    else
        jq "$path = $value" "$file" > "$tmp_file" && mv "$tmp_file" "$file"
    fi
}

# =============================================================================
# Time Utilities
# =============================================================================

# Get current ISO timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get Unix timestamp
get_unix_timestamp() {
    date +%s
}

# Calculate age in seconds from ISO timestamp
get_age_seconds() {
    local timestamp="$1"
    local current
    current=$(get_unix_timestamp)

    # Parse ISO timestamp to unix (platform-specific)
    local past
    if [ "$MAHORAGA_PLATFORM" = "macos" ]; then
        past=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || echo "0")
    elif [ "$MAHORAGA_PLATFORM" = "windows" ]; then
        # Windows/Git Bash: Parse manually since date -d may not work
        # Format: 2026-01-31T10:00:00Z
        local year month day hour min sec
        year=$(echo "$timestamp" | cut -c1-4)
        month=$(echo "$timestamp" | cut -c6-7)
        day=$(echo "$timestamp" | cut -c9-10)
        hour=$(echo "$timestamp" | cut -c12-13)
        min=$(echo "$timestamp" | cut -c15-16)
        sec=$(echo "$timestamp" | cut -c18-19)
        # Approximate calculation (doesn't account for leap years perfectly)
        past=$(( (year - 1970) * 31536000 + (month - 1) * 2592000 + (day - 1) * 86400 + hour * 3600 + min * 60 + sec ))
    else
        # Linux
        past=$(date -d "$timestamp" +%s 2>/dev/null || echo "0")
    fi

    echo $((current - past))
}

# =============================================================================
# Hash Utilities
# =============================================================================

# Generate a hash for an approach signature (cross-platform)
generate_hash() {
    local input="$1"
    if [ "$MAHORAGA_PLATFORM" = "macos" ]; then
        echo -n "$input" | md5 | cut -d' ' -f1
    else
        # Linux and Windows (Git Bash has md5sum)
        echo -n "$input" | md5sum | cut -d' ' -f1
    fi
}

# =============================================================================
# Tool Input Extraction (shared helper)
# =============================================================================

# Extract command/identifier from tool input for immunity checking
extract_command_from_tool() {
    local tool_name="$1"
    local tool_input="$2"
    local max_length="${3:-200}"

    case "$tool_name" in
        Bash)
            echo "$tool_input" | jq -r '.command // ""'
            ;;
        Write|Edit)
            echo "$tool_input" | jq -r '.file_path // ""'
            ;;
        WebFetch)
            echo "$tool_input" | jq -r '.url // ""'
            ;;
        *)
            echo "$tool_input" | jq -c '.' 2>/dev/null | head -c "$max_length"
            ;;
    esac
}

# =============================================================================
# Error Categorization
# =============================================================================

# Categorize error message into a category
categorize_error() {
    local error_message="$1"

    # Lowercase for matching
    local lower_error
    lower_error=$(echo "$error_message" | tr '[:upper:]' '[:lower:]')

    if echo "$lower_error" | grep -qE "modulenotfound|no module named|import error|cannot find module|package.*not found"; then
        echo "dependency"
    elif echo "$lower_error" | grep -qE "permission denied|access denied|eacces|eperm|not permitted"; then
        echo "permission"
    elif echo "$lower_error" | grep -qE "timeout|timed out|etimedout|econnreset|connection refused|network"; then
        echo "network"
    elif echo "$lower_error" | grep -qE "file not found|no such file|enoent|directory not found"; then
        echo "file_not_found"
    elif echo "$lower_error" | grep -qE "syntax error|unexpected token|parse error"; then
        echo "syntax"
    elif echo "$lower_error" | grep -qE "out of memory|heap|stack overflow|memory"; then
        echo "memory"
    elif echo "$lower_error" | grep -qE "authentication|unauthorized|401|403|invalid.*token|invalid.*key"; then
        echo "auth"
    elif echo "$lower_error" | grep -qE "rate limit|too many requests|429|throttl"; then
        echo "rate_limit"
    else
        echo "unknown"
    fi
}

# =============================================================================
# Initialization Check
# =============================================================================

# Note: jq check is done in individual scripts, not on source
# This prevents library sourcing from failing
