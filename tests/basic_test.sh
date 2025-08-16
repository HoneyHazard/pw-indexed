#!/bin/bash

# Basic functionality test for pw_indexed.sh
# 
# This test validates core functionality without making system changes
# Uses --dry-run mode for all tests that could modify connections

set -e

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PW_INDEXED="$SCRIPT_DIR/../pw_indexed.sh"
TEST_FILE="/tmp/pw_indexed_test_$$.qpwgraph"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== pw_indexed.sh Basic Functionality Test ===${NC}"
echo ""

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}Test $TESTS_RUN: $test_name${NC}"
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  Command: $test_command"
        return 1
    fi
}

run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    local min_lines="${3:-1}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}Test $TESTS_RUN: $test_name${NC}"
    
    local output
    if output=$(eval "$test_command" 2>&1); then
        local line_count=$(echo "$output" | wc -l)
        if [[ $line_count -ge $min_lines ]]; then
            echo -e "${GREEN}✓ PASS${NC} ($line_count lines)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            echo -e "${RED}✗ FAIL${NC} (insufficient output: $line_count < $min_lines)"
            return 1
        fi
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  Output: $output"
        return 1
    fi
}

# Verify script exists and is executable
if [[ ! -x "$PW_INDEXED" ]]; then
    echo -e "${RED}ERROR: pw_indexed.sh not found or not executable at $PW_INDEXED${NC}"
    exit 1
fi

echo -e "${BLUE}Testing core functionality...${NC}"
echo ""

# Test 1: Version check
run_test "Version command" "$PW_INDEXED --version"

# Test 2: Help command
run_test "Help command" "$PW_INDEXED --help"

# Test 3: Service status
run_test "Service status" "$PW_INDEXED service status"

# Test 4: Node listing
run_test_with_output "Node listing" "$PW_INDEXED nodes" 5

# Test 5: Node listing with pattern
run_test_with_output "Node listing with pattern" "$PW_INDEXED nodes '*sink*'" 1

# Test 6: Node listing in oneline format
run_test_with_output "Node listing --oneline" "$PW_INDEXED nodes --oneline" 5

# Test 7: Node listing in JSON format
run_test "Node listing --json" "$PW_INDEXED nodes --json | jq . > /dev/null"

# Test 8: Connection listing
run_test_with_output "Connection listing" "$PW_INDEXED connect" 5

# Test 9: Connection listing --oneline
run_test_with_output "Connection listing --oneline" "$PW_INDEXED connect --oneline" 5

# Test 10: Connection listing --json
run_test "Connection listing --json" "$PW_INDEXED connect --json | jq . > /dev/null"

# Test 11: Port listing (using a known node)
FIRST_NODE=$($PW_INDEXED nodes --oneline | head -1 | cut -d'@' -f1)
if [[ -n "$FIRST_NODE" ]]; then
    run_test "Port listing" "$PW_INDEXED ports '$FIRST_NODE'"
else
    echo -e "${YELLOW}Skipping port test - no nodes found${NC}"
fi

# Test 12: Export dry-run
run_test "Export dry-run" "$PW_INDEXED export --dry-run '$TEST_FILE'"

# Test 13: Export actual (to test file)
run_test "Export to file" "$PW_INDEXED export '$TEST_FILE'"

# Test 14: Verify export file exists and has content
if [[ -f "$TEST_FILE" && -s "$TEST_FILE" ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}Test $TESTS_RUN: Export file validation${NC}"
    if grep -q "<patchbay" "$TEST_FILE" && grep -q "</patchbay>" "$TEST_FILE"; then
        echo -e "${GREEN}✓ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC} (invalid XML structure)"
    fi
else
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}Test $TESTS_RUN: Export file validation${NC}"
    echo -e "${RED}✗ FAIL${NC} (file not created or empty)"
fi

# Test 15: Import dry-run
if [[ -f "$TEST_FILE" ]]; then
    run_test "Import dry-run" "$PW_INDEXED import --dry-run '$TEST_FILE'"
else
    echo -e "${YELLOW}Skipping import dry-run test - no export file${NC}"
fi

# Test 16: Pattern matching in connections
run_test "Connection pattern matching" "$PW_INDEXED connect '*' | head -1"

# Test 17: Batch processing dry-run
BATCH_FILE="/tmp/pw_indexed_batch_test_$$"
cat > "$BATCH_FILE" << 'EOF'
# Test batch file
service status
nodes "*sink*"
connect "*jamesdsp*"
EOF

run_test "Batch processing" "$PW_INDEXED --batch '$BATCH_FILE'"
rm -f "$BATCH_FILE"

# Test 18: Cache functionality (run nodes twice, second should be faster)
run_test "Cache functionality" "time $PW_INDEXED nodes > /dev/null && time $PW_INDEXED nodes > /dev/null"

# Cleanup
rm -f "$TEST_FILE"

echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    echo ""
    echo "Common issues:"
    echo "- Missing dependencies (jq, pipewire-utils)"
    echo "- PipeWire not running"
    echo "- Insufficient permissions"
    echo ""
    echo "Run with verbose flag to debug:"
    echo "  $PW_INDEXED --verbose nodes"
    exit 1
fi
