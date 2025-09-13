# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
