# pw_indexed.sh Troubleshooting Guide

This guide covers common issues and solutions when using pw_indexed.sh.

## Table of Contents

1. [Installation Issues](#installation-issues)
2. [Permission and Access Issues](#permission-and-access-issues)
3. [qpwgraph Integration Issues](#qpwgraph-integration-issues)
4. [Connection Management Issues](#connection-management-issues)
5. [Patchbay Import/Export Issues](#patchbay-importexport-issues)
6. [Performance Issues](#performance-issues)
7. [Debugging and Logging](#debugging-and-logging)

## Installation Issues

### Issue: "Command not found" errors
```bash
pw_indexed: command not found
```

**Causes:**
- Script not in PATH
- Script not executable
- Missing dependencies

**Solutions:**
1. **Check if script is executable:**
   ```bash
   ls -la pw_indexed.sh
   chmod +x pw_indexed.sh
   ```

2. **Add to PATH or create symlink:**
   ```bash
   # Option 1: Symlink to user bin
   mkdir -p ~/.local/bin
   ln -sf $(pwd)/pw_indexed.sh ~/.local/bin/pw_indexed
   
   # Option 2: System-wide installation
   sudo cp pw_indexed.sh /usr/local/bin/pw_indexed
   sudo chmod +x /usr/local/bin/pw_indexed
   ```

3. **Check PATH includes the directory:**
   ```bash
   echo $PATH | grep -o ~/.local/bin
   # If not found, add to ~/.bashrc:
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

### Issue: Missing dependencies
```bash
./pw_indexed.sh: line X: jq: command not found
./pw_indexed.sh: line X: pw-dump: command not found
```

**Solutions:**
```bash
# Fedora/RHEL/CentOS
sudo dnf install pipewire pipewire-utils jq qpwgraph

# Ubuntu/Debian
sudo apt update
sudo apt install pipewire pipewire-utils jq qpwgraph

# Arch Linux
sudo pacman -S pipewire pipewire-utils jq qpwgraph

# Verify installation
which pw-dump pw-link jq
pw-dump --version
```

## Permission and Access Issues

### Issue: PipeWire session not accessible
```bash
ERROR: Failed to connect to PipeWire
```

**Causes:**
- PipeWire not running
- User not in audio group
- Session bus issues

**Solutions:**
1. **Check PipeWire status:**
   ```bash
   systemctl --user status pipewire
   systemctl --user status wireplumber
   
   # If not running:
   systemctl --user enable --now pipewire wireplumber
   ```

2. **Check audio group membership:**
   ```bash
   groups $USER | grep audio
   
   # If not in audio group:
   sudo usermod -a -G audio $USER
   # Log out and back in
   ```

3. **Check session environment:**
   ```bash
   env | grep PIPEWIRE
   env | grep XDG_RUNTIME_DIR
   
   # Restart session if needed
   ```

### Issue: Permission denied on cache directory
```bash
mkdir: cannot create directory '/tmp/pw_indexed': Permission denied
```

**Solutions:**
```bash
# Check /tmp permissions
ls -ld /tmp

# Clean up any conflicting cache
sudo rm -rf /tmp/pw_indexed
mkdir -p /tmp/pw_indexed

# Or set alternative cache location by modifying the script:
# CACHE_DIR="$HOME/.cache/pw_indexed"
```

## qpwgraph Integration Issues

### Issue: qpwgraph pause/resume not working
```bash
qpwgraph not running
# or connections still being interfered with
```

**Causes:**
- qpwgraph not running
- Process signals not working
- Auto-reconnect enabled in qpwgraph

**Solutions:**
1. **Verify qpwgraph is running:**
   ```bash
   pgrep -f qpwgraph
   ps aux | grep qpwgraph
   ```

2. **Check qpwgraph settings:**
   - Disable "Auto Connect" in qpwgraph settings
   - Disable "Persistent" connections if enabled

3. **Manual service management:**
   ```bash
   # Kill qpwgraph completely during operations
   killall qpwgraph
   # ... perform pw_indexed operations ...
   qpwgraph &
   ```

4. **Alternative: Use specific session file:**
   ```bash
   # Export current state first
   ./pw_indexed.sh export backup.qpwgraph
   # Close qpwgraph, make changes, then import
   ./pw_indexed.sh import backup.qpwgraph
   ```

### Issue: Node enumeration doesn't match qpwgraph
```bash
# pw_indexed shows: ee_soe_multiband_gate~1
# qpwgraph shows: ee_soe_multiband_gate-1
```

**Explanation:**
This is expected behavior. pw_indexed uses tilde notation (`~`) while qpwgraph uses dash notation (`-`). Both refer to the same nodes.

**Workarounds:**
1. **Use node IDs directly in scripts:**
   ```bash
   ./pw_indexed.sh nodes --oneline | grep multiband
   # Use the @nodeID suffix for exact identification
   ```

2. **Pattern matching works with both:**
   ```bash
   ./pw_indexed.sh connect "*multiband*"
   ```

## Connection Management Issues

### Issue: "Node not found" errors
```bash
ERROR: Source node not found: non_existent_node
```

**Diagnosis:**
1. **Check node exists:**
   ```bash
   ./pw_indexed.sh nodes | grep -i "partial_name"
   ./pw_indexed.sh nodes "*pattern*"
   ```

2. **Use exact indexed name:**
   ```bash
   # Wrong:
   ./pw_indexed.sh make "ee_soe_multiband_gate:output->target:input"
   
   # Right (check enumeration first):
   ./pw_indexed.sh nodes "*multiband*"
   ./pw_indexed.sh make "ee_soe_multiband_gate~1:output->target:input"
   ```

### Issue: "Port not found" errors
```bash
ERROR: Source port not found: node:wrong_port
```

**Solutions:**
1. **Check available ports:**
   ```bash
   ./pw_indexed.sh ports "node_name"
   ./pw_indexed.sh ports "node_name" --output
   ./pw_indexed.sh ports "node_name" --input
   ```

2. **Use exact port names:**
   ```bash
   # Check port name format:
   ./pw_indexed.sh ports jamesdsp_sink
   # Use exact names: playback_FL, monitor_FL, etc.
   ```

### Issue: Connection already exists
```bash
Connection already exists (Link ID: 12345)
```

**This is not an error** - pw_indexed.sh safely handles existing connections. If you need to replace a connection:

```bash
# Use exclusive command to remove conflicts:
./pw_indexed.sh exclusive "source:port->target:port"

# Or remove specific connection first:
./pw_indexed.sh remove "source:port->target:port"
./pw_indexed.sh make "source:port->new_target:port"
```

## Patchbay Import/Export Issues

### Issue: XML parsing errors
```bash
./pw_indexed.sh: line 1400: process_patchbay_item: command not found
```

**This is a known issue** with xmllint parsing. The script falls back to basic parsing automatically.

**Workarounds:**
1. **Install xmllint (recommended):**
   ```bash
   # Fedora/RHEL
   sudo dnf install libxml2
   
   # Ubuntu/Debian
   sudo apt install libxml2-utils
   
   # Arch Linux
   sudo pacman -S libxml2
   ```

2. **Use simpler patchbay files:**
   - Export from pw_indexed.sh creates compatible format
   - Some qpwgraph files may have complex XML that needs xmllint

### Issue: Import mode not working as expected
```bash
# Connections not being replaced/merged properly
```

**Solutions:**
1. **Understand import modes:**
   ```bash
   # add (default): Adds new connections, keeps existing
   ./pw_indexed.sh import setup.qpwgraph
   
   # replace: Removes ALL existing connections first
   ./pw_indexed.sh import --mode replace clean_slate.qpwgraph
   
   # merge: Smart merge (same as add currently)
   ./pw_indexed.sh import --mode merge additional.qpwgraph
   ```

2. **Always use dry-run first:**
   ```bash
   ./pw_indexed.sh import --dry-run --mode replace risky_setup.qpwgraph
   ```

3. **Manual cleanup if needed:**
   ```bash
   # Remove all connections manually:
   ./pw_indexed.sh connect --oneline > current_connections.txt
   # Edit the file to create remove commands
   ```

## Performance Issues

### Issue: Slow response times
```bash
# Commands taking several seconds to complete
```

**Causes:**
- Large number of nodes/connections
- Frequent cache invalidation
- Complex pattern matching

**Solutions:**
1. **Check cache effectiveness:**
   ```bash
   ./pw_indexed.sh --verbose nodes | grep "cached"
   ```

2. **Use specific patterns:**
   ```bash
   # Slow:
   ./pw_indexed.sh connect "*"
   
   # Faster:
   ./pw_indexed.sh connect "*limiter*->*gate*"
   ```

3. **Batch operations:**
   ```bash
   # Create batch file instead of individual commands:
   echo 'make "a:out->b:in"' >> batch.txt
   echo 'make "b:out->c:in"' >> batch.txt
   ./pw_indexed.sh --batch batch.txt
   ```

### Issue: High memory usage
```bash
# Script consuming excessive memory
```

**Solutions:**
1. **Restart PipeWire session periodically:**
   ```bash
   systemctl --user restart pipewire wireplumber
   ```

2. **Clear cache directory:**
   ```bash
   rm -rf /tmp/pw_indexed/*
   ```

## Debugging and Logging

### Enable Verbose Output
```bash
# Add --verbose to any command for detailed logging:
./pw_indexed.sh --verbose nodes
./pw_indexed.sh --verbose make "source:port->target:port"
```

### Check PipeWire State
```bash
# Raw PipeWire data:
pw-dump | jq .

# Check specific node:
pw-dump | jq '.[] | select(.info.props."node.name" == "jamesdsp_sink")'

# Check connections:
pw-dump | jq '.[] | select(.type == "PipeWire:Interface:Link")'
```

### Script Debugging
```bash
# Enable bash debugging:
bash -x ./pw_indexed.sh nodes

# Or add to script temporarily:
set -x  # Enable debugging
./pw_indexed.sh nodes
set +x  # Disable debugging
```

### Log Analysis
```bash
# Check system logs:
journalctl --user -u pipewire
journalctl --user -u wireplumber

# Check script cache:
ls -la /tmp/pw_indexed/
cat /tmp/pw_indexed/pipewire_dump
```

## Common Workflow Issues

### Issue: qpwgraph changes disappearing
**Solution:** Always pause qpwgraph before making programmatic changes:
```bash
./pw_indexed.sh pause qpwgraph
# ... make changes ...
./pw_indexed.sh resume qpwgraph
```

### Issue: Connection changes not persistent
**Solution:** Export your setup to a patchbay file for persistence:
```bash
./pw_indexed.sh export ~/.config/pw_indexed/my_setup.qpwgraph
# Load on startup or when needed:
./pw_indexed.sh import ~/.config/pw_indexed/my_setup.qpwgraph
```

### Issue: Complex connection patterns
**Solution:** Use batch files for complex setups:
```bash
# Create setup.txt:
pause qpwgraph
make "source1:out->effect1:in"
make "effect1:out->effect2:in"
make "effect2:out->sink:in"
resume qpwgraph

# Execute:
./pw_indexed.sh --batch setup.txt
```

---

## Getting Help

If you encounter issues not covered here:

1. **Enable verbose output** and check the detailed logs
2. **Test with --dry-run** to see what would happen
3. **Verify PipeWire and dependencies** are properly installed
4. **Check the examples** in the examples/ directory
5. **Review the architecture documentation** in ARCHITECTURE.md

Remember: pw_indexed.sh is a wrapper around PipeWire tools. Many issues stem from the underlying PipeWire system configuration rather than the script itself.
