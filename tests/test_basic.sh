#!/bin/bash

# test_basic.sh - Basic functionality tests for pw_indexed
# 
# Tests the core functionality that should work before any integration

set -eo pipefail  # Removed -u for compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_INDEXED="$SCRIPT_DIR/../pw_indexed.sh"
TEST_PASSED=0
TEST_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TEST_PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TEST_FAILED++))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

test_help() {
    log "Testing help functionality..."
    
    if "$PW_INDEXED" --help >/dev/null 2>&1; then
        pass "Help command works"
    else
        fail "Help command failed"
    fi
    
    if "$PW_INDEXED" --version >/dev/null 2>&1; then
        pass "Version command works"
    else
        fail "Version command failed"
    fi
}

test_dependencies() {
    log "Testing dependencies..."
    
    # Check required commands
    local deps=("pw-dump" "jq" "systemctl")
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            pass "Dependency '$dep' found"
        else
            fail "Dependency '$dep' missing"
        fi
    done
    
    # Test pw-dump works
    if pw-dump >/dev/null 2>&1; then
        pass "pw-dump produces output"
    else
        fail "pw-dump not working or no PipeWire"
    fi
}

test_service_status() {
    log "Testing service status..."
    
    if "$PW_INDEXED" service status >/dev/null 2>&1; then
        pass "Service status command works"
    else
        fail "Service status command failed"
    fi
}

test_node_listing() {
    log "Testing node listing..."
    
    # Test basic nodes command
    if "$PW_INDEXED" nodes >/dev/null 2>&1; then
        pass "Basic nodes command works"
    else
        fail "Basic nodes command failed"
        return 1
    fi
    
    # Test nodes with verbose
    if "$PW_INDEXED" nodes --verbose >/dev/null 2>&1; then
        pass "Nodes with verbose works"
    else
        fail "Nodes with verbose failed"
    fi
    
    # Test different output formats
    if "$PW_INDEXED" nodes --oneline >/dev/null 2>&1; then
        pass "Nodes oneline format works"
    else
        fail "Nodes oneline format failed"
    fi
    
    if "$PW_INDEXED" nodes --json >/dev/null 2>&1; then
        pass "Nodes JSON format works"  
    else
        fail "Nodes JSON format failed"
    fi
    
    # Test pattern matching
    if "$PW_INDEXED" nodes "Dummy*" >/dev/null 2>&1; then
        pass "Node pattern matching works"
    else
        fail "Node pattern matching failed"
    fi
}

test_port_listing() {
    log "Testing port listing..."
    
    # Test basic ports command
    if "$PW_INDEXED" ports >/dev/null 2>&1; then
        pass "Basic ports command works"
    else
        fail "Basic ports command failed"
        return 1
    fi
    
    # Test port filters
    if "$PW_INDEXED" ports --input >/dev/null 2>&1; then
        pass "Port input filter works"
    else
        fail "Port input filter failed"
    fi
    
    if "$PW_INDEXED" ports --output >/dev/null 2>&1; then
        pass "Port output filter works"
    else
        fail "Port output filter failed"
    fi
}

test_enumeration_accuracy() {
    log "Testing enumeration accuracy..."
    
    # Get node list and check for consistent enumeration
    local nodes_output
    if nodes_output=$("$PW_INDEXED" nodes 2>/dev/null); then
        if [[ -n "$nodes_output" ]]; then
            pass "Node enumeration produces output"
            
            # Check for indexed nodes (ones with ~)
            if echo "$nodes_output" | grep -q "~[0-9]"; then
                pass "Found indexed nodes (multiple instances detected)"
            else
                warn "No indexed nodes found (normal if no duplicate node names)"
            fi
        else
            warn "Node enumeration produced empty output"
        fi
    else
        fail "Node enumeration failed completely"
    fi
}

test_cache_functionality() {
    log "Testing cache functionality..."
    
    # Clear any existing cache
    rm -rf /tmp/pw_indexed/ 2>/dev/null || true
    
    # First run should create cache
    local start_time=$(date +%s%3N)
    "$PW_INDEXED" nodes >/dev/null 2>&1
    local first_run=$(($(date +%s%3N) - start_time))
    
    # Second run should use cache (be faster)
    start_time=$(date +%s%3N)
    "$PW_INDEXED" nodes >/dev/null 2>&1
    local second_run=$(($(date +%s%3N) - start_time))
    
    if [[ -f "/tmp/pw_indexed/pipewire_dump" ]]; then
        pass "Cache file created"
    else
        fail "Cache file not created"
    fi
    
    if [[ $second_run -lt $first_run ]]; then
        pass "Second run was faster (cache working)"
    else
        warn "Second run not faster (cache may not be working optimally)"
    fi
}

test_error_handling() {
    log "Testing error handling..."
    
    # Test invalid command
    if ! "$PW_INDEXED" invalid_command >/dev/null 2>&1; then
        pass "Invalid command properly rejected"
    else
        fail "Invalid command not rejected"
    fi
    
    # Test invalid option
    if ! "$PW_INDEXED" nodes --invalid-option >/dev/null 2>&1; then
        pass "Invalid option properly rejected"
    else
        fail "Invalid option not rejected"
    fi
}

run_all_tests() {
    echo "=== pw_indexed Basic Functionality Tests ==="
    echo "Testing: $PW_INDEXED"
    echo ""
    
    test_help
    test_dependencies
    test_service_status
    test_node_listing
    test_port_listing
    test_enumeration_accuracy
    test_cache_functionality
    test_error_handling
    
    echo ""
    echo "=== Test Results ==="
    echo -e "${GREEN}Passed: $TEST_PASSED${NC}"
    echo -e "${RED}Failed: $TEST_FAILED${NC}"
    
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All basic tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Review output above.${NC}"
        exit 1
    fi
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
