---
description: Show the current Mahoraga session status, immunity database, and wheel state
argument-hint:
disable-model-invocation: true
---

# Mahoraga Status

Display the current status of the Mahoraga adaptive iteration system.

## Instructions

Read and display the Mahoraga state files from the `.mahoraga/` directory:

1. **Check if Mahoraga is active**:
   ```bash
   cat .mahoraga/state.json 2>/dev/null || echo "Mahoraga not initialized"
   ```

2. **Show session state** including:
   - Active status
   - Current task
   - Rotation count / max rotations
   - Started at timestamp
   - Last rotation timestamp
   - Immunity mode (enabled/disabled)
   - Session scope (project/session-only)

3. **Show immunity database summary**:
   ```bash
   cat .mahoraga/immunity.json 2>/dev/null
   ```
   - Total forbidden patterns count
   - Most recent pattern
   - Error categories breakdown

4. **Show wheel state**:
   ```bash
   cat .mahoraga/wheel.json 2>/dev/null
   ```
   - Current strategy
   - Recent adaptations
   - Next trigger rotation

5. **Format the output** as a clear status report:

```
🛞 Mahoraga Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Session:
  Active: Yes/No
  Task: "<task description>"
  Rotation: X / Y
  Started: <timestamp>
  Last rotation: <timestamp>
  Immunity: Enabled/Disabled (observe mode)

Immunity Database:
  Patterns: X forbidden patterns
  Most recent: <tool>: <command>
  Categories:
    - dependency: X
    - permission: Y
    - network: Z

Wheel State:
  Current strategy: <strategy>
  Refactoring triggered: Yes/No
  Next trigger: Rotation X

State directory: <path>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If Mahoraga is not initialized, display:

```
🛞 Mahoraga Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Mahoraga is not active in this directory.

To start a Mahoraga session:
  /mahoraga "<your task>"

Options:
  --max-rotations N    Set max wheel rotations (default: 10)
  --no-immunity        Observe mode (log but don't block)
  --session-only       Don't persist state across sessions
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
