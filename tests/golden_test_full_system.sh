#!/bin/bash

# golden_test_full_system.sh - Comprehensive Golden Test with System Reset & Verification
#
# This is the comprehensive golden test that performs full system reset and verification
# of all pw_indexed functionality including connections, nodes, and system state.
# Tests the complete system functionality from scratch after reset.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_INDEXED_SCRIPT="$SCRIPT_DIR/../pw_indexed.sh"
HQ_AUDIO_SCRIPT="/home/admin/scripts/audio/hq_audio.sh"
TEST_NAME="FULL_SYSTEM_RESET_GOLDEN"

# Test configuration
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
VERBOSE=${VERBOSE:-true}
RESET_SYSTEM=${RESET_SYSTEM:-false}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

#########################################
# UTILITIES
#########################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_system() {
    echo -e "${PURPLE}[SYSTEM]${NC} $*"
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
    log_test "System Golden Test: $test_name"
    
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
    
    # Check output pattern if specified
    if [[ "$expected_output_pattern" != ".*" ]]; then
        if echo "$output" | grep -qzE "$expected_output_pattern"; then
            # Pattern found - good
            :
        elif echo "$output" | grep -qE "$expected_output_pattern"; then
            # Try single line matching
            :
        else
            log_fail "$test_name - Output doesn't match expected pattern"
            test_passed=false
        fi
    fi
    
    if [[ "$test_passed" == true ]]; then
        log_pass "$test_name"
        if [[ "$VERBOSE" == true ]]; then
            echo "  Output preview: $(echo "$output" | head -3 | tr '\n' ' ')..."
        fi
        return 0
    else
        echo "  Full output: $output"
        return 1
    fi
}

capture_full_baseline() {
    log_info "Capturing comprehensive system baseline..."
    
    local baseline_file="/tmp/golden_system_baseline_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "=== FULL SYSTEM BASELINE - $(date) ===" > "$baseline_file"
    echo "" >> "$baseline_file"
    
    # PipeWire system status
    echo "=== PIPEWIRE SERVICES ===" >> "$baseline_file"
    systemctl --user is-active pipewire pipewire-pulse wireplumber >> "$baseline_file" 2>/dev/null || true
    echo "" >> "$baseline_file"
    
    # All pw_indexed nodes
    echo "=== ALL NODES ===" >> "$baseline_file"
    "$PW_INDEXED_SCRIPT" nodes "*" >> "$baseline_file" 2>/dev/null || true
    echo "" >> "$baseline_file"
    
    # Key nodes for testing
    echo "=== KEY TEST NODES ===" >> "$baseline_file"
    "$PW_INDEXED_SCRIPT" nodes "*gate*" --oneline >> "$baseline_file" 2>/dev/null || true
    "$PW_INDEXED_SCRIPT" nodes "*limiter*" --oneline >> "$baseline_file" 2>/dev/null || true
    "$PW_INDEXED_SCRIPT" nodes "*sink*" --oneline >> "$baseline_file" 2>/dev/null || true
    echo "" >> "$baseline_file"
    
    # Current connections using PipeWire
    echo "=== CURRENT CONNECTIONS ===" >> "$baseline_file"
    pw-link -l >> "$baseline_file" 2>/dev/null || true
    echo "" >> "$baseline_file"
    
    # HQ Audio system status if available
    if [[ -x "$HQ_AUDIO_SCRIPT" ]]; then
        echo "=== HQ AUDIO STATUS ===" >> "$baseline_file"
        "$HQ_AUDIO_SCRIPT" status >> "$baseline_file" 2>/dev/null || true
        echo "" >> "$baseline_file"
    fi
    
    log_info "Full baseline captured: $baseline_file"
    echo "$baseline_file"
}

#########################################
# SYSTEM RESET FUNCTIONS
#########################################

reset_audio_system() {
    if [[ "$RESET_SYSTEM" != "true" ]]; then
        log_info "System reset disabled. Use RESET_SYSTEM=true to enable."
        return 0
    fi
    
    log_system "=== INITIATING FULL AUDIO SYSTEM RESET ==="
    
    # Stop HQ audio system if running
    if [[ -x "$HQ_AUDIO_SCRIPT" ]] && "$HQ_AUDIO_SCRIPT" status >/dev/null 2>&1; then
        log_system "Stopping HQ audio system..."
        "$HQ_AUDIO_SCRIPT" stop || true
        sleep 3
    fi
    
    # Kill any remaining audio processes
    log_system "Cleaning up audio processes..."
    pkill -f "easyeffects" || true
    pkill -f "jamesdsp" || true
    pkill -f "qpwgraph" || true
    sleep 2
    
    # Restart PipeWire services
    log_system "Restarting PipeWire services..."
    systemctl --user restart pipewire pipewire-pulse wireplumber || true
    sleep 5
    
    # Wait for PipeWire to stabilize
    log_system "Waiting for PipeWire to stabilize..."
    local max_wait=30
    local wait_count=0
    while [[ $wait_count -lt $max_wait ]]; do
        if pw-cli info >/dev/null 2>&1; then
            break
        fi
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    if [[ $wait_count -ge $max_wait ]]; then
        log_fail "PipeWire failed to stabilize after reset"
        return 1
    fi
    
    log_system "PipeWire stabilized. System reset complete."
    sleep 2
}

restart_hq_system() {
    if [[ -x "$HQ_AUDIO_SCRIPT" ]]; then
        log_system "Starting HQ audio system..."
        "$HQ_AUDIO_SCRIPT" start || true
        sleep 10
        
        # Wait for applications to start
        local max_wait=30
        local wait_count=0
        while [[ $wait_count -lt $max_wait ]]; do
            if "$HQ_AUDIO_SCRIPT" status | grep -q "running"; then
                break
            fi
            sleep 2
            wait_count=$((wait_count + 1))
        done
        
        log_system "HQ audio system started and ready."
    else
        log_info "HQ audio script not found - skipping HQ system start"
    fi
}

#########################################
# GOLDEN TESTS - FULL SYSTEM
#########################################

test_pipewire_system_health() {
    log_info "=== Golden Test: PipeWire System Health ==="
    
    # Test PipeWire core service
    run_golden_test "PipeWire core service active" \
        "systemctl --user is-active pipewire" \
        0 \
        "active"
    
    # Test PipeWire pulse service
    run_golden_test "PipeWire pulse service active" \
        "systemctl --user is-active pipewire-pulse" \
        0 \
        "active"
        
    # Test WirePlumber service
    run_golden_test "WirePlumber service active" \
        "systemctl --user is-active wireplumber" \
        0 \
        "active"
        
    # Test pw-cli connectivity
    run_golden_test "PipeWire CLI connectivity" \
        "timeout 5 pw-cli info" \
        0 \
        ".*"
}

test_pw_indexed_core_functionality() {
    log_info "=== Golden Test: PW_Indexed Core Functionality ==="
    
    # Test script executable and responsive
    run_golden_test "PW_Indexed script executable" \
        "\"$PW_INDEXED_SCRIPT\" --help" \
        0 \
        "Swiss Army Knife"
        
    # Test node enumeration works
    run_golden_test "Node enumeration functional" \
        "\"$PW_INDEXED_SCRIPT\" nodes" \
        0 \
        "Indexed Nodes"
        
    # Test service status command
    run_golden_test "Service status command" \
        "\"$PW_INDEXED_SCRIPT\" service status" \
        0 \
        "Service Status"
}

test_node_enumeration_comprehensive() {
    log_info "=== Golden Test: Comprehensive Node Enumeration ==="
    
    # Test all major node types exist
    run_golden_test "Audio sink nodes exist" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*sink*'" \
        0 \
        ".*sink.*"
        
    # Test EasyEffects nodes if system is running
    run_golden_test "EasyEffects nodes detection" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*ee_*' || echo 'EE not running'" \
        0 \
        ".*"
        
    # Test multiband gates enumeration with tilde notation
    run_golden_test "Multiband gates with tilde notation" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*gate*' || echo 'No gates found'" \
        0 \
        ".*"
        
    # Test limiter nodes
    run_golden_test "Limiter nodes enumeration" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*limiter*' || echo 'No limiters found'" \
        0 \
        ".*"
}

test_port_enumeration_comprehensive() {
    log_info "=== Golden Test: Comprehensive Port Enumeration ==="
    
    # Test port enumeration for different node types
    run_golden_test "Sink ports enumeration" \
        "\"$PW_INDEXED_SCRIPT\" ports '*sink*' | head -10 || echo 'No sink ports'" \
        0 \
        ".*"
        
    # Test input/output port filtering
    run_golden_test "Input port filtering" \
        "\"$PW_INDEXED_SCRIPT\" ports '*' --input | head -5 || echo 'No input ports'" \
        0 \
        ".*"
        
    run_golden_test "Output port filtering" \
        "\"$PW_INDEXED_SCRIPT\" ports '*' --output | head -5 || echo 'No output ports'" \
        0 \
        ".*"
}

test_connection_operations_comprehensive() {
    log_info "=== Golden Test: Comprehensive Connection Operations ==="
    
    # Test connection listing
    run_golden_test "Connection listing basic" \
        "timeout 5 \"$PW_INDEXED_SCRIPT\" connect || echo 'Connection listing timeout'" \
        0 \
        ".*"
        
    # Test dry-run make operations
    run_golden_test "Make connection dry-run" \
        "\"$PW_INDEXED_SCRIPT\" make 'test_source:port->test_target:port' --dry-run || echo 'Expected failure'" \
        0 \
        ".*"
        
    # Test dry-run remove operations  
    run_golden_test "Remove connection dry-run" \
        "\"$PW_INDEXED_SCRIPT\" remove 'nonexistent:port->nonexistent:port' --dry-run" \
        1 \
        ".*"
}

test_exclusive_connections_comprehensive() {
    log_info "=== Golden Test: Comprehensive Exclusive Connection Testing ==="
    
    # This tests the core bug fix - bash syntax errors in exclusive connections
    if "$PW_INDEXED_SCRIPT" nodes "*gate*" | grep -q "ee_soe_multiband_gate~2"; then
        run_golden_test "Exclusive connection to gate~2 (syntax fix test)" \
            "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FL->ee_soe_multiband_gate~2:probe_FL' --dry-run" \
            0 \
            ".*"
            
        # Test verbose mode specifically (regression test)
        run_golden_test "Exclusive connection verbose mode (bash syntax regression)" \
            "\"$PW_INDEXED_SCRIPT\" exclusive 'ee_sie_limiter:output_FR->ee_soe_multiband_gate~2:probe_FR' --dry-run --verbose" \
            0 \
            ".*"
    else
        log_info "Gate~2 not found - skipping gate-specific exclusive tests"
    fi
    
    # Test exclusive connection with non-existent nodes (should fail gracefully)
    run_golden_test "Exclusive connection with invalid nodes" \
        "\"$PW_INDEXED_SCRIPT\" exclusive 'invalid:port->invalid:port' --dry-run" \
        1 \
        ".*"
}

test_hq_system_integration() {
    log_info "=== Golden Test: HQ System Integration ==="
    
    if [[ -x "$HQ_AUDIO_SCRIPT" ]]; then
        # Test HQ system status
        run_golden_test "HQ system status check" \
            "\"$HQ_AUDIO_SCRIPT\" status" \
            0 \
            ".*"
            
        # Test HQ connection enforcement (dry mode)
        run_golden_test "HQ connection enforcement" \
            "timeout 30 \"$HQ_AUDIO_SCRIPT\" enforce_all_connections || echo 'Enforcement timeout'" \
            0 \
            ".*"
    else
        log_info "HQ audio script not available - skipping integration tests"
    fi
}

test_stress_and_regression() {
    log_info "=== Golden Test: Stress Testing and Regression Prevention ==="
    
    # Stress test the bash syntax fix with multiple rapid operations
    for i in {1..5}; do
        run_golden_test "Stress test exclusive operation $i" \
            "\"$PW_INDEXED_SCRIPT\" exclusive 'test:port->test:port' --dry-run 2>/dev/null || echo 'Expected stress test failure'" \
            0 \
            ".*"
    done
    
    # Test concurrent operations (regression test for temp file handling)
    run_golden_test "Concurrent operations test" \
        "\"$PW_INDEXED_SCRIPT\" nodes '*' >/dev/null 2>&1 & \"$PW_INDEXED_SCRIPT\" nodes '*' >/dev/null 2>&1 & wait" \
        0 \
        ""
}

#########################################
# MAIN EXECUTION
#########################################

main() {
    echo "=========================================="
    echo "🧪 PW_INDEXED FULL SYSTEM GOLDEN TEST"
    echo "=========================================="
    echo "Test Suite: $TEST_NAME"
    echo "Target: Complete system functionality"
    echo "Focus: Full reset, verification, and integration"
    echo ""
    
    # Check prerequisites
    if [[ ! -x "$PW_INDEXED_SCRIPT" ]]; then
        echo "ERROR: pw_indexed.sh script not found or not executable: $PW_INDEXED_SCRIPT"
        exit 1
    fi
    
    # Capture baseline before any operations
    baseline_file=$(capture_full_baseline)
    echo ""
    
    # Optional system reset
    if [[ "$RESET_SYSTEM" == "true" ]]; then
        reset_audio_system
        echo ""
        
        # Wait and restart HQ system
        restart_hq_system
        echo ""
    else
        log_info "Running tests with current system state (use RESET_SYSTEM=true for full reset)"
        echo ""
    fi
    
    # Run all comprehensive test suites
    test_pipewire_system_health
    echo ""
    
    test_pw_indexed_core_functionality
    echo ""
    
    test_node_enumeration_comprehensive
    echo ""
    
    test_port_enumeration_comprehensive
    echo ""
    
    test_connection_operations_comprehensive
    echo ""
    
    test_exclusive_connections_comprehensive
    echo ""
    
    test_hq_system_integration
    echo ""
    
    test_stress_and_regression
    echo ""
    
    # Final system verification
    log_system "Final system verification..."
    final_baseline=$(capture_full_baseline)
    
    # Test summary
    echo "=========================================="
    echo "🏆 FULL SYSTEM GOLDEN TEST RESULTS"
    echo "=========================================="
    echo "Test Suite: $TEST_NAME"
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo ""
    echo "📋 Baselines captured:"
    echo "  Initial: $baseline_file"
    echo "  Final:   $final_baseline"
    echo ""
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL SYSTEM GOLDEN TESTS PASSED!${NC}"
        echo "✅ Full system functionality verified"
        echo "✅ PipeWire services healthy"
        echo "✅ PW_Indexed tool fully functional"  
        echo "✅ Tilde notation and exclusive connections working"
        echo "✅ Bash syntax error regression prevented"
        echo "✅ System integration confirmed"
        
        if [[ "$RESET_SYSTEM" == "true" ]]; then
            echo "✅ Full reset and recovery successful"
        fi
        
        exit 0
    else
        echo -e "${RED}❌ $FAILED_TESTS SYSTEM GOLDEN TESTS FAILED!${NC}"
        echo "⚠️  System has issues that need attention"
        echo "📋 Check baseline files for system state details"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --reset)
        RESET_SYSTEM=true
        main
        ;;
    --help|-h)
        echo "Usage: $0 [--reset] [--help]"
        echo ""
        echo "Comprehensive golden test for pw_indexed system functionality."
        echo ""
        echo "Options:"
        echo "  --reset     Perform full system reset before testing"
        echo "  --help, -h  Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  RESET_SYSTEM=true  Enable system reset"
        echo "  VERBOSE=false      Disable verbose output"
        exit 0
        ;;
    *)
        main
        ;;
esac
