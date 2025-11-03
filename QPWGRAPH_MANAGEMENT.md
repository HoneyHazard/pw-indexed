# Smart qpwgraph Management in pw-indexed

## Overview

`pw-indexed` implements intelligent qpwgraph management to avoid unnecessary process pausing and ensure reliable PipeWire connection operations.

## Implementation Summary

### ✅ Three-Level Intelligence

1. **Patchbay Activation Check**
   - Only intervenes if qpwgraph is running with `--activated` flag
   - Skips all intervention if patchbay is inactive

2. **Connection Compliance Check**
   - **`make`**: Returns early if connection already exists
   - **`remove`**: Returns early if connection doesn't exist
   - **`exclusive`**: Could be enhanced to check if state already complies

3. **Lazy Pause on First Non-Compliance**
   - Only pauses qpwgraph when actually making changes
   - Never pauses for read-only operations or compliant state

### ✅ Single Command Behavior

```bash
./pw-indexed make "source:port > target:port"
```

**Flow:**
1. Check if connection already exists
2. If **exists** → return immediately (no pause) ✓
3. If **doesn't exist** → pause qpwgraph → create → resume ✓

### ✅ Batch Command Behavior

```bash
./pw-indexed --batch commands.txt
```

**Flow:**
1. Set `IN_BATCH_MODE=true`
2. Process each command:
   - Check compliance
   - First non-compliant command pauses qpwgraph (sets `QPWGRAPH_PAUSED_BY_US=true`)
   - Subsequent commands skip pause (already paused)
3. After last command, resume qpwgraph once

**Key Code Locations:**
- Batch mode setup: lines 2529-2542 (main function)
- Pause logic: lines 1370-1380 (make), 1505-1515 (remove)
- Resume logic: lines 1390-1395 (make), 1529-1534 (remove)
- Batch resume: lines 2537-2541 (main function)

## Safe Signal Handling

### ✅ What We Use (CORRECT)
- **SIGSTOP** - Pause process (safe, standard POSIX)
- **SIGCONT** - Resume process (safe, standard POSIX)
- Process stays alive, just temporarily frozen

### ❌ What We Don't Use (DANGEROUS)
- **SIGUSR1** - Was killing/restarting qpwgraph
- Caused process to quit and restart with new PID

## Testing

### Test Single Command Compliance
```bash
# Should return immediately (no pause)
./pw-indexed make "easyeffects_sink:monitor_FL > ee_soe_expander:input_FL"

# Output: "Connection already exists (Link ID: xxx)"
```

### Test Batch Mode
```bash
cat > /tmp/batch.txt << 'EOF'
connections
make "node1:port1 > node2:port2"  # May pause here if non-compliant
make "node3:port3 > node4:port4"  # Uses same pause
remove "node5:port5 > node6:port6"  # Uses same pause
EOF

./pw-indexed --batch /tmp/batch.txt
# Output shows single pause/resume cycle
```

### Test Service Status
```bash
./pw-indexed service status

# Shows:
# qpwgraph: RUNNING (patchbay ACTIVE - may interfere with connections)
# qpwgraph: RUNNING (patchbay INACTIVE - won't interfere)
# qpwgraph: PAUSED (use 'pw-indexed resume qpwgraph' to unpause)
```

## Architecture Details

### Global Flags

- `QPWGRAPH_PAUSED_BY_US` - Tracks if we paused qpwgraph
- `IN_BATCH_MODE` - Prevents premature resume during batch
- `QPWGRAPH_MANAGEMENT_DISABLED` - Disables all qpwgraph management

### Key Functions

```bash
needs_qpwgraph_intervention() {
    # Returns 0 if qpwgraph has --activated flag
    # Returns 1 if not running or not activated
}

pause_qpwgraph() {
    # Sends SIGSTOP to qpwgraph process
}

resume_qpwgraph() {
    # Sends SIGCONT to qpwgraph process
}
```

### Pause Decision Logic

```bash
# In make_connection, remove_connection, exclusive_connection:
local qpw_was_paused=false
if [[ "$QPWGRAPH_MANAGEMENT_DISABLED" != true ]] && 
   [[ "$QPWGRAPH_PAUSED_BY_US" != true ]]; then
    if needs_qpwgraph_intervention; then
        pause_qpwgraph
        QPWGRAPH_PAUSED_BY_US=true
        qpw_was_paused=true
    fi
fi

# Resume only if NOT in batch mode
if [[ "$qpw_was_paused" == true ]] && 
   [[ "${IN_BATCH_MODE:-false}" != true ]]; then
    resume_qpwgraph
    QPWGRAPH_PAUSED_BY_US=false
fi
```

## Environment Variables

### `PW_INDEXED_NO_QPWGRAPH_MGMT`
Disable all qpwgraph management:
```bash
export PW_INDEXED_NO_QPWGRAPH_MGMT=true
./pw-indexed make "source > target"  # Never pauses qpwgraph
```

## Benefits

1. **No Unnecessary Pausing** - Only when state needs changing
2. **Batch Efficiency** - Single pause for entire batch
3. **Safe Process Handling** - Never kills qpwgraph
4. **GUI Remains Usable** - Can interact during pause (frozen but visible)
5. **Automatic Cleanup** - Trap ensures resume on exit

## Future Enhancements

### Exclusive Connection Compliance
Add early return in `exclusive_connection()` if:
- Desired connection exists
- No conflicting connections to same target port

### Pattern-Based Batch Optimization
Pre-scan batch file to detect if any command needs changes before pausing.

## Troubleshooting

### qpwgraph Stays Paused
```bash
# Check if paused
./pw-indexed service status

# Manually resume
./pw-indexed resume qpwgraph
```

### Commands Still Pause When Not Needed
Check verbose output:
```bash
./pw-indexed --verbose make "connection"
# Should show: "Connection already exists - no action needed"
# Should NOT show: "Pausing qpwgraph"
```

### qpwgraph Keeps Restarting
If qpwgraph has different PID after operations:
- Check if using SIGUSR1 anywhere (should NOT be used)
- Ensure SIGSTOP/SIGCONT are being used
- Check qpwgraph logs for crash reasons

## References

- Main implementation: `pw-indexed` lines 379-435 (service management)
- Compliance checks: lines 1344-1368 (make), 1481-1524 (remove)
- Batch mode: lines 2441-2542
