# PW_Indexed - Advanced PipeWire Connection Management

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.kernel.org/)

A comprehensive PipeWire connection management tool with **indexed node enumeration** for reliable programmatic audio routing. Features serializable input/output for connections and deterministic node identification inspired by qpwgraph's naming conventions.

> **Note:** This project has been developed primarily with AI assistance, providing automated audio routing capabilities with a focus on reproducible, scriptable operations.

## 🎯 Purpose

**Core Innovation:** **Indexed node enumeration** - When multiple instances of audio applications create nodes with identical names, PW_Indexed provides deterministic indexing (node, node~1, node~2) enabling reliable programmatic operations.

**Key Distinction:** While inspired by qpwgraph's display naming, PW_Indexed uses **augmented node names** for unique operations rather than just visual labeling. This enables serializable connection specifications that can be reliably reproduced across audio system restarts.

**Serializable I/O:** All connection operations support standardized, machine-readable formats for automation, backup, and restoration of complex audio routing configurations.

## 🚀 Key Features

### Core Functionality ✅
- **🔢 Indexed Node Enumeration:** Full compatibility with qpwgraph naming (node, node~1, node~2)
- **⏸️ Service Management:** Pause/resume of qpwgraph for conflict-free operations
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

### qpwgraph Compatibility

**Important Note:** PW_Indexed is **not fully compatible** with qpwgraph naming - it is **inspired by** qpwgraph's conventions but serves a different purpose:

- **qpwgraph**: Focuses on display/labeling for visual interface
- **PW_Indexed**: Uses augmented node names for unique operations and serializable connections

**Integration Features:**
- **Pause/Resume:** Experimental use of SIGSTOP/SIGCONT (may cause issues)
- **Enumeration:** Attempts to match qpwgraph's visual layout (not guaranteed)
- **Serializable Format:** Enables reproducible connection specifications across system restarts

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
├── tests/                  # Test suite
│   ├── test_basic.sh      # Basic functionality tests
│   ├── test_enumeration.sh # Enumeration accuracy tests
│   └── test_services.sh   # Service management tests
├── docs/                   # Documentation
│   ├── API.md             # Command reference
│   └── TROUBLESHOOTING.md # Common issues
└── examples/               # Example usage
    └── patchbay_files/    # Sample patchbay configurations
```

## 🚀 Future Goals

1. **Enhanced Enumeration Consistency** - Improve matching with qpwgraph's indexing behavior
2. **Robust Service Control** - More reliable pause/resume functionality for qpwgraph integration
3. **Session File Support** - Full qpwgraph session file import/export capabilities
4. **Performance Optimization** - Further improvements to response times and caching efficiency
5. **Extended Serialization** - Additional machine-readable formats for automation ecosystems
6. **Real-time Connection Monitoring** - Live connection change detection and logging

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
- Thin wrapper around `pw-link` and `pw-dump` (all credit to PipeWire devs)
- Attempts to add enumeration info to standard tools
- Designed for integration with automated audio management workflows

## 📞 Support

- **Issues:** Please open GitHub issues for bugs and feature requests
- **Architecture:** See `ARCHITECTURE.md` for technical details
- **API Reference:** See `docs/API.md` for complete command reference
- **Troubleshooting:** See `docs/TROUBLESHOOTING.md` for common problems

---

**Note:** This is an experimental wrapper around PipeWire tools. It may break with system updates and should not be relied upon for critical audio work. All the real work is done by the PipeWire and qpwgraph developers - this just tries to add some convenience features.
