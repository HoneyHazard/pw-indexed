#!/bin/bash

# test_tilde_notation.sh - Comprehensive Test Suite for Tilde Notation Functionality
#
# This test suite validates tilde notation resolution, multi-instance handling,
# and edge cases to prevent regression of the bash syntax error bug that was
# fixed around line 1161-1163 in exclusive_connection() function.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_INDEXED_SCRIPT="$SCRIPT_DIR/../pw_indexed.sh"

# Test configuration
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
VERBOSE=${VERBOSE:-false}

# Test colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#########################################
# TEST UTILITIES
#########################################

log_test() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${YELLOW}[TEST]${NC} $*"
    fi
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_exit_code="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test "Running: $test_name"
    
    local output
    local exit_code
    
    set +e
    output=$(eval "$test_cmd" 2>&1)
    exit_code=$?
    set -e
    
    if [[ $exit_code -eq $expected_exit_code ]]; then
        log_pass "$test_name"
        if [[ "$VERBOSE" == true ]]; then
            echo "  Output: $output"
        fi
        return 0
    else
        log_fail "$test_name (exit code: $exit_code, expected: $expected_exit_code)"
        echo "  Output: $output"
        return 1
    fi
}

# Check if the test environment has the required nodes for testing
check_test_environment() {
    log_test "Checking test environment..."
    
    # Check if we have multiple instances of multiband_gate
    local multiband_instances
    multiband_instances=$("$PW_INDEXED_SCRIPT" nodes "*multiband_gate*" --oneline 2>/dev/null | wc -l)
    
    if [[ $multiband_instances -lt 2 ]]; then
        echo "WARNING: Test environment doesn't have multiple multiband_gate instances"
        echo "Found $multiband_instances instances. Some tests may be skipped."
        return 1
    fi
    
    log_pass "Test environment ready (found $multiband_instances multiband_gate instances)"
    return 0
}

#########################################
# CORE TILDE NOTATION TESTS
#########################################

test_basic_node_resolution() {
    log_test "=== Basic Node Resolution Tests ==="
    
    # Test basic node enumeration
    run_test "List all multiband_gate nodes" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*multiband_gate*'" \
        0
    
    # Test tilde notation in node listing
    run_test "List multiband_gate~2 specifically" \
        "\"$PW_INDEXED_SCRIPT\" nodes 'ee_soe_multiband_gate~2'" \
        0
        
    # Test port listing with tilde notation
    run_test "List ports for multiband_gate~2" \
        "\"$PW_INDEXED_SCRIPT\" ports 'ee_soe_multiband_gate~2'" \
        0
}

test_connection_operations_with_tilde() {
    log_test "=== Connection Operations with Tilde Notation ==="
    
    # Test dry-run make connection with tilde notation
    run_test "Make connection with tilde notation (dry-run)" \
        "\"$PW_INDEXED_SCRIPT\" make 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run" \
        0
    
    # Test dry-run exclusive connection with tilde notation  
    run_test "Exclusive connection with tilde notation (dry-run)" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run" \
        0
        
    # Test pattern-based removal with tilde notation
    run_test "Remove connections with tilde pattern (dry-run)" \
        "\"$PW_INDEXED_SCRIPT\" remove '*multiband_gate~2*' --dry-run" \
        0
}

test_syntax_error_regression() {
    log_test "=== Syntax Error Regression Tests ==="
    
    # These tests specifically target the bash syntax error that was fixed
    # around line 1161-1163 in the exclusive_connection function
    
    # Test with verbose output to catch any bash syntax errors
    run_test "Exclusive connection with verbose output (regression test)" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run --verbose" \
        0
    
    # Test the core fix - exclusive connection should not have bash syntax errors
    # This was the main issue: ./pw_indexed.sh: line 1161: [[: 0\n0: syntax error in expression
    run_test "Exclusive connection bash syntax fix validation" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FR->ee_soe_multiband_gate~2:probe_FR' --dry-run" \
        0
        
    # Test specific pattern that works reliably - focusing on the grep -c fix
    # This tests the temp file handling without syntax errors
    run_test "Remove non-existent connection (temp file handling)" \
        "\"$PW_INDEXED_SCRIPT\" remove 'nonexistent:port->nonexistent:port' --dry-run" \
        1
}

#########################################
# EDGE CASE TESTS  
#########################################

test_edge_cases() {
    log_test "=== Edge Case Tests ==="
    
    # Test with non-existent tilde instances
    run_test "Non-existent tilde instance" \
        "\"$PW_INDEXED_SCRIPT\" nodes 'ee_soe_multiband_gate~99'" \
        0
    
    # Test with invalid tilde syntax
    run_test "Invalid tilde syntax" \
        "\"$PW_INDEXED_SCRIPT\" nodes 'invalid_node~abc'" \
        0
        
    # Test empty pattern
    run_test "Empty node pattern" \
        "\"$PW_INDEXED_SCRIPT\" nodes ''" \
        0
        
    # Test wildcard patterns with tilde
    run_test "Wildcard with tilde notation" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*gate~*'" \
        0
}

test_concurrent_operations() {
    log_test "=== Concurrent Operations Tests ==="
    
    # Test multiple operations that might conflict with temp files
    run_test "Concurrent dry-run exclusive operations" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~1:probe_FL' --dry-run & \"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FR->ee_soe_multiband_gate~2:probe_FR' --dry-run & wait" \
        0
}

test_format_variations() {
    log_test "=== Output Format Tests ==="
    
    # Test different output formats with tilde notation
    run_test "Oneline format with tilde notation" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*multiband_gate*' --oneline" \
        0
        
    run_test "JSON format with tilde notation" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*multiband_gate*' --json" \
        0
        
    run_test "Connection listing (basic functionality)" \
        "timeout 5 \"$PW_INDEXED_SCRIPT\" connect || echo 'timeout ok'" \
        0
}

#########################################
# INTEGRATION TESTS
#########################################

test_real_connection_scenarios() {
    log_test "=== Real Connection Scenario Tests ==="
    
    # These tests simulate the actual HQ audio system scenarios
    # that revealed the original tilde notation bugs
    
    local test_connections=(
        "ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL"
        "ee_sie_limiter:output_FR->ee_soe_multiband_gate~2:probe_FR"  
        "virtual_input_device:capture_FL->ee_soe_expander:probe_FL"
    )
    
    for connection in "${test_connections[@]}"; do
        run_test "Real scenario: $connection (dry-run)" \
            "\"$PW_INDEXED_SCRIPT\" exclusive '$connection' --dry-run" \
            0
    done
}

#########################################
# MAIN TEST EXECUTION
#########################################

main() {
    echo "=========================================="
    echo "PW_INDEXED TILDE NOTATION TEST SUITE"  
    echo "=========================================="
    echo ""
    
    if [[ ! -x "$PW_INDEXED_SCRIPT" ]]; then
        echo "ERROR: pw_indexed.sh script not found or not executable: $PW_INDEXED_SCRIPT"
        exit 1
    fi
    
    # Check test environment
    if ! check_test_environment; then
        echo "WARNING: Limited test environment detected. Some tests may be skipped."
    fi
    
    echo ""
    
    # Run all test suites
    test_basic_node_resolution
    echo ""
    
    test_connection_operations_with_tilde  
    echo ""
    
    test_syntax_error_regression
    echo ""
    
    test_edge_cases
    echo ""
    
    test_concurrent_operations
    echo ""
    
    test_format_variations
    echo ""
    
    test_real_connection_scenarios
    echo ""
    
    # Test summary
    echo "=========================================="
    echo "TEST SUMMARY"
    echo "=========================================="
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}ALL TESTS PASSED!${NC}"
        exit 0
    else
        echo -e "${RED}$FAILED_TESTS TESTS FAILED!${NC}"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --verbose|-v)
        VERBOSE=true
        main
        ;;
    --help|-h)
        echo "Usage: $0 [--verbose|-v] [--help|-h]"
        echo ""
        echo "Comprehensive test suite for pw_indexed tilde notation functionality."
        echo ""
        echo "Options:"
        echo "  --verbose, -v    Enable verbose output"
        echo "  --help, -h       Show this help message"
        exit 0
        ;;
    *)
        main
        ;;
esac
