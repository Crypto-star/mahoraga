# 🛞 Mahoraga

**Adaptive autonomous agent plugin for Claude Code that learns from failures and never repeats mistakes.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-blue)](https://claude.ai/code)

Like the mythical Mahoraga that adapts to any attack and becomes immune to it, this plugin enables Claude to:
- **Never repeat a failed approach** - Immunity system tracks failures and blocks identical attempts
- **Adapt strategy** - Wheel rotation triggers strategy changes at key points
- **Validate before completing** - Multi-factor validation ensures tasks are truly complete
- **Learn from errors** - Each failure informs future attempts

## Installation

### Prerequisites
- **Claude Code** >= 1.0.0
- **jq** >= 1.6 (JSON processor)
  ```bash
  # Ubuntu/Debian
  sudo apt install jq

  # macOS
  brew install jq
  ```

### Install Plugin

```bash
# Clone the repository
git clone https://github.com/Crypto-star/mahoraga.git

# Use with Claude Code
claude --plugin-dir ./mahoraga
```

Or add to your Claude plugins directory:
```bash
git clone https://github.com/Crypto-star/mahoraga.git ~/.claude/plugins/mahoraga
```

## Usage

### Start a Mahoraga Session
```
/mahoraga "Your task description here"
```

### Check Session Status
```
/mahoraga:mahoraga-status
```

### Options
```
/mahoraga "task" --max-rotations 15    # Max failures before stopping (default: 10)
/mahoraga "task" --no-immunity         # Observe mode: log but don't block
/mahoraga "task" --session-only        # Don't persist state across sessions
```

## How It Works

### The Adaptive Cycle

```
┌─────────────────────────────────────────────────────────────┐
│                    /mahoraga "task"                         │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  UserPromptSubmit Hook → Creates .mahoraga/ state           │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  PreToolUse Hook → Checks immunity, BLOCKS if failed before │
└─────────────────────┬───────────────────────────────────────┘
                      │
            ┌─────────┴─────────┐
            ▼                   ▼
      ┌───────────┐       ┌───────────┐
      │  SUCCESS  │       │  FAILURE  │
      └─────┬─────┘       └─────┬─────┘
            │                   │
            ▼                   ▼
   ┌─────────────────┐   ┌─────────────────────────────────┐
   │ PostToolUse     │   │ PostToolUseFailure              │
   │ → Logs SUCCESS  │   │ → Logs FAILURE                  │
   └────────┬────────┘   │ → Adds to immunity database     │
            │            │ → Increments rotation count     │
            │            └───────────────┬─────────────────┘
            └───────────────┬────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Stop Hook → Validates completion                           │
│  → BLOCKS if recent failures exist                          │
│  → ALLOWS if successes > failures                           │
└─────────────────────────────────────────────────────────────┘
```

### State Files

All state is stored in `.mahoraga/` directory:

| File | Purpose |
|------|---------|
| `state.json` | Session state (active, task, rotations) |
| `immunity.json` | Failed approaches database |
| `wheel.json` | Adaptation tracking |
| `history.log` | Complete execution log |

### Immunity System

When a command fails:
1. Logged to `history.log` as `FAILURE [UNRESOLVED]`
2. Added to `immunity.json` with signature and error type
3. Future identical commands are **BLOCKED**
4. Claude must try a different approach

**Error Categories:** `dependency`, `permission`, `network`, `file_not_found`, `syntax`, `memory`, `auth`, `rate_limit`, `unknown`

### Rotation Triggers

| Rotation | Guidance |
|----------|----------|
| 3 | "Try a different strategy entirely" |
| 5 | "Rethink the architecture" |
| 10 | "Maximum rotations - session ends" |

## Example Session

```
❯ /mahoraga "Create a script using pandas"

● Testing pandas import...
  → FAILURE: ModuleNotFoundError (added to immunity)

● Trying pip install pandas...
  → FAILURE: externally-managed-environment (added to immunity)

● Trying --break-system-packages...
  → SUCCESS

● Creating script...
  → SUCCESS

● Task completed after 2 rotations

❯ /mahoraga:mahoraga-status

🛞 Mahoraga Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Session: Completed ✓
Rotation: 2 / 10
Immunity: 2 patterns blocked
```

## File Structure

```
mahoraga/
├── .claude-plugin/
│   └── plugin.json           # Plugin manifest
├── commands/
│   ├── mahoraga.md           # Main /mahoraga command
│   └── mahoraga-status.md    # Status command
├── hooks/
│   └── hooks.json            # Hook configuration
├── scripts/
│   ├── init-handler.sh       # Session initialization
│   ├── pre-tool-handler.sh   # Immunity checking
│   ├── post-tool-handler.sh  # Failure logging
│   ├── post-success-handler.sh # Success logging
│   └── stop-handler.sh       # Completion validation
├── templates/                # State file templates
└── README.md
```

## Troubleshooting

### "jq: command not found"
Install jq: `sudo apt install jq` (Ubuntu) or `brew install jq` (macOS)

### Reset immunity database
```bash
rm .mahoraga/immunity.json
# or remove entire state
rm -rf .mahoraga/
```

### Plugin not loading
```bash
claude --plugin-dir ./mahoraga --debug
```

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Created by [Crypto-star](https://github.com/Crypto-star)

Inspired by the mythical Mahoraga (摩睺羅伽) - a divine being that adapts to overcome any challenge.

---

🛞 **Mahoraga** - Persistence with Intelligence
