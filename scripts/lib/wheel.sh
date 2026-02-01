#!/usr/bin/env bash
# wheel.sh - Dharma Wheel rotation logic for Mahoraga
# Usage: source wheel.sh

# =============================================================================
# Wheel State Operations
# =============================================================================

# Spin the wheel (increment rotation, trigger adaptations)
spin_wheel() {
    local reason="$1"

    # Increment rotation in state
    local new_rotation
    new_rotation=$(increment_rotation)

    local timestamp
    timestamp=$(get_timestamp)

    # Determine new strategy based on rotation
    local current_strategy
    current_strategy=$(json_get "$WHEEL_FILE" ".current_strategy" "initial")

    local new_strategy="$current_strategy"
    local refactoring_triggered=false

    case "$new_rotation" in
        1|2)
            new_strategy="retry_with_awareness"
            ;;
        3)
            new_strategy="alternative_approach"
            refactoring_triggered=true
            ;;
        4)
            new_strategy="expanded_alternatives"
            ;;
        5)
            new_strategy="architectural_rethink"
            refactoring_triggered=true
            ;;
        6|7|8|9)
            new_strategy="systematic_exploration"
            ;;
        10)
            new_strategy="human_guidance_needed"
            refactoring_triggered=true
            ;;
        *)
            new_strategy="exhausted"
            ;;
    esac

    # Create adaptation entry
    local adaptation
    adaptation=$(jq -n \
        --argjson rot "$new_rotation" \
        --arg trigger "$reason" \
        --arg action "strategy_change: $new_strategy" \
        --arg ts "$timestamp" \
        '{rotation: $rot, trigger: $trigger, action: $action, timestamp: $ts}')

    # Update wheel state
    local tmp_file="${WHEEL_FILE}.tmp"
    jq --arg old "$current_strategy" \
       --arg new "$new_strategy" \
       --argjson ref "$refactoring_triggered" \
       --argjson adaptation "$adaptation" \
       '.last_strategy = $old |
        .current_strategy = $new |
        .rotation_count += 1 |
        .refactoring_triggered = $ref |
        .adaptations += [$adaptation]' \
       "$WHEEL_FILE" > "$tmp_file" && mv "$tmp_file" "$WHEEL_FILE"

    log_wheel_spin "$new_rotation" "$reason"

    if [ "$current_strategy" != "$new_strategy" ]; then
        log_strategy_change "$new_rotation" "$current_strategy" "$new_strategy"
    fi

    echo "$new_rotation"
}

# Generate guidance message based on rotation and context
generate_guidance_message() {
    local rotation="$1"

    # Get dominant error category for context-aware guidance
    local error_category
    error_category=$(get_dominant_category)

    case "$rotation" in
        3)
            generate_rotation_3_guidance "$error_category"
            ;;
        5)
            generate_rotation_5_guidance "$error_category"
            ;;
        10)
            generate_rotation_10_guidance
            ;;
        *)
            # No special guidance for other rotations
            echo ""
            ;;
    esac
}

# Rotation 3: Strategy change guidance
generate_rotation_3_guidance() {
    local category="$1"

    cat << 'HEADER'

---

## Wheel Rotation 3: Strategy Change Required

The current approach has failed multiple times. Based on the error patterns detected:

HEADER

    case "$category" in
        dependency)
            cat << 'EOF'
**Analysis:** Multiple dependency-related failures detected.

**Suggested approaches:**
- Try alternative package manager (pip -> conda, npm -> yarn/pnpm)
- Use a virtual environment if not already
- Check for conflicting dependency versions with `pip list` or `npm ls`
- Consider using Docker to isolate dependencies
- Try installing with specific version constraints
EOF
            ;;
        permission)
            cat << 'EOF'
**Analysis:** Multiple permission errors detected.

**Suggested approaches:**
- Check file/directory ownership with `ls -la`
- Move operation to user-writable directory
- Check if files are locked by another process
- Consider if elevated permissions are actually needed
- Use `chmod` or `chown` if you own the files
EOF
            ;;
        network)
            cat << 'EOF'
**Analysis:** Multiple network/timeout errors detected.

**Suggested approaches:**
- Add retry logic with exponential backoff
- Check if the service/API is available
- Try with increased timeout values
- Consider using a local cache or mock for testing
- Check firewall or proxy settings
EOF
            ;;
        auth)
            cat << 'EOF'
**Analysis:** Multiple authentication errors detected.

**Suggested approaches:**
- Verify credentials are correctly set in environment
- Check if tokens/keys have expired
- Ensure correct API endpoint is being used
- Review authentication documentation
- Try regenerating API keys/tokens
EOF
            ;;
        rate_limit)
            cat << 'EOF'
**Analysis:** Rate limiting errors detected.

**Suggested approaches:**
- Add delays between requests
- Implement exponential backoff
- Check API rate limit documentation
- Consider caching responses
- Use batch APIs if available
EOF
            ;;
        *)
            cat << 'EOF'
**Analysis:** Multiple failures with varied error types.

**Suggested approaches:**
- Try a fundamentally different library or tool
- Change from synchronous to async approach
- Break the task into smaller subtasks
- Question initial assumptions about the solution
- Review documentation or examples for the correct approach
EOF
            ;;
    esac

    cat << 'FOOTER'

Please analyze the root cause and try a fundamentally different approach.

---

FOOTER
}

# Rotation 5: Architectural rethink guidance
generate_rotation_5_guidance() {
    local category="$1"

    cat << 'EOF'

---

## Wheel Rotation 5: Architectural Rethink Required

Repeated failures suggest deeper structural issues. Consider:

**Fundamental Questions:**
- Is the overall approach correct for this problem?
- Are there missing prerequisites or setup steps?
- Should this be done with entirely different tools?
- Is there documentation that needs to be consulted?

**Architectural Changes to Consider:**
- Completely different technology stack
- Breaking the problem into independent phases
- Using a proven template or boilerplate as starting point
- Reconsidering the requirements themselves

**What to Document:**
- What approaches have been tried
- What specific errors occurred
- What constraints prevent success

Review the error history and consider if the fundamental approach needs to change.

---

EOF
}

# Rotation 10: Human guidance needed
generate_rotation_10_guidance() {
    cat << 'EOF'

---

## Wheel Rotation 10: Human Guidance Required

After 10 adaptation attempts, this task likely requires:

**External Resources:**
- Domain expertise beyond current context
- API keys, credentials, or external services
- Access to systems or documentation not available

**Human Decisions Needed:**
- Design decisions only a human can make
- Clarification of ambiguous requirements
- Approval for significant architectural changes

**Recommended Actions:**
1. Review the error history in `.mahoraga/history.log`
2. Check the immunity database for patterns in `.mahoraga/immunity.json`
3. Provide specific guidance on how to proceed
4. Consider if the task scope needs adjustment

Please provide guidance or adjust the task requirements.

---

EOF
}

# Check if we should trigger refactoring guidance
should_show_guidance() {
    local rotation="$1"

    case "$rotation" in
        3|5|10)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Get next guidance trigger rotation
get_next_trigger() {
    local current="$1"

    if [ "$current" -lt 3 ]; then
        echo "3"
    elif [ "$current" -lt 5 ]; then
        echo "5"
    elif [ "$current" -lt 10 ]; then
        echo "10"
    else
        echo "none"
    fi
}
