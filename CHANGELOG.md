# Changelog

All notable changes to claude-yolo will be documented in this file.

## [2.0.0-dev] - Unreleased

### Added
- Complete Go rewrite of claude-yolo from Bash
- Clean package architecture (cmd/, internal/, pkg/)
- Comprehensive test suite with 76.6% coverage
- golangci-lint integration
- Makefile with build/test/lint targets
- AGENTS.md playbook for AI development
- Package-level godoc documentation

### Changed
- Binary is now compiled Go (12MB) vs bash script (67KB)
- Improved error handling
- Better terminal output with colors
- Strategy detection uses existing detect.sh scripts

### Compatibility
- All CLI flags preserved
- Works with existing strategies/ directory
- Compatible with .yolo/ configurations
- Auto-migrates legacy sessions

## [1.0.0] - Bash Version

Initial bash implementation.
