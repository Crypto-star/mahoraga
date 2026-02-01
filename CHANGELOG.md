# Changelog

All notable changes to the Mahoraga plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-01

### Added
- Initial release of Mahoraga adaptive autonomous agent plugin
- **Immunity System**: Tracks failed approaches and blocks identical retry attempts
  - Time-decay immunity (10-minute expiry)
  - Context change detection (allows retry if files modified)
  - Similar command matching for package managers (pip, npm, yarn)
  - Error categorization (dependency, permission, network, auth, rate_limit, etc.)
- **Wheel Rotation System**: Strategy adaptation based on failure count
  - Rotation 3: "Try a different strategy entirely"
  - Rotation 5: "Rethink the architecture"
  - Rotation 10: "Maximum rotations - human guidance needed"
  - Context-aware guidance based on dominant error category
- **Multi-Factor Validation**: Ensures tasks are truly complete
  - Mandatory check: No recent unresolved errors
  - Bonus checks: Tests pass, completion markers, no new TODOs, deliverables exist
- **Structured Logging**: Complete execution history with log levels
- **Hook Integration**:
  - UserPromptSubmit: Session initialization
  - PreToolUse: Immunity checking
  - PostToolUse: Success logging
  - PostToolUseFailure: Failure tracking and wheel spinning
  - Stop: Completion validation
- **Commands**:
  - `/mahoraga "task"` - Start adaptive session
  - `/mahoraga:mahoraga-status` - Check session status
- **Options**:
  - `--max-rotations N` - Set maximum failures before stopping (default: 10)
  - `--no-immunity` - Observe mode: log but don't block
  - `--session-only` - Don't persist state across sessions

### Technical Details
- Cross-platform support (Linux, macOS, Windows/Git Bash)
- Library-based architecture with modular components:
  - `lib/common.sh` - Platform detection, JSON utilities, error categorization
  - `lib/immunity.sh` - Immunity database operations
  - `lib/wheel.sh` - Dharma wheel rotation logic
  - `lib/validator.sh` - Multi-factor completion validation
  - `lib/state.sh` - State management
  - `lib/logger.sh` - Structured logging
- State files stored in `.mahoraga/` directory:
  - `state.json` - Session state
  - `immunity.json` - Forbidden patterns database
  - `wheel.json` - Adaptation tracking
  - `history.log` - Execution log
  - `recent_output.log` - Recent errors for validation

[1.0.0]: https://github.com/Crypto-star/mahoraga/releases/tag/v1.0.0
