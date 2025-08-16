#!/bin/bash

# golden_test_gates_limiter.sh - Golden Test for Gates and SOE Limiter Connections
#
# This test focuses specifically on multiband gates and SOE limiter connections
# using pw_indexed tool with emphasis on tilde notation and exclusive connections.
# This is a "golden test" that verifies the exact expected behavior after fixes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_INDEXED_SCRIPT="$SCRIPT_DIR/../pw_indexed.sh"
TEST_NAME="GATES_LIMITER_GOLDEN"

# Test configuration
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
VERBOSE=${VERBOSE:-true}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#########################################
# UTILITIES
#########################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

run_golden_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_exit_code="${3:-0}"
    local expected_output_pattern="${4:-.*}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test "Golden Test: $test_name"
    
    local output
    local exit_code
    
    set +e
    output=$(eval "$test_cmd" 2>&1)
    exit_code=$?
    set -e
    
    local test_passed=true
    
    # Check exit code
    if [[ $exit_code -ne $expected_exit_code ]]; then
        log_fail "$test_name - Wrong exit code: $exit_code (expected: $expected_exit_code)"
        test_passed=false
    fi
    
    # Check output pattern if specified (using grep -qzE for multiline)
    if [[ "$expected_output_pattern" != ".*" ]] && ! echo "$output" | grep -qzE "$expected_output_pattern"; then
        log_fail "$test_name - Output doesn't match expected pattern"
        test_passed=false
    fi
    
    if [[ "$test_passed" == true ]]; then
        log_pass "$test_name"
        if [[ "$VERBOSE" == true ]]; then
            echo "  Output: $output"
        fi
        return 0
    else
        echo "  Output: $output"
        return 1
    fi
}

capture_baseline() {
    log_info "Capturing baseline state for gates and limiters..."
    
    # Capture current node enumeration
    echo "=== BASELINE NODES ===" > /tmp/golden_baseline.txt
    echo "Gates:" >> /tmp/golden_baseline.txt
    "$PW_INDEXED_SCRIPT" nodes "*gate*" --oneline >> /tmp/golden_baseline.txt 2>/dev/null || true
    echo "" >> /tmp/golden_baseline.txt
    echo "Limiters:" >> /tmp/golden_baseline.txt
    "$PW_INDEXED_SCRIPT" nodes "*limiter*" --oneline >> /tmp/golden_baseline.txt 2>/dev/null || true
    echo "" >> /tmp/golden_baseline.txt
    
    # Capture current connections using pw-link
    echo "=== BASELINE CONNECTIONS ===" >> /tmp/golden_baseline.txt
    pw-link -l | grep -E "(gate|limiter)" >> /tmp/golden_baseline.txt 2>/dev/null || true
    
    log_info "Baseline captured to /tmp/golden_baseline.txt"
}

#########################################
# GOLDEN TESTS - GATES AND LIMITERS
#########################################

test_node_enumeration_golden() {
    log_info "=== Golden Test: Node Enumeration ==="
    
    # Test that we have expected gates with tilde notation
    run_golden_test "Gates enumeration with tilde notation" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*gate*'" \
        0 \
        "ee_soe_multiband_gate.*273.*154.*312"
    
    # Test that we have expected limiters
    run_golden_test "Limiters enumeration" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*limiter*'" \
        0 \
        "ee_sie_limiter.*ee_soe_limiter"
        
    # Test specific tilde resolution
    run_golden_test "Specific gate~2 resolution" \
        "\"$PW_INDEXED_SCRIPT\" nodes 'ee_soe_multiband_gate~2'" \
        0 \
        "ee_soe_multiband_gate~2"
}

test_port_enumeration_golden() {
    log_info "=== Golden Test: Port Enumeration ==="
    
    # Test ports for specific gate instances
    run_golden_test "Gate~2 ports enumeration" \
        "\"$PW_INDEXED_SCRIPT\" ports 'ee_soe_multiband_gate~2'" \
        0 \
        "probe_FL.*probe_FR"
        
    # Test limiter ports
    run_golden_test "SOE Limiter ports enumeration" \
        "\"$PW_INDEXED_SCRIPT\" ports 'ee_soe_limiter'" \
        0 \
        "probe_FL.*probe_FR"
}

test_exclusive_connections_golden() {
    log_info "=== Golden Test: Exclusive Connections ==="
    
    # This is the core functionality we fixed - test bash syntax error prevention
    run_golden_test "Exclusive connection to gate~2 (no syntax errors)" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run" \
        0 \
        "Removing conflicting connections"
        
    # Test the other channel
    run_golden_test "Exclusive connection to gate~2 FR channel" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FR->ee_soe_multiband_gate~2:probe_FR' --dry-run" \
        0 \
        "Removing conflicting connections.*connection"
        
    # Test connection to different gate instance
    run_golden_test "Exclusive connection to gate~1" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~1:probe_FL' --dry-run" \
        0 \
        ".*connection"
        
    # Test verbose mode (regression test for bash syntax errors)
    run_golden_test "Exclusive connection with verbose (regression test)" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run --verbose" \
        0 \
        ".*connection"
}

test_make_connections_golden() {
    log_info "=== Golden Test: Make Connections ==="
    
    # Test make connections with tilde notation
    run_golden_test "Make connection to gate~2" \
        "\"$PW_INDEXED_SCRIPT\" make 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run" \
        0 \
        "Would create connection.*gate.*probe_FL"
        
    # Test connection to SOE limiter
    run_golden_test "Make connection to SOE limiter" \
        "\"$PW_INDEXED_SCRIPT\" make 'ee_sie_limiter:output_FL->ee_soe_limiter:probe_FL' --dry-run" \
        0 \
        "Would create connection.*limiter.*probe_FL"
}

test_remove_connections_golden() {
    log_info "=== Golden Test: Remove Connections ==="
    
    # Test remove specific connections
    run_golden_test "Remove specific gate connection" \
        "\"$PW_INDEXED_SCRIPT\" remove 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run" \
        1 \
        "Connection not found"
        
    # Test pattern-based removal (using a safe pattern)
    run_golden_test "Remove pattern connections to gate~2" \
        "\"$PW_INDEXED_SCRIPT\" remove '*gate~2*' --dry-run" \
        0 \
        ".*removed.*connection"
}

test_tilde_notation_edge_cases() {
    log_info "=== Golden Test: Tilde Notation Edge Cases ==="
    
    # Test non-existent instances
    run_golden_test "Non-existent gate~99" \
        "\"$PW_INDEXED_SCRIPT\" nodes 'ee_soe_multiband_gate~99'" \
        0 \
        "^$"
        
    # Test invalid tilde syntax  
    run_golden_test "Invalid tilde syntax" \
        "\"$PW_INDEXED_SCRIPT\" nodes 'invalid_node~abc'" \
        0 \
        "^$"
        
    # Test edge case with highest valid instance
    run_golden_test "Highest gate instance (gate~2)" \
        "\"$PW_INDEXED_SCRIPT\" nodes 'ee_soe_multiband_gate~2'" \
        0 \
        "ee_soe_multiband_gate~2"
}

#########################################
# REGRESSION TESTS - BASH SYNTAX ERRORS
#########################################

test_bash_syntax_regression() {
    log_info "=== Golden Test: Bash Syntax Error Regression ==="
    
    # This specifically tests the fix for lines 1161-1163 bash syntax errors
    log_test "Testing bash syntax error prevention in exclusive operations"
    
    # Run multiple exclusive operations to stress-test the grep -c newline handling
    for i in {1..3}; do
        run_golden_test "Bash syntax stress test $i" \
            "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run" \
            0 \
            ".*connection"
    done
}

#########################################
# MAIN EXECUTION
#########################################

main() {
    echo "=========================================="
    echo "🧪 PW_INDEXED GOLDEN TEST - GATES & LIMITERS"
    echo "=========================================="
    echo "Test Suite: $TEST_NAME"
    echo "Target: Gates and SOE Limiter connections"
    echo "Focus: Tilde notation and exclusive connections"
    echo ""
    
    if [[ ! -x "$PW_INDEXED_SCRIPT" ]]; then
        echo "ERROR: pw_indexed.sh script not found or not executable: $PW_INDEXED_SCRIPT"
        exit 1
    fi
    
    # Capture baseline for reference
    capture_baseline
    echo ""
    
    # Run all golden test suites
    test_node_enumeration_golden
    echo ""
    
    test_port_enumeration_golden
    echo ""
    
    test_exclusive_connections_golden
    echo ""
    
    test_make_connections_golden
    echo ""
    
    test_remove_connections_golden
    echo ""
    
    test_tilde_notation_edge_cases
    echo ""
    
    test_bash_syntax_regression
    echo ""
    
    # Test summary
    echo "=========================================="
    echo "🏆 GOLDEN TEST RESULTS - $TEST_NAME"
    echo "=========================================="
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo ""
    
    if [[ -f /tmp/golden_baseline.txt ]]; then
        echo "📋 Baseline captured in: /tmp/golden_baseline.txt"
    fi
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL GOLDEN TESTS PASSED!${NC}"
        echo "✅ Gates and limiter connections working perfectly"
        echo "✅ Tilde notation resolution verified"
        echo "✅ Exclusive connection functionality confirmed"
        echo "✅ Bash syntax error regression prevented"
        exit 0
    else
        echo -e "${RED}❌ $FAILED_TESTS GOLDEN TESTS FAILED!${NC}"
        echo "⚠️  System may have regressions or issues"
        exit 1
    fi
}

# Run main function
main "$@"
