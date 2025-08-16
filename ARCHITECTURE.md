# pw_indexed Architecture

## Overview

`pw_indexed` is an experimental wrapper around PipeWire tools, attempting to address two common issues:

1. **Node Instance Enumeration:** Multiple instances of the same PipeWire node need consistent, deterministic indexing
2. **qpwgraph Interference:** qpwgraph actively fights programmatic connection changes when running

## Core Architecture

### 1. Enhanced PipeWire Data Engine

**Location:** Lines 120-250 in `pw_indexed.sh`

```bash
Components:
├── get_pipewire_dump()           # Cached pw-dump wrapper
├── create_node_mapping()         # Indexed enumeration engine  
├── resolve_node_id()             # Tilde notation resolver
└── get_port_id()                 # Port ID resolution
```

**Approach:** Attempts to reverse-engineer qpwgraph's enumeration logic (ascending node ID sort). May break if qpwgraph changes.

**Caching Strategy:**
- Location: `/tmp/pw_indexed/pipewire_dump`
- TTL: 5 seconds (configurable via `CACHE_TTL`)
- Automatic invalidation and refresh

### 2. Node Enumeration System

**The Problem:** 
When multiple instances of `ee_soe_multiband_gate` exist, both qpwgraph and scripts need to reference the same instance consistently.

**Our Attempt:**
```bash
# Enumeration Logic (ascending node ID order)
Node ID 201: ee_soe_multiband_gate      # Base instance (no suffix)
Node ID 238: ee_soe_multiband_gate~1    # Second instance (~1)  
Node ID 315: ee_soe_multiband_gate~2    # Third instance (~2)
```

**Implementation:**
```bash
create_node_mapping() {
    # 1. Collect all nodes, sort by ascending node ID
    # 2. Group by node name
    # 3. Assign indices: lowest ID = base, higher IDs = ~1, ~2, etc.
    # 4. Store in global associative arrays
}
```

### 3. Service Management System

**Location:** Lines 250-325 in `pw_indexed.sh`

**The Problem:**
qpwgraph actively monitors and "fixes" connections, fighting against programmatic changes.

**Our Approach:**
```bash
pause_qpwgraph()  # SIGSTOP - experimental, may cause issues
resume_qpwgraph() # SIGCONT - tries to restore normal operation
```

**Service State Detection:**
```bash
is_qpwgraph_running() # Process detection
service_status()      # Comprehensive service state
```

### 4. Pattern Matching Engine

**Location:** Lines 326-340 in `pw_indexed.sh`

Simple but effective glob pattern matching for filtering:
```bash
pattern_match() {
    case "$text" in
        $pattern) return 0 ;;
        *) return 1 ;;
    esac
}
```

**Usage Examples:**
- `nodes multiband*` - All nodes starting with "multiband"
- `ports *gate*` - All ports containing "gate"
- `connect probe_*` - All connections to probe ports

### 5. Output Format System

**Location:** Lines 343-476 in `pw_indexed.sh`

Three distinct output modes:

1. **Table Format** (default) - Human-readable tables
2. **Oneline Format** - Canonical copy-paste format
3. **JSON Format** - Machine-readable structured data

**Canonical Format Specification:**
```
source_node~N:port_name->target_node~M:port_name
```

**Example:**
```
ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL
```

## Data Flow

### Node Enumeration Flow
```
pw-dump → jq processing → sort by node ID → group by name → assign indices → store in arrays
```

### Command Processing Flow
```
CLI args → option parsing → command dispatch → create_node_mapping() → execute operation → format output
```

### Service Management Flow
```
detect qpwgraph → pause if running → perform operations → resume if was running
```

## Key Data Structures

### Global Associative Arrays
```bash
declare -gA node_instances      # node_id -> "indexed_name"
declare -gA instance_counters   # node_name -> count  
declare -gA node_id_lists      # node_name -> "id1 id2 id3"
```

### Configuration Variables
```bash
CACHE_TTL=5                    # Cache validity in seconds
QPWGRAPH_PROCESS="qpwgraph"   # Process name for service management
WIREPLUMBER_SERVICE="wireplumber" # SystemD service name
```

## qpwgraph Compatibility

### Enumeration Synchronization Attempt
- **Problem:** qpwgraph uses visual enumeration that scripts need to match
- **Our Approach:** Try to use same ascending node ID sort algorithm
- **Status:** Works in testing, but fragile - may break with updates

### Session File Conversion (Planned)
- **Export:** `node~1` → `node-1` (qpwgraph XML format)
- **Import:** `node-1` → `node~1` (script tilde format)  
- **Goal:** Reversible conversion (not yet implemented)

### Service Interference Mitigation (Experimental)
- **Problem:** qpwgraph auto-reconnects and fights script changes
- **Our Approach:** Pause qpwgraph during operations, resume after
- **Implementation:** SIGSTOP/SIGCONT (may cause instability)

## Performance Characteristics

### Caching Strategy
- **Cache Hit:** ~10ms response time
- **Cache Miss:** ~200ms response time (pw-dump + processing)
- **Cache TTL:** 5 seconds (balances freshness vs performance)

### Memory Usage
- **Typical:** ~50KB for associative arrays with 40 nodes
- **Peak:** ~200KB during full enumeration with 200+ nodes
- **Cache File:** ~500KB typical pw-dump output

### Scalability
- **Linear complexity:** O(n) where n = number of nodes
- **Light testing:** Works with typical audio setups (~50 nodes)
- **Bottleneck:** jq processing of pw-dump output (could be slow with many nodes)

## Error Handling Strategy

### Bash Strict Mode
```bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures
```

### Associative Array Safety
```bash
# Prevent "unbound variable" errors
if [[ ${#node_instances[@]} -gt 0 ]]; then
    # Safe to iterate
fi
```

### Service Management Safety
```bash
pkill -STOP -x "$QPWGRAPH_PROCESS" 2>/dev/null || true
# Never fail on service control operations
```

## Extension Points

### Phase 2 - Connection Operations
**Ready for implementation:**
- Connection parsing engine (parse canonical format)
- pw-link integration (make/remove operations)
- Exclusive connection logic
- Batch processing engine

### Phase 3 - Advanced Features  
**Architecture prepared for:**
- Real-time monitoring (polling with cache invalidation)
- Live patchbay synchronization (qpwgraph D-Bus interface)
- Enhanced error handling (rollback capabilities)
- Plugin system (custom connection validators)

## Testing Architecture

### Test Categories
1. **Unit Tests:** Individual function testing
2. **Integration Tests:** End-to-end workflow testing  
3. **Compatibility Tests:** qpwgraph enumeration verification
4. **Performance Tests:** Cache and scalability testing

### Test Data Requirements
- **Minimal:** 5+ nodes with at least 2 duplicate names
- **Standard:** 20+ nodes with multiband gate instances
- **Stress:** 200+ nodes with complex connection graph

## Security Considerations

### Process Control Safety
- Uses SIGSTOP/SIGCONT (non-destructive)
- Never kills processes, only pauses temporarily
- Graceful fallbacks if service control fails

### Cache Security
- Temporary directory in `/tmp` (auto-cleaned on reboot)
- No sensitive data cached (only PipeWire structure)
- No elevation requirements

### Input Validation
- Pattern matching uses bash built-in case statements (safe)
- jq provides JSON parsing security
- No direct shell evaluation of user input

---

**Architecture Status:** Phase 1 basic functionality working, but this is experimental software that wraps the real work done by PipeWire developers. No compatibility guarantees.
