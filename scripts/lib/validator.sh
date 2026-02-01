#!/usr/bin/env bash
# validator.sh - Multi-factor completion validation for Mahoraga
# Usage: source validator.sh

# =============================================================================
# Validation Configuration
# =============================================================================

# Minimum bonus score required (out of 4)
MIN_BONUS_SCORE=2

# =============================================================================
# Main Validation Function
# =============================================================================

# Validate if the task appears complete
# Returns: 0 = complete, 1 = incomplete
# Output: JSON with validation details
validate_completion() {
    local transcript_path="${1:-}"
    local mahoraga_dir="${2:-}"

    local mandatory_passed=0
    local mandatory_required=1
    local bonus_score=0
    local bonus_available=4
    local validation_details=()

    # MANDATORY: No recent errors in output
    if check_no_recent_errors "$mahoraga_dir"; then
        ((mandatory_passed++))
        validation_details+=("mandatory:no_errors:pass")
    else
        validation_details+=("mandatory:no_errors:fail")
        log_validation "fail" "Recent errors detected in output"

        # Output validation result
        output_validation_result "fail" "$mandatory_passed" "$mandatory_required" \
            "$bonus_score" "$bonus_available" "${validation_details[*]}"
        return 1
    fi

    # BONUS 1: Tests pass (if test suite exists)
    if has_test_suite; then
        if run_test_suite; then
            ((bonus_score++))
            validation_details+=("bonus:tests:pass")
        else
            validation_details+=("bonus:tests:fail")
        fi
    else
        validation_details+=("bonus:tests:skip")
    fi

    # BONUS 2: Completion markers in transcript
    if check_completion_markers "$transcript_path"; then
        ((bonus_score++))
        validation_details+=("bonus:markers:pass")
    else
        validation_details+=("bonus:markers:fail")
    fi

    # BONUS 3: No new TODOs/FIXMEs in staged changes
    if check_no_new_todos; then
        ((bonus_score++))
        validation_details+=("bonus:no_todos:pass")
    else
        validation_details+=("bonus:no_todos:fail")
    fi

    # BONUS 4: Expected deliverable files exist
    if check_deliverable_files "$transcript_path"; then
        ((bonus_score++))
        validation_details+=("bonus:deliverables:pass")
    else
        validation_details+=("bonus:deliverables:fail")
    fi

    # Check if validation passes
    if [ "$mandatory_passed" -eq "$mandatory_required" ] && [ "$bonus_score" -ge "$MIN_BONUS_SCORE" ]; then
        log_validation "pass" "Mandatory: $mandatory_passed/$mandatory_required, Bonus: $bonus_score/$bonus_available"
        output_validation_result "pass" "$mandatory_passed" "$mandatory_required" \
            "$bonus_score" "$bonus_available" "${validation_details[*]}"
        return 0
    else
        log_validation "fail" "Mandatory: $mandatory_passed/$mandatory_required, Bonus: $bonus_score/$bonus_available (need $MIN_BONUS_SCORE)"
        output_validation_result "incomplete" "$mandatory_passed" "$mandatory_required" \
            "$bonus_score" "$bonus_available" "${validation_details[*]}"
        return 1
    fi
}

# Output validation result as JSON
output_validation_result() {
    local result="$1"
    local mandatory_passed="$2"
    local mandatory_required="$3"
    local bonus_score="$4"
    local bonus_available="$5"
    local details="$6"

    jq -n \
        --arg result "$result" \
        --argjson mp "$mandatory_passed" \
        --argjson mr "$mandatory_required" \
        --argjson bs "$bonus_score" \
        --argjson ba "$bonus_available" \
        --arg details "$details" \
        '{
            result: $result,
            mandatory: {passed: $mp, required: $mr},
            bonus: {score: $bs, available: $ba, required: 2},
            details: $details
        }'
}

# =============================================================================
# Validation Checks
# =============================================================================

# Check for recent errors in output
check_no_recent_errors() {
    local mahoraga_dir="$1"
    local recent_output="${mahoraga_dir}/recent_output.log"

    # If no recent output file, pass by default
    if [ ! -f "$recent_output" ]; then
        return 0
    fi

    # Check for error patterns (case-insensitive)
    if grep -qiE "error:|exception:|failed:|traceback|fatal:" "$recent_output" 2>/dev/null; then
        return 1
    fi

    return 0
}

# Check if a test suite exists
has_test_suite() {
    # Check for common test indicators
    if [ -f "pytest.ini" ] || [ -f "setup.cfg" ] || [ -f "pyproject.toml" ]; then
        if grep -q "pytest" pyproject.toml 2>/dev/null || \
           grep -q "pytest" setup.cfg 2>/dev/null || \
           [ -f "pytest.ini" ]; then
            return 0
        fi
    fi

    if [ -f "package.json" ]; then
        if grep -q '"test"' package.json 2>/dev/null; then
            return 0
        fi
    fi

    if [ -f "Cargo.toml" ]; then
        return 0  # Rust projects have built-in test support
    fi

    if [ -f "go.mod" ]; then
        if ls *_test.go 1>/dev/null 2>&1; then
            return 0
        fi
    fi

    if [ -f "test.sh" ] || [ -f "run_tests.sh" ]; then
        return 0
    fi

    return 1
}

# Run the test suite
run_test_suite() {
    local exit_code=0

    # Try common test runners
    if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
        if command -v pytest &>/dev/null; then
            pytest --tb=no -q 2>/dev/null || exit_code=$?
        fi
    elif [ -f "package.json" ]; then
        if grep -q '"test"' package.json 2>/dev/null; then
            npm test --silent 2>/dev/null || exit_code=$?
        fi
    elif [ -f "Cargo.toml" ]; then
        cargo test --quiet 2>/dev/null || exit_code=$?
    elif [ -f "go.mod" ]; then
        go test ./... 2>/dev/null || exit_code=$?
    elif [ -f "test.sh" ]; then
        bash test.sh 2>/dev/null || exit_code=$?
    fi

    return $exit_code
}

# Check for completion markers in transcript
check_completion_markers() {
    local transcript_path="$1"

    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        return 1  # No transcript, can't check
    fi

    # Look for completion indicators in recent transcript content
    # Check last 1000 lines for performance
    if tail -n 1000 "$transcript_path" 2>/dev/null | \
       grep -qiE "completed|finished|done|successfully|implemented|created|built"; then
        return 0
    fi

    return 1
}

# Check for new TODOs in git changes
check_no_new_todos() {
    # Only check if we're in a git repo
    if ! git rev-parse --git-dir &>/dev/null; then
        return 0  # Not a git repo, pass by default
    fi

    # Check staged changes for TODO/FIXME
    if git diff --cached 2>/dev/null | grep -qiE "^\+.*\b(TODO|FIXME|XXX|HACK)\b"; then
        return 1
    fi

    # Also check unstaged changes
    if git diff 2>/dev/null | grep -qiE "^\+.*\b(TODO|FIXME|XXX|HACK)\b"; then
        return 1
    fi

    return 0
}

# Check if expected deliverable files exist
check_deliverable_files() {
    local transcript_path="$1"

    # This is a heuristic check
    # Look for file references in recent transcript and verify they exist

    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        return 0  # No transcript, pass by default
    fi

    # Extract potential file paths from recent transcript
    local file_refs
    file_refs=$(tail -n 500 "$transcript_path" 2>/dev/null | \
                grep -oE '\b[a-zA-Z0-9_/.-]+\.(py|js|ts|tsx|jsx|go|rs|java|md|json|yaml|yml|sh)\b' | \
                sort -u | head -20)

    if [ -z "$file_refs" ]; then
        return 0  # No file references found, pass
    fi

    local missing=0
    local checked=0

    while IFS= read -r file; do
        if [ -n "$file" ]; then
            ((checked++))
            if [ ! -f "$file" ]; then
                ((missing++))
            fi
        fi
    done <<< "$file_refs"

    # Pass if at least 70% of referenced files exist
    if [ "$checked" -gt 0 ]; then
        local existing=$((checked - missing))
        local threshold=$((checked * 70 / 100))
        if [ "$existing" -ge "$threshold" ]; then
            return 0
        else
            return 1
        fi
    fi

    return 0
}
