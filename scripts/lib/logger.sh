#!/usr/bin/env bash
# logger.sh - Logging utilities for Mahoraga
# Usage: source logger.sh

# =============================================================================
# Logging Configuration
# =============================================================================

MAHORAGA_LOG_LEVEL="${MAHORAGA_LOG_LEVEL:-INFO}"
MAHORAGA_LOG_FILE=""

# Log levels: DEBUG=0, INFO=1, WARN=2, ERROR=3
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
)

# =============================================================================
# Logging Functions
# =============================================================================

# Initialize logger with state directory
init_logger() {
    local mahoraga_dir="$1"
    MAHORAGA_LOG_FILE="${mahoraga_dir}/history.log"

    # Ensure log file exists
    if [ ! -f "$MAHORAGA_LOG_FILE" ]; then
        touch "$MAHORAGA_LOG_FILE"
    fi
}

# Internal log function
_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local level_num=${LOG_LEVELS[$level]:-1}
    local current_level_num=${LOG_LEVELS[$MAHORAGA_LOG_LEVEL]:-1}

    # Only log if level is >= current log level
    if [ "$level_num" -ge "$current_level_num" ]; then
        local log_line="[$timestamp] [$level] $message"

        # Write to log file if initialized
        if [ -n "$MAHORAGA_LOG_FILE" ] && [ -f "$MAHORAGA_LOG_FILE" ]; then
            echo "$log_line" >> "$MAHORAGA_LOG_FILE"
        fi

        # Also output to stderr for debugging
        if [ "$MAHORAGA_LOG_LEVEL" = "DEBUG" ]; then
            echo "$log_line" >&2
        fi
    fi
}

# Public logging functions
log_debug() {
    _log "DEBUG" "$1"
}

log_info() {
    _log "INFO" "$1"
}

log_warn() {
    _log "WARN" "$1"
}

log_error() {
    _log "ERROR" "$1"
}

# Shorthand
log() {
    log_info "$1"
}

# =============================================================================
# Specialized Log Functions
# =============================================================================

# Log Mahoraga initialization
log_init() {
    local task="$1"
    local max_rotations="$2"
    log_info "INIT: Task started - \"$task\" (max_rotations: $max_rotations)"
}

# Log wheel spin
log_wheel_spin() {
    local rotation="$1"
    local reason="$2"
    log_info "WHEEL_SPIN: Rotation $rotation - $reason"
}

# Log immunity addition
log_immunity_add() {
    local pattern_id="$1"
    local description="$2"
    log_info "IMMUNITY_ADD: Pattern $pattern_id - $description"
}

# Log PreToolUse block
log_block() {
    local tool="$1"
    local reason="$2"
    log_warn "PRE_TOOL_BLOCK: Blocked $tool - $reason"
}

# Log PreToolUse allow (observe mode)
log_observe() {
    local tool="$1"
    local reason="$2"
    log_info "OBSERVE_MODE: Would block $tool - $reason (immunity disabled)"
}

# Log tool failure
log_failure() {
    local tool="$1"
    local error="$2"
    log_error "TOOL_FAILURE: $tool - $error"
}

# Log validation result
log_validation() {
    local result="$1"
    local details="$2"
    if [ "$result" = "pass" ]; then
        log_info "VALIDATION: Passed - $details"
    else
        log_warn "VALIDATION: Failed - $details"
    fi
}

# Log completion
log_complete() {
    local message="$1"
    log_info "COMPLETE: $message"
}

# Log strategy change
log_strategy_change() {
    local rotation="$1"
    local old_strategy="$2"
    local new_strategy="$3"
    log_info "STRATEGY_CHANGE: Rotation $rotation - $old_strategy -> $new_strategy"
}
