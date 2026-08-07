# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.1] - 2026-08-07

### Fixed
- **Performance**: `create_all_mappings()`'s indexed-node-name assignment loop forked `echo | tr | sort` (3 subprocesses) per unique node name to sort that name's instances by `object.serial`. Replaced with a pure-bash insertion sort over each name's small instance list (in practice almost always 1, rarely more than a handful) - zero subprocess forks for this step. On a loaded system, subprocess scheduling wait dominated this function's cost: `pw-indexed nodes`/`connect` dropped from ~4-6s wall time (of which only ~0.4s was actual CPU work) to ~0.6-1.2s. Verified byte-identical output across `nodes`, `nodes --detailed`, `nodes --id`, `connect --oneline`, and `ports`, plus `verify_all_functionality.sh` (same pass/warn/fail counts as unmodified `main`) and manual exercise of `make`, tilde-notation resolution, and port lookups against multi-instance nodes.

Note: this entry picks up after a gap where in-script `VERSION` advanced to
1.5.0 without matching CHANGELOG entries (single-call architecture rewrite,
qpwgraph management, etc.) - not backfilled here, only new changes going
forward.

## [1.1.0] - 2024-09-11

### Added
- `--detailed` option for the `nodes` command to show node IDs alongside serial numbers
- Enhanced table format with SERIAL column when using `--detailed`
- Enhanced JSON format with `serial_number` field when using `--detailed`  
- Enhanced oneline format with serial number appended when using `--detailed`
- Serial number display provides visibility into PipeWire's `object.serial` property for debugging

### Changed
- Updated help text to document the new `--detailed` option with examples
- Improved command documentation to show proper usage of the detailed view

## [1.0.1] - Previous Release

### Fixed
- Fixed enumeration mismatch with qpwgraph by switching from node ID ordering to creation order (object.serial)
- Ensures gate~2:probe_FL references work consistently between tools
- Help text updated to reflect all command aliases correctly

## [1.0.0] - Initial Release

### Added
- Indexed node enumeration matching qpwgraph (node~0, node~1, node~2)
- Creation-order based enumeration using object.serial (matches qpwgraph exactly)
- qpwgraph service management (pause/resume for reliable operations)
- Pattern-based connection operations
- Canonical one-liner format for copy-paste
- Live patchbay synchronization
- Comprehensive connection management with multiple arrow format support
- Export/import functionality for qpwgraph patchbay files
- Batch processing capabilities
- Multiple output formats (table, JSON, oneline)
