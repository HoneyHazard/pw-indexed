#!/bin/bash

# pw_indexed.sh - Basic Usage Examples
# 
# This file demonstrates the core functionality of pw_indexed.sh
# Run each section independently to see the results

# Exit on any error for safety
set -e

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PW_INDEXED="$SCRIPT_DIR/../pw_indexed.sh"

echo "=== pw_indexed.sh Basic Usage Examples ==="
echo "Script location: $PW_INDEXED"
echo ""

# Verify the script exists
if [[ ! -x "$PW_INDEXED" ]]; then
    echo "ERROR: pw_indexed.sh not found or not executable at $PW_INDEXED"
    exit 1
fi

echo "### 1. Node Management ###"
echo ""

# List all nodes with indexed enumeration
echo "--- All nodes with indexed names ---"
$PW_INDEXED nodes | head -20
echo "(showing first 20 nodes)"
echo ""

# Filter nodes by pattern
echo "--- Filter nodes containing 'sink' ---"
$PW_INDEXED nodes "*sink*"
echo ""

# Show nodes in one-line format (great for scripting)
echo "--- Nodes in canonical one-line format ---"
$PW_INDEXED nodes --oneline | head -10
echo "(showing first 10 nodes)"
echo ""

echo "### 2. Port Management ###"
echo ""

# Get the first available sink for port demonstration
DEMO_NODE=$($PW_INDEXED nodes "*sink*" --oneline | head -1 | cut -d'@' -f1)
if [[ -n "$DEMO_NODE" ]]; then
    echo "--- Ports for node: $DEMO_NODE ---"
    $PW_INDEXED ports "$DEMO_NODE"
    echo ""
    
    echo "--- Input ports only ---"
    $PW_INDEXED ports "$DEMO_NODE" --input
    echo ""
    
    echo "--- Output ports in one-line format ---"
    $PW_INDEXED ports "$DEMO_NODE" --output --oneline
    echo ""
else
    echo "No sink nodes found for port demonstration"
fi

echo "### 3. Connection Viewing ###"
echo ""

# Show current connections in different formats
echo "--- Active connections (table format) ---"
$PW_INDEXED connect | head -20
echo "(showing first 20 connections)"
echo ""

echo "--- Active connections (canonical one-line format) ---"
$PW_INDEXED connect --oneline | head -10
echo "(showing first 10 connections)"
echo ""

echo "--- Connections matching pattern ---"
$PW_INDEXED connect "*jamesdsp*" 2>/dev/null || echo "No jamesdsp connections found"
echo ""

echo "### 4. Service Management ###"
echo ""

echo "--- Service status ---"
$PW_INDEXED service status
echo ""

# Note: We don't demonstrate pause/resume here as it affects the running system
echo "--- Service management commands (not executed) ---"
echo "# $PW_INDEXED pause qpwgraph      # Pause qpwgraph for operations"
echo "# $PW_INDEXED resume qpwgraph     # Resume qpwgraph"
echo ""

echo "### 5. Dry-Run Examples ###"
echo ""

echo "--- Export dry-run (safe preview) ---"
$PW_INDEXED export --dry-run /tmp/test_export.qpwgraph 2>/dev/null | head -10
echo "(showing first 10 lines of dry-run output)"
echo ""

echo "### 6. JSON Output ###"
echo ""

echo "--- Nodes in JSON format ---"
$PW_INDEXED nodes --json | head -20
echo "(showing first 20 lines of JSON)"
echo ""

echo "### 7. Help and Version ###"
echo ""

echo "--- Version information ---"
$PW_INDEXED --version
echo ""

echo "--- Help output (first 20 lines) ---"
$PW_INDEXED --help | head -20
echo ""

echo "=== Examples Complete ==="
echo ""
echo "TIP: Use --dry-run with any command that makes changes to preview the effects"
echo "TIP: Use --verbose for detailed logging during operations"
echo "TIP: Always pause qpwgraph before making bulk connection changes"
