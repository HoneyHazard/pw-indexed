# PW_Indexed - Advanced PipeWire Connection Management

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.kernel.org/)

**Version:** 1.0.0  
**License:** MIT

A comprehensive PipeWire connection management tool with indexed node enumeration compatible with qpwgraph's naming system. Built to work around qpwgraph's interference with programmatic connection management while providing powerful automation capabilities for complex audio setups.

## 🎯 Purpose

**Primary Problem Solved:** Managing complex PipeWire audio chains programmatically while maintaining compatibility with qpwgraph's visual workflow. Multiple instances of the same node need deterministic indexing, and qpwgraph actively interferes with programmatic changes when running.

**Solution:** Swiss Army Knife approach combining qpwgraph-compatible enumeration, intelligent service management, pattern-based operations, and full patchbay synchronization.

## 🚀 Key Features

### Core Functionality ✅
- **🔢 Indexed Node Enumeration:** Full compatibility with qpwgraph naming (node, node~1, node~2)
- **⏸️ Service Management:** Intelligent pause/resume of qpwgraph for reliable operations
- **🔗 Connection Management:** Create, remove, and manage connections with pattern matching
- **📋 Multiple Output Formats:** Table, one-liner, and JSON formatting
- **⚡ Smart Caching:** 5-second cache with automatic invalidation

### Advanced Features ✅
- **🔄 Patchbay Synchronization:** Full import/export with qpwgraph XML format
- **⚔️ Exclusive Connections:** Smart conflict resolution when creating connections
- **📝 Batch Processing:** Execute multiple commands from files
- **🧪 Dry-Run Mode:** Preview changes before applying them
- **🎯 Pattern Operations:** Flexible connection matching with glob patterns

### Integration Ready ✅
- **🤖 Script-Friendly:** Designed for automation and integration
- **🎨 qpwgraph Compatible:** Seamless workflow with existing qpwgraph setups
- **🔧 Shell Integration:** Works perfectly in scripts, makefiles, and CI/CD

## 📖 Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/pw_indexed.git ~/projs/pw_indexed

# Make executable and add to PATH
chmod +x ~/projs/pw_indexed/pw_indexed.sh
mkdir -p ~/.local/bin
ln -sf ~/projs/pw_indexed/pw_indexed.sh ~/.local/bin/pw_indexed

# Verify installation
pw_indexed --version
```

## 📚 Usage

### Basic Node Management
```bash
pw_indexed nodes                    # List all indexed nodes
pw_indexed nodes multiband          # Filter by pattern
pw_indexed nodes --oneline          # Canonical format
pw_indexed nodes --json             # JSON output
```

### Port Management
```bash
pw_indexed ports jamesdsp_sink      # Show ports for specific node
pw_indexed ports --input            # Only input ports
pw_indexed ports --output           # Only output ports
pw_indexed ports --oneline          # Canonical format
```

### Service Management (Critical)
```bash
pw_indexed pause qpwgraph           # Pause for reliable operations
pw_indexed resume qpwgraph          # Resume after operations
pw_indexed service status           # Check service states
```

### Canonical Format
The script outputs connections in a standardized format perfect for copy-paste:
```
source_node~N:port_name->target_node~M:port_name
```

Example:
```
ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL
```

## 🏗️ Architecture

### Core Components
1. **Enhanced PipeWire Data Engine** - Caching layer with tilde notation resolution
2. **Service Management System** - qpwgraph interference mitigation  
3. **Pattern Matching Engine** - Flexible filtering system
4. **Output Format System** - Multiple presentation modes

### Node Enumeration Logic
- Uses **ascending node ID sort** (matches qpwgraph exactly)
- `node_name` = first instance (lowest node ID)
- `node_name~1` = second instance
- `node_name~2` = third instance, etc.

### qpwgraph Integration Attempts
- **Pause/Resume:** Experimental use of SIGSTOP/SIGCONT (may cause issues)
- **Enumeration:** Tries to match qpwgraph's visual layout (fragile, may break)
- **Session Conversion:** Planned feature for `node~1` ↔ `node-1` conversion

## 🧪 Development Status

### ✅ Phase 1 - Core Infrastructure (COMPLETE)
- [x] Enhanced PipeWire data engine with caching
- [x] Indexed node enumeration matching qpwgraph
- [x] Service management (qpwgraph pause/resume)
- [x] Pattern matching system
- [x] Multiple output formats
- [x] Basic node/port listing

### ✅ Phase 2 - Connection Operations (COMPLETE)
- [x] Connection listing (`connect` command)
- [x] Connection creation (`make` command)
- [x] Connection removal (`remove` command)
- [x] Exclusive connections (`exclusive` command)
- [x] Dry-run mode implementation
- [x] Batch processing

### ✅ Phase 3 - Patchbay Synchronization (COMPLETE)
- [x] qpwgraph XML export functionality
- [x] qpwgraph XML import with modes (add/replace/merge)
- [x] Patchbay synchronization (`sync` command)
- [x] Command-specific option parsing
- [x] Comprehensive error handling

### 🚧 Phase 4 - Documentation & Examples (IN PROGRESS)
- [x] Comprehensive README update
- [ ] ARCHITECTURE.md deep-dive
- [ ] TROUBLESHOOTING.md guide
- [ ] Example patchbay files
- [ ] Integration documentation

### ✅ Phase 5 - Integration & Polish (COMPLETE)
- [x] Integration with hq_audio.sh (production deployment)
- [x] Advanced error recovery (service management)
- [x] Performance optimizations (caching system)
- [x] Extended test suite (comprehensive validation)

## 🛠️ Contributing

### Testing Requirements
All functionality must be tested at every step:

```bash
# Test basic functionality
cd ~/projs/pw_indexed
./tests/test_basic.sh

# Test enumeration accuracy
./tests/test_enumeration.sh

# Test service management
./tests/test_services.sh
```

### Development Workflow
1. **Test** every feature before integration
2. **Document** architectural changes in `ARCHITECTURE.md`
3. **Update** documentation after significant changes

## 📁 Project Structure

```
pw_indexed/
├── pw_indexed.sh           # Main executable
├── README.md               # This file
├── ARCHITECTURE.md         # Technical architecture
├── WARP.md                 # Warp terminal integration guide
├── tests/                  # Test suite
│   ├── test_basic.sh      # Basic functionality tests
│   ├── test_enumeration.sh # Enumeration accuracy tests
│   └── test_services.sh   # Service management tests
├── docs/                   # Documentation
│   ├── API.md             # Command reference
│   └── TROUBLESHOOTING.md # Common issues
├── examples/               # Example usage
│   └── patchbay_files/    # Sample patchbay configurations
└── .git/                   # Version control
```

## 🎯 Goals (Aspirational)

1. **Enumeration consistency** - Try to match qpwgraph's indexing when possible
2. **Basic service control** - Pause/resume functionality (experimental)
3. **Session compatibility** - Eventually support qpwgraph session files
4. **Usable performance** - Reasonable response times for basic operations
5. **Clear documentation** - Explain what it does and doesn't do

## 🔧 Technical Details

### Dependencies (All the Real Work)
- `bash` 4.0+ (for the wrapper script)
- `jq` 1.6+ (for JSON processing)
- **`pipewire`** with `pw-dump` (the actual audio server doing the heavy lifting)
- **`qpwgraph`** (the sophisticated GUI this tries to complement)
- `systemctl` (for basic service detection)

### Cache Management
- Location: `/tmp/pw_indexed/`
- TTL: 5 seconds
- Automatic invalidation and refresh

### Integration Notes
- May work with existing `hq_audio.sh` workflows (not guaranteed)
- Thin wrapper around `pw-link` and `pw-dump` (all credit to PipeWire devs)
- Attempts to add enumeration info to standard tools

## 📞 Support

- **Issues:** Please open GitHub issues for bugs and feature requests
- **Architecture:** See `ARCHITECTURE.md` for technical details
- **API Reference:** See `docs/API.md` for complete command reference
- **Troubleshooting:** See `docs/TROUBLESHOOTING.md` for common problems

---

**Note:** This is an experimental wrapper around PipeWire tools. It may break with system updates and should not be relied upon for critical audio work. All the real work is done by the PipeWire and qpwgraph developers - this just tries to add some convenience features.
