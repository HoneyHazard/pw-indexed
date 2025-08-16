#!/bin/bash

# pw_indexed.sh - Swiss Army Knife for PipeWire Connection Management
# 
# Comprehensive PipeWire connection management with indexed node enumeration
# Inspired by qpwgraph's enumeration system and designed to work around 
# qpwgraph's interference with programmatic connection management.
#
# Key Features:
# - Indexed node enumeration matching qpwgraph (node~0, node~1, node~2)
# - qpwgraph service management (pause/resume for reliable operations)
# - Pattern-based connection operations
# - Canonical one-liner format for copy-paste
# - Live patchbay synchronization
#
# Author: AI Agent System
# Version: 1.0.0
# License: MIT

# Safe mode: pipefail and exit-on-error enabled, unset variable checking disabled for arrays
set -eo pipefail

#########################################
# CONFIGURATION & GLOBALS
#########################################

SCRIPT_NAME="pw_indexed.sh"
VERSION="1.0.0"
CACHE_DIR="/tmp/pw_indexed"
CACHE_TTL=5  # Cache valid for 5 seconds

# Service management
QPWGRAPH_PROCESS="qpwgraph"
WIREPLUMBER_SERVICE="wireplumber"

# Output formats
FORMAT_TABLE="table"
FORMAT_ONELINE="oneline"  
FORMAT_JSON="json"

# Global options
VERBOSE=false
DRY_RUN=false
FORMAT="$FORMAT_TABLE"

#########################################
# UTILITY FUNCTIONS
#########################################

log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[$SCRIPT_NAME] $*" >&2
    fi
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    cat << 'EOF'
pw_indexed.sh - Swiss Army Knife for PipeWire Connection Management

USAGE:
    pw_indexed.sh <command> [options] [arguments]

COMMANDS:
    nodes [pattern]                 List nodes with indexed enumeration
    ports [node] [--input|--output] List ports for node(s)
    connect [pattern]               Show current connections
    make "source~N:port->target~M:port"  Create connection
    remove "pattern->pattern"       Remove connections
    masked "pattern->pattern"        Remove connections with pattern masking
    exclusive "source->target"      Make exclusive connection
    
    pause qpwgraph                  Pause qpwgraph for operations
    resume qpwgraph                 Resume qpwgraph
    service status                  Show service status
    
    sync                           Sync connections to qpwgraph patchbay
    export file.qpwgraph           Export to qpwgraph format
    import file.qpwgraph           Import from qpwgraph format

OPTIONS:
    --oneline                      Canonical one-liner format
    --json                         JSON output
    --dry-run                      Preview mode (no changes)
    --batch file                   Process commands from file
    --verbose                      Verbose output
    --help                         Show this help

EXAMPLES:
    pw_indexed.sh nodes multiband
    pw_indexed.sh make "limiter:output_FL->gate~2:probe_FL"
    pw_indexed.sh pause qpwgraph
    pw_indexed.sh connect --oneline
    
CANONICAL FORMAT:
    source_node~N:port_name->target_node~M:port_name
    
    Where:
    - node_name = first instance (lowest node ID)
    - node_name~1 = second instance  
    - node_name~2 = third instance, etc.

EOF
}

#########################################
# CACHE MANAGEMENT
#########################################

ensure_cache_dir() {
    mkdir -p "$CACHE_DIR"
}

cache_file() {
    echo "$CACHE_DIR/pipewire_dump"
}

is_cache_valid() {
    local cache_file=$(cache_file)
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
        [[ $cache_age -lt $CACHE_TTL ]]
    else
        false
    fi
}

#########################################
# PIPEWIRE DATA ENGINE
#########################################

get_pipewire_dump() {
    local cache_file=$(cache_file)
    
    if is_cache_valid; then
        log "Using cached PipeWire data"
        cat "$cache_file"
    else
        log "Refreshing PipeWire data cache"
        ensure_cache_dir
        pw-dump 2>/dev/null > "$cache_file" || echo '[]' > "$cache_file"
        cat "$cache_file"
    fi
}

# Create indexed node mapping with qpwgraph-compatible enumeration
create_node_mapping() {
    declare -gA node_instances
    declare -gA instance_counters
    declare -gA node_id_lists
    
    log "Creating indexed node mapping..."
    
    # Collect all node IDs for each node name, sorted in ascending order (qpwgraph style)
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            node_id=$(echo "$line" | cut -d':' -f1)
            node_name=$(echo "$line" | cut -d':' -f2)
            
            # Add to the list for this node name
            if [[ -z "${node_id_lists[$node_name]:-}" ]]; then
                node_id_lists[$node_name]="$node_id"
            else
                node_id_lists[$node_name]="${node_id_lists[$node_name]} $node_id"
            fi
        fi
    done < <(get_pipewire_dump | jq -r '
        .[] | 
        select(.type == "PipeWire:Interface:Node") | 
        select(.info.props."node.name" != null) | 
        "\(.id):\(.info.props."node.name")"
    ' 2>/dev/null | sort -t: -k1,1n)
    
    # Assign indexed notation based on ascending node ID order (matches qpwgraph)
    if [[ ${#node_id_lists[@]} -gt 0 ]]; then
        for node_name in "${!node_id_lists[@]}"; do
            node_ids=(${node_id_lists[$node_name]})
            count=${#node_ids[@]}
            instance_counters[$node_name]=$count
        
            if [[ $count -eq 1 ]]; then
                # Single instance - no suffix
                node_instances[${node_ids[0]}]="$node_name"
                log "  $node_name -> ID ${node_ids[0]} (single instance)"
            else
                # Multiple instances - assign based on ascending order
                index=0
                for node_id in "${node_ids[@]}"; do
                    if [[ $index -eq 0 ]]; then
                        # Lowest node ID gets no suffix (base instance)
                        node_instances[$node_id]="$node_name"
                        log "  $node_name -> ID $node_id (base instance)"
                    else
                        # Higher node IDs get ~1, ~2, etc.
                        node_instances[$node_id]="$node_name~$index"
                        log "  $node_name~$index -> ID $node_id"
                    fi
                    index=$((index + 1))
                done
            fi
        done
    else
        log "No nodes found to enumerate"
    fi
    
    log "Node mapping complete. Found ${#node_instances[@]} total nodes."
}

# Resolve tilde notation to actual node ID
resolve_node_id() {
    local tilde_notation="$1"
    
    if [[ "$tilde_notation" == *"~"* ]]; then
        local base_name=$(echo "$tilde_notation" | cut -d'~' -f1)
        local instance_num=$(echo "$tilde_notation" | cut -d'~' -f2)
        
        # Get all instances of this node name, sorted by ID in ascending order
        local instances=()
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local node_id=$(echo "$line" | cut -d':' -f1)
                instances+=("$node_id")
            fi
        done < <(get_pipewire_dump | jq -r --arg name "$base_name" '
            .[] |
            select(.type == "PipeWire:Interface:Node") |
            select(.info.props."node.name" == $name) |
            "\(.id):\(.info.props."node.name")"
        ' 2>/dev/null | sort -t: -k1,1n)
        
        # Return the node ID at the specified index
        local array_index=$instance_num
        if [[ $array_index -ge 0 && $array_index -lt ${#instances[@]} ]]; then
            echo "${instances[$array_index]}"
            return 0
        else
            return 1
        fi
    else
        # No tilde notation - get the first instance (lowest node ID)
        get_pipewire_dump | jq -r --arg name "$tilde_notation" '
            .[] |
            select(.type == "PipeWire:Interface:Node") |
            select(.info.props."node.name" == $name) |
            .id
        ' 2>/dev/null | sort -n | head -1
    fi
}

# Get port ID for a specific node ID and port name
get_port_id() {
    local node_id="$1"
    local port_name="$2"
    
    get_pipewire_dump | jq -r --arg node "$node_id" --arg port "$port_name" '
        .[] |
        select(.type == "PipeWire:Interface:Port") |
        select(.info.props."node.id" == ($node | tonumber)) |
        select(.info.props."port.name" == $port) |
        .id
    ' 2>/dev/null
}

#########################################
# SERVICE MANAGEMENT
#########################################

is_qpwgraph_running() {
    pgrep -x "$QPWGRAPH_PROCESS" >/dev/null 2>&1
}

pause_qpwgraph() {
    if is_qpwgraph_running; then
        log "Pausing qpwgraph for reliable connection operations..."
        # Send SIGSTOP to pause the process without killing it
        pkill -STOP -x "$QPWGRAPH_PROCESS" 2>/dev/null || true
        sleep 0.5  # Give it a moment to pause
        echo "qpwgraph paused"
    else
        echo "qpwgraph not running"
    fi
}

resume_qpwgraph() {
    if pgrep -x "$QPWGRAPH_PROCESS" >/dev/null 2>&1; then
        log "Resuming qpwgraph..."
        # Send SIGCONT to resume the paused process
        pkill -CONT -x "$QPWGRAPH_PROCESS" 2>/dev/null || true
        sleep 0.5  # Give it a moment to resume
        echo "qpwgraph resumed"
    else
        echo "qpwgraph not running"
    fi
}

service_status() {
    echo "=== Service Status ==="
    
    if is_qpwgraph_running; then
        # Check if it's paused (stopped)
        local qpw_state=$(ps -o state= -p $(pgrep -x "$QPWGRAPH_PROCESS") 2>/dev/null | tr -d ' ')
        if [[ "$qpw_state" == "T" ]]; then
            echo "qpwgraph: PAUSED (can resume)"
        else
            echo "qpwgraph: RUNNING"
        fi
    else
        echo "qpwgraph: NOT RUNNING"
    fi
    
    # Check wireplumber
    if systemctl --user is-active "$WIREPLUMBER_SERVICE" >/dev/null 2>&1; then
        echo "wireplumber: ACTIVE"
    else
        echo "wireplumber: INACTIVE"
    fi
    
    # Check PipeWire
    if systemctl --user is-active pipewire >/dev/null 2>&1; then
        echo "pipewire: ACTIVE"
    else
        echo "pipewire: INACTIVE"
    fi
}

#########################################
# PATTERN MATCHING
#########################################

pattern_match() {
    local text="$1"
    local pattern="$2"
    
    # Simple glob pattern matching
    case "$text" in
        $pattern) return 0 ;;
        *) return 1 ;;
    esac
}

#########################################
# CORE OPERATIONS
#########################################

list_nodes() {
    local pattern="*"
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -*)
                error "Unknown option for nodes command: $1"
                ;;
            *)
                pattern="$1"
                shift
                break
                ;;
        esac
    done
    
    log "Listing nodes with pattern: $pattern"
    create_node_mapping
    
    case "$FORMAT" in
        "$FORMAT_ONELINE")
            if [[ ${#node_instances[@]} -gt 0 ]]; then
                for node_id in "${!node_instances[@]}"; do
                    local indexed_name="${node_instances[$node_id]}"
                    if pattern_match "$indexed_name" "$pattern"; then
                        echo "$indexed_name@$node_id"
                    fi
                done | sort
            fi
            ;;
        "$FORMAT_JSON")
            echo "["
            local first=true
            if [[ ${#node_instances[@]} -gt 0 ]]; then
                for node_id in "${!node_instances[@]}"; do
                    local indexed_name="${node_instances[$node_id]}"
                    if pattern_match "$indexed_name" "$pattern"; then
                        if [[ "$first" == true ]]; then
                            first=false
                        else
                            echo ","
                        fi
                        echo "  {\"name\": \"$indexed_name\", \"node_id\": $node_id}"
                    fi
                done
            fi
            echo "]"
            ;;
        *)
            # Table format
            echo "=== Indexed Nodes ==="
            printf "%-40s %s\n" "INDEXED NAME" "NODE ID"
            printf "%-40s %s\n" "$(printf '%*s' 40 '' | tr ' ' '-')" "-------"
            
            if [[ ${#node_instances[@]} -gt 0 ]]; then
                output_lines=()
                for node_id in "${!node_instances[@]}"; do
                    indexed_name="${node_instances[$node_id]}"
                    if pattern_match "$indexed_name" "$pattern"; then
                        output_lines+=("$(printf "%-40s %s\n" "$indexed_name" "$node_id")")
                    fi
                done
                # Sort and output the lines
                if [[ ${#output_lines[@]} -gt 0 ]]; then
                    printf '%s\n' "${output_lines[@]}" | sort
                fi
            fi
            ;;
    esac
}

list_ports() {
    local node_pattern="${1:-*}"
    local port_filter="${2:-}"
    
    log "Listing ports for node pattern: $node_pattern"
    create_node_mapping
    
    case "$FORMAT" in
        "$FORMAT_ONELINE")
            if [[ ${#node_instances[@]} -gt 0 ]]; then
                for node_id in "${!node_instances[@]}"; do
                    local indexed_name="${node_instances[$node_id]}"
                    if pattern_match "$indexed_name" "$node_pattern"; then
                        get_pipewire_dump | jq -r --arg node_id "$node_id" '
                            .[] |
                            select(.type == "PipeWire:Interface:Port") |
                            select(.info.props."node.id" == ($node_id | tonumber)) |
                            .info.props."port.name"
                        ' 2>/dev/null | while read -r port_name; do
                            if [[ -n "$port_name" ]]; then
                                # Apply port filter if specified
                                case "$port_filter" in
                                    "--input")
                                        if [[ "$port_name" == *"input"* || "$port_name" == *"playback"* ]]; then
                                            echo "$indexed_name:$port_name"
                                        fi
                                        ;;
                                    "--output")
                                        if [[ "$port_name" == *"output"* || "$port_name" == *"capture"* || "$port_name" == *"monitor"* ]]; then
                                            echo "$indexed_name:$port_name"
                                        fi
                                        ;;
                                    *)
                                        echo "$indexed_name:$port_name"
                                        ;;
                                esac
                            fi
                        done
                    fi
                done | sort
            fi
            ;;
        *)
            # Table format
            echo "=== Ports ==="
            printf "%-30s %-20s %s\n" "NODE" "PORT" "DIRECTION"
            printf "%-30s %-20s %s\n" "$(printf '%*s' 30 '' | tr ' ' '-')" "$(printf '%*s' 20 '' | tr ' ' '-')" "---------"
            
            if [[ ${#node_instances[@]} -gt 0 ]]; then
                for node_id in $(printf '%s\n' "${!node_instances[@]}" | sort -n); do
                    local indexed_name="${node_instances[$node_id]}"
                    if pattern_match "$indexed_name" "$node_pattern"; then
                        get_pipewire_dump | jq -r --arg node_id "$node_id" '
                            .[] |
                            select(.type == "PipeWire:Interface:Port") |
                            select(.info.props."node.id" == ($node_id | tonumber)) |
                            "\(.info.props."port.name"):\(.info.props."port.direction")"
                        ' 2>/dev/null | while IFS=':' read -r port_name direction; do
                            if [[ -n "$port_name" ]]; then
                                # Apply port filter if specified
                                local show_port=true
                                case "$port_filter" in
                                    "--input")
                                        if [[ "$direction" != "in" ]]; then
                                            show_port=false
                                        fi
                                        ;;
                                    "--output")
                                        if [[ "$direction" != "out" ]]; then
                                            show_port=false
                                        fi
                                        ;;
                                esac
                                
                                if [[ "$show_port" == true ]]; then
                                    printf "%-30s %-20s %s\n" "$indexed_name" "$port_name" "$direction"
                                fi
                            fi
                        done
                    fi
                done
            fi
            ;;
    esac
}

#########################################
# CONNECTION OPERATIONS
#########################################

# Get port name by port ID
get_port_name_by_id() {
    local port_id="$1"
    
    get_pipewire_dump | jq -r --arg port_id "$port_id" '
        .[] |
        select(.type == "PipeWire:Interface:Port") |
        select(.id == ($port_id | tonumber)) |
        .info.props."port.name"
    ' 2>/dev/null
}

# List current connections with indexed node names
list_connections() {
    local pattern="*"
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --oneline)
                FORMAT="$FORMAT_ONELINE"
                shift
                ;;
            --json)
                FORMAT="$FORMAT_JSON"
                shift
                ;;
            -*)
                error "Unknown option for connect command: $1"
                ;;
            *)
                pattern="$1"
                shift
                break
                ;;
        esac
    done
    
    log "Listing connections with pattern: $pattern"
    create_node_mapping
    
    case "$FORMAT" in
        "$FORMAT_ONELINE")
            get_pipewire_dump | jq -r '
                .[] |
                select(.type == "PipeWire:Interface:Link") |
                select(.info.state == "active" or .info.state == "paused") |
                "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id")"
            ' 2>/dev/null | while IFS= read -r connection; do
                if [[ -n "$connection" ]]; then
                    # Parse connection
                    local output_part input_part
                    output_part=$(echo "$connection" | cut -d'-' -f1)
                    input_part=$(echo "$connection" | cut -d'>' -f2)
                    
                    local output_node_id output_port_id input_node_id input_port_id
                    output_node_id=$(echo "$output_part" | cut -d':' -f1)
                    output_port_id=$(echo "$output_part" | cut -d':' -f2)
                    input_node_id=$(echo "$input_part" | cut -d':' -f1)
                    input_port_id=$(echo "$input_part" | cut -d':' -f2)
                    
                    # Get indexed names and port names
                    local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
                    local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
                    local output_port_name input_port_name
                    output_port_name=$(get_port_name_by_id "$output_port_id")
                    input_port_name=$(get_port_name_by_id "$input_port_id")
                    
                    # Create canonical connection string
                    local canonical="$output_indexed_name:$output_port_name->$input_indexed_name:$input_port_name"
                    
                    # Apply pattern matching
                    if pattern_match "$canonical" "$pattern"; then
                        echo "$canonical"
                    fi
                fi
            done | sort
            ;;
        "$FORMAT_JSON")
            echo "["
            local first=true
            get_pipewire_dump | jq -r '
                .[] |
                select(.type == "PipeWire:Interface:Link") |
                select(.info.state == "active" or .info.state == "paused") |
                "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id"):\(.id):\(.info.state)"
            ' 2>/dev/null | while IFS= read -r connection; do
                if [[ -n "$connection" ]]; then
                    # Parse connection
                    local parts=($(echo "$connection" | tr ':' ' '))
                    local output_node_id="${parts[0]}"
                    local output_port_id="${parts[1]}"
                    local input_node_id="${parts[3]}"
                    local input_port_id="${parts[4]}"
                    local link_id="${parts[5]}"
                    local state="${parts[6]}"
                    
                    # Get indexed names and port names
                    local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
                    local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
                    local output_port_name input_port_name
                    output_port_name=$(get_port_name_by_id "$output_port_id")
                    input_port_name=$(get_port_name_by_id "$input_port_id")
                    
                    # Create canonical connection string
                    local canonical="$output_indexed_name:$output_port_name->$input_indexed_name:$input_port_name"
                    
                    # Apply pattern matching
                    if pattern_match "$canonical" "$pattern"; then
                        if [[ "$first" == true ]]; then
                            first=false
                        else
                            echo ","
                        fi
                        echo "  {\"connection\": \"$canonical\", \"link_id\": $link_id, \"state\": \"$state\"}"
                    fi
                fi
            done
            echo "]"
            ;;
        *)
            # Table format
            echo "=== Active Connections ==="
            printf "%-50s %-50s %s\n" "SOURCE" "TARGET" "STATE"
            printf "%-50s %-50s %s\n" "$(printf '%*s' 50 '' | tr ' ' '-')" "$(printf '%*s' 50 '' | tr ' ' '-')" "-----"
            
            get_pipewire_dump | jq -r '
                .[] |
                select(.type == "PipeWire:Interface:Link") |
                select(.info.state == "active" or .info.state == "paused") |
                "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id"):\(.info.state)"
            ' 2>/dev/null | while IFS= read -r connection; do
                if [[ -n "$connection" ]]; then
                    # Parse connection
                    local output_part input_part state
                    output_part=$(echo "$connection" | cut -d'-' -f1)
                    input_part=$(echo "$connection" | cut -d'>' -f2 | cut -d':' -f1,2)
                    state=$(echo "$connection" | cut -d':' -f5)
                    
                    local output_node_id output_port_id input_node_id input_port_id
                    output_node_id=$(echo "$output_part" | cut -d':' -f1)
                    output_port_id=$(echo "$output_part" | cut -d':' -f2)
                    input_node_id=$(echo "$input_part" | cut -d':' -f1)
                    input_port_id=$(echo "$input_part" | cut -d':' -f2)
                    
                    # Get indexed names and port names
                    local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
                    local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
                    local output_port_name input_port_name
                    output_port_name=$(get_port_name_by_id "$output_port_id")
                    input_port_name=$(get_port_name_by_id "$input_port_id")
                    
                    # Create source and target strings
                    local source="$output_indexed_name:$output_port_name"
                    local target="$input_indexed_name:$input_port_name"
                    local canonical="$source->$target"
                    
                    # Apply pattern matching
                    if pattern_match "$canonical" "$pattern"; then
                        printf "%-50s %-50s %s\n" "$source" "$target" "$state"
                    fi
                fi
            done
            ;;
    esac
}

# Parse canonical connection format: source~N:port->target~M:port
# Returns: source_node:source_port:target_node:target_port
parse_connection_format() {
    local connection_spec="$1"
    
    # Handle both -> and \u003e arrow formats
    local arrow_pattern="->"
    if [[ "$connection_spec" == *"\\u003e"* ]]; then
        # Convert \u003e to >
        connection_spec=$(echo "$connection_spec" | sed 's/\\u003e/>/g')
        arrow_pattern="->"
    elif [[ "$connection_spec" == *"->"* ]]; then
        arrow_pattern="->"
    elif [[ "$connection_spec" == *"->"* ]]; then
        arrow_pattern="->"
    else
        error "Invalid connection format. Expected: source:port->target:port or source:port->target:port"
    fi
    
    # Split on arrow
    local source_part target_part
    if [[ "$arrow_pattern" == "->" ]]; then
        source_part=$(echo "$connection_spec" | cut -d'-' -f1)
        target_part=$(echo "$connection_spec" | cut -d'>' -f2)
    else
        # Handle -> pattern
        source_part="${connection_spec%%->*}"
        target_part="${connection_spec##*->}"
    fi
    
    # Extract node and port from source
    if [[ "$source_part" != *":"* ]]; then
        error "Invalid source format. Expected: node:port"
    fi
    local source_node source_port
    source_node=$(echo "$source_part" | cut -d':' -f1)
    source_port=$(echo "$source_part" | cut -d':' -f2)
    
    # Extract node and port from target
    if [[ "$target_part" != *":"* ]]; then
        error "Invalid target format. Expected: node:port"
    fi
    local target_node target_port
    target_node=$(echo "$target_part" | cut -d':' -f1)
    target_port=$(echo "$target_part" | cut -d':' -f2)
    
    # Return colon-separated values
    echo "$source_node:$source_port:$target_node:$target_port"
}

# Create a connection using canonical format
make_connection() {
    local connection_spec=""
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                error "Unknown option for make command: $1"
                ;;
            *)
                connection_spec="$1"
                shift
                break
                ;;
        esac
    done
    
    if [[ -z "$connection_spec" ]]; then
        error "Connection specification required. Usage: make \"source:port->target:port\""
    fi
    
    log "Creating connection: $connection_spec"
    create_node_mapping
    
    # Parse the connection specification
    local parsed
    parsed=$(parse_connection_format "$connection_spec")
    local source_node source_port target_node target_port
    source_node=$(echo "$parsed" | cut -d':' -f1)
    source_port=$(echo "$parsed" | cut -d':' -f2)
    target_node=$(echo "$parsed" | cut -d':' -f3)
    target_port=$(echo "$parsed" | cut -d':' -f4)
    
    # Resolve indexed node names to node IDs
    local source_node_id target_node_id
    source_node_id=$(resolve_node_id "$source_node")
    target_node_id=$(resolve_node_id "$target_node")
    
    if [[ -z "$source_node_id" ]]; then
        error "Source node not found: $source_node"
    fi
    
    if [[ -z "$target_node_id" ]]; then
        error "Target node not found: $target_node"
    fi
    
    log "Resolved: $source_node -> node ID $source_node_id"
    log "Resolved: $target_node -> node ID $target_node_id"
    
    # Get port IDs
    local source_port_id target_port_id
    source_port_id=$(get_port_id "$source_node_id" "$source_port")
    target_port_id=$(get_port_id "$target_node_id" "$target_port")
    
    if [[ -z "$source_port_id" ]]; then
        error "Source port not found: $source_node:$source_port (node ID $source_node_id)"
    fi
    
    if [[ -z "$target_port_id" ]]; then
        error "Target port not found: $target_node:$target_port (node ID $target_node_id)"
    fi
    
    log "Resolved: $source_node:$source_port -> port ID $source_port_id"
    log "Resolved: $target_node:$target_port -> port ID $target_port_id"
    
    # Check if connection already exists
    local existing_connection
    existing_connection=$(get_pipewire_dump | jq -r --arg out_port "$source_port_id" --arg in_port "$target_port_id" '
        .[] |
        select(.type == "PipeWire:Interface:Link") |
        select(.info."output-port-id" == ($out_port | tonumber)) |
        select(.info."input-port-id" == ($in_port | tonumber)) |
        .id
    ' 2>/dev/null | head -1)
    
    if [[ -n "$existing_connection" ]]; then
        echo "Connection already exists (Link ID: $existing_connection)"
        return 0
    fi
    
    # Create the connection
    if [[ "$DRY_RUN" == true ]]; then
        echo "DRY RUN: Would create connection $source_node:$source_port -> $target_node:$target_port"
        echo "  Source port ID: $source_port_id"
        echo "  Target port ID: $target_port_id"
        return 0
    fi
    
    log "Creating connection: port $source_port_id -> port $target_port_id"
    
    # Use pw-link to create the connection
    if pw-link "$source_port_id" "$target_port_id" >/dev/null 2>&1; then
        echo "Successfully created connection: $source_node:$source_port -> $target_node:$target_port"
    else
        error "Failed to create connection: $source_node:$source_port -> $target_node:$target_port"
    fi
}

# Remove connections using canonical format or pattern matching
remove_connection() {
    local connection_spec=""
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                error "Unknown option for remove command: $1"
                ;;
            *)
                connection_spec="$1"
                shift
                break
                ;;
        esac
    done
    
    if [[ -z "$connection_spec" ]]; then
        error "Connection specification required. Usage: remove \"source:port->target:port\" or remove \"*pattern*\""
    fi
    
    log "Removing connections: $connection_spec"
    create_node_mapping
    
    local removed_count=0
    local failed_count=0
    
    # Check if this looks like a specific connection (has ->) or a pattern
    if [[ "$connection_spec" == *"->"* ]]; then
        # Specific connection removal
        log "Removing specific connection: $connection_spec"
        
        # Parse the connection specification 
        local parsed
        parsed=$(parse_connection_format "$connection_spec")
        local source_node source_port target_node target_port
        source_node=$(echo "$parsed" | cut -d':' -f1)
        source_port=$(echo "$parsed" | cut -d':' -f2)
        target_node=$(echo "$parsed" | cut -d':' -f3)
        target_port=$(echo "$parsed" | cut -d':' -f4)
        
        # Resolve indexed node names to node IDs
        local source_node_id target_node_id
        source_node_id=$(resolve_node_id "$source_node")
        target_node_id=$(resolve_node_id "$target_node")
        
        if [[ -z "$source_node_id" ]]; then
            error "Source node not found: $source_node"
        fi
        
        if [[ -z "$target_node_id" ]]; then
            error "Target node not found: $target_node"
        fi
        
        # Get port IDs
        local source_port_id target_port_id
        source_port_id=$(get_port_id "$source_node_id" "$source_port")
        target_port_id=$(get_port_id "$target_node_id" "$target_port")
        
        if [[ -z "$source_port_id" ]]; then
            error "Source port not found: $source_node:$source_port (node ID $source_node_id)"
        fi
        
        if [[ -z "$target_port_id" ]]; then
            error "Target port not found: $target_node:$target_port (node ID $target_node_id)"
        fi
        
        log "Resolved: $source_node:$source_port -> port ID $source_port_id"
        log "Resolved: $target_node:$target_port -> port ID $target_port_id"
        
        # Find the connection to remove
        local link_id
        link_id=$(get_pipewire_dump | jq -r --arg out_port "$source_port_id" --arg in_port "$target_port_id" '
            .[] |
            select(.type == "PipeWire:Interface:Link") |
            select(.info."output-port-id" == ($out_port | tonumber)) |
            select(.info."input-port-id" == ($in_port | tonumber)) |
            .id
        ' 2>/dev/null | head -1)
        
        if [[ -z "$link_id" ]]; then
            echo "Connection not found: $connection_spec"
            return 1
        fi
        
        # Remove the connection
        if [[ "$DRY_RUN" == true ]]; then
            echo "DRY RUN: Would remove connection $source_node:$source_port -> $target_node:$target_port (Link ID: $link_id)"
            return 0
        fi
        
        log "Removing connection: Link ID $link_id"
        
        if pw-link -d "$link_id" >/dev/null 2>&1; then
            echo "Successfully removed connection: $source_node:$source_port -> $target_node:$target_port"
            removed_count=1
        else
            echo "Failed to remove connection: $source_node:$source_port -> $target_node:$target_port"
            failed_count=1
        fi
    else
        # Pattern-based removal
        log "Removing connections matching pattern: $connection_spec"
        
        # Use a temporary file to collect results from the subshell
        local temp_file="/tmp/pw_indexed_remove_$$"
        
        # Get all active connections and match against the pattern
        get_pipewire_dump | jq -r '
            .[] |
            select(.type == "PipeWire:Interface:Link") |
            select(.info.state == "active") |
            "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id"):\(.id)"
        ' 2>/dev/null | while IFS= read -r connection; do
            if [[ -n "$connection" ]]; then
                # Parse connection properly
                # Format: output_node:output_port->input_node:input_port:link_id
                local output_part="${connection%%->*}"  # Everything before ->
                local remainder="${connection#*->}"     # Everything after ->
                local input_part="${remainder%:*}"     # Everything before last :
                local link_id="${remainder##*:}"       # Everything after last :
                
                local output_node_id="${output_part%:*}"  # Before last : in output_part
                local output_port_id="${output_part##*:}" # After last : in output_part
                local input_node_id="${input_part%:*}"   # Before last : in input_part  
                local input_port_id="${input_part##*:}"  # After last : in input_part
                
                # Get indexed names and port names
                local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
                local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
                local output_port_name input_port_name
                output_port_name=$(get_port_name_by_id "$output_port_id")
                input_port_name=$(get_port_name_by_id "$input_port_id")
                
                # Create canonical connection string
                local canonical="$output_indexed_name:$output_port_name->$input_indexed_name:$input_port_name"
                
                # Apply pattern matching
                if pattern_match "$canonical" "$connection_spec"; then
                    if [[ "$DRY_RUN" == true ]]; then
                        echo "DRY RUN: Would remove $canonical (Link ID: $link_id)"
                        echo "removed" >> "$temp_file"
                    else
                        log "Removing connection: $canonical (Link ID: $link_id)"
                        if pw-link -d "$link_id" >/dev/null 2>&1; then
                            echo "Removed: $canonical"
                            echo "removed" >> "$temp_file"
                        else
                            echo "Failed to remove: $canonical"
                            echo "failed" >> "$temp_file"
                        fi
                    fi
                fi
            fi
        done
        
        # Count results from temp file
        if [[ -f "$temp_file" ]]; then
            removed_count=$(grep -c "removed" "$temp_file" 2>/dev/null || echo 0)
            failed_count=$(grep -c "failed" "$temp_file" 2>/dev/null || echo 0)
            rm -f "$temp_file"
            
            # Clean up any newlines in the count variables
            removed_count=$(echo "$removed_count" | tr -d '\n')
            failed_count=$(echo "$failed_count" | tr -d '\n')
        fi
    fi
    
    # Summary
    if [[ "$DRY_RUN" == true ]]; then
        echo "DRY RUN: Would remove $removed_count connection(s)"
    else
        echo "Removed $removed_count connection(s)"
        if [[ "$failed_count" -gt 0 ]]; then
            echo "Failed to remove $failed_count connection(s)"
            return 1
        fi
    fi
    
    return 0
}

# Remove connections with pattern masking (allows wildcards in both source and target)
masked_remove_connection() {
    local connection_pattern=""
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                error "Unknown option for masked command: $1"
                ;;
            *)
                connection_pattern="$1"
                shift
                break
                ;;
        esac
    done
    
    if [[ -z "$connection_pattern" ]]; then
        error "Connection pattern required. Usage: masked \"source_pattern->target_pattern\""
    fi
    
    log "Masked removing connections: $connection_pattern"
    create_node_mapping
    
    local removed_count=0
    local failed_count=0
    
    # Parse the pattern into source and target parts
    if [[ "$connection_pattern" != *"->"* ]]; then
        error "Invalid pattern format. Expected: source_pattern->target_pattern"
    fi
    
    local source_pattern="${connection_pattern%%->*}"  # Everything before ->
    local target_pattern="${connection_pattern##*->}"  # Everything after ->
    
    log "Source pattern: $source_pattern"
    log "Target pattern: $target_pattern"
    
    # Use a temporary file to collect results from the subshell
    local temp_file="/tmp/pw_indexed_masked_$$"
    
    # Get all active connections and apply dual pattern matching
    get_pipewire_dump | jq -r '
        .[] |
        select(.type == "PipeWire:Interface:Link") |
        select(.info.state == "active") |
        "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id"):\(.id)"
    ' 2>/dev/null | while IFS= read -r connection; do
        if [[ -n "$connection" ]]; then
            # Parse connection properly
            # Format: output_node:output_port->input_node:input_port:link_id
            local output_part="${connection%%->*}"  # Everything before ->
            local remainder="${connection#*->}"     # Everything after ->
            local input_part="${remainder%:*}"     # Everything before last :
            local link_id="${remainder##*:}"       # Everything after last :
            
            local output_node_id="${output_part%:*}"  # Before last : in output_part
            local output_port_id="${output_part##*:}" # After last : in output_part
            local input_node_id="${input_part%:*}"   # Before last : in input_part  
            local input_port_id="${input_part##*:}"  # After last : in input_part
            
            # Get indexed names and port names
            local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
            local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
            local output_port_name input_port_name
            output_port_name=$(get_port_name_by_id "$output_port_id")
            input_port_name=$(get_port_name_by_id "$input_port_id")
            
            # Create source and target strings for matching
            local source_string="$output_indexed_name:$output_port_name"
            local target_string="$input_indexed_name:$input_port_name"
            local canonical="$source_string->$target_string"
            
            # Apply dual pattern matching - both source and target must match their patterns
            local source_matches=false
            local target_matches=false
            
            if pattern_match "$source_string" "$source_pattern"; then
                source_matches=true
            fi
            
            if pattern_match "$target_string" "$target_pattern"; then
                target_matches=true
            fi
            
            # Only proceed if both patterns match
            if [[ "$source_matches" == true && "$target_matches" == true ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    echo "DRY RUN: Would remove $canonical (Link ID: $link_id)"
                    echo "removed" >> "$temp_file"
                else
                    log "Masked removing connection: $canonical (Link ID: $link_id)"
                    if pw-link -d "$link_id" >/dev/null 2>&1; then
                        echo "Removed: $canonical"
                        echo "removed" >> "$temp_file"
                    else
                        echo "Failed to remove: $canonical"
                        echo "failed" >> "$temp_file"
                    fi
                fi
            fi
        fi
    done
    
    # Count results from temp file
    if [[ -f "$temp_file" ]]; then
        removed_count=$(grep -c "removed" "$temp_file" 2>/dev/null || echo 0)
        failed_count=$(grep -c "failed" "$temp_file" 2>/dev/null || echo 0)
        rm -f "$temp_file"
        
        # Clean up any newlines in the count variables
        removed_count=$(echo "$removed_count" | tr -d '\n')
        failed_count=$(echo "$failed_count" | tr -d '\n')
    fi
    
    # Summary
    if [[ "$DRY_RUN" == true ]]; then
        echo "DRY RUN: Would remove $removed_count connection(s) matching both patterns"
    else
        echo "Removed $removed_count connection(s) matching both patterns"
        if [[ "$failed_count" -gt 0 ]]; then
            echo "Failed to remove $failed_count connection(s)"
            return 1
        fi
    fi
    
    return 0
}

# Create exclusive connection (remove conflicting connections first)
exclusive_connection() {
    local connection_spec=""
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                error "Unknown option for exclusive command: $1"
                ;;
            *)
                connection_spec="$1"
                shift
                break
                ;;
        esac
    done
    
    if [[ -z "$connection_spec" ]]; then
        error "Connection specification required. Usage: exclusive \"source:port->target:port\""
    fi
    
    log "Creating exclusive connection: $connection_spec"
    create_node_mapping
    
    # Parse the connection specification
    local parsed
    parsed=$(parse_connection_format "$connection_spec")
    local source_node source_port target_node target_port
    source_node=$(echo "$parsed" | cut -d':' -f1)
    source_port=$(echo "$parsed" | cut -d':' -f2)
    target_node=$(echo "$parsed" | cut -d':' -f3)
    target_port=$(echo "$parsed" | cut -d':' -f4)
    
    # Resolve indexed node names to node IDs
    local source_node_id target_node_id
    source_node_id=$(resolve_node_id "$source_node")
    target_node_id=$(resolve_node_id "$target_node")
    
    if [[ -z "$source_node_id" ]]; then
        error "Source node not found: $source_node"
    fi
    
    if [[ -z "$target_node_id" ]]; then
        error "Target node not found: $target_node"
    fi
    
    log "Resolved: $source_node -> node ID $source_node_id"
    log "Resolved: $target_node -> node ID $target_node_id"
    
    # Get port IDs
    local source_port_id target_port_id
    source_port_id=$(get_port_id "$source_node_id" "$source_port")
    target_port_id=$(get_port_id "$target_node_id" "$target_port")
    
    if [[ -z "$source_port_id" ]]; then
        error "Source port not found: $source_node:$source_port (node ID $source_node_id)"
    fi
    
    if [[ -z "$target_port_id" ]]; then
        error "Target port not found: $target_node:$target_port (node ID $target_node_id)"
    fi
    
    log "Resolved: $source_node:$source_port -> port ID $source_port_id"
    log "Resolved: $target_node:$target_port -> port ID $target_port_id"
    
    # Find and remove conflicting connections
    local removed_count=0
    local temp_file="/tmp/pw_indexed_exclusive_$$"
    
    echo "Removing conflicting connections..."
    
    # Find all connections TO the same target port (exclusivity applies to input port only)
    get_pipewire_dump | jq -r --arg target_port "$target_port_id" '
        .[] |
        select(.type == "PipeWire:Interface:Link") |
        select(.info.state == "active") |
        select(
            .info."input-port-id" == ($target_port | tonumber)
        ) |
        "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id"):\(.id)"
    ' 2>/dev/null | while IFS= read -r connection; do
        if [[ -n "$connection" ]]; then
            # Parse connection properly
            local output_part="${connection%%->*}"  # Everything before ->
            local remainder="${connection#*->}"     # Everything after ->
            local input_part="${remainder%:*}"     # Everything before last :
            local link_id="${remainder##*:}"       # Everything after last :
            
            local output_node_id="${output_part%:*}"  # Before last : in output_part
            local output_port_id="${output_part##*:}" # After last : in output_part
            local input_node_id="${input_part%:*}"   # Before last : in input_part  
            local input_port_id="${input_part##*:}"  # After last : in input_part
            
            # Skip if this is exactly the connection we want to create
            if [[ "$output_port_id" == "$source_port_id" && "$input_port_id" == "$target_port_id" ]]; then
                log "Skipping desired connection: already exists (Link ID: $link_id)"
                continue
            fi
            
            # Get indexed names and port names for logging
            local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
            local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
            local output_port_name input_port_name
            output_port_name=$(get_port_name_by_id "$output_port_id")
            input_port_name=$(get_port_name_by_id "$input_port_id")
            
            local canonical="$output_indexed_name:$output_port_name->$input_indexed_name:$input_port_name"
            
            if [[ "$DRY_RUN" == true ]]; then
                echo "DRY RUN: Would remove conflicting connection: $canonical (Link ID: $link_id)"
                echo "removed" >> "$temp_file"
            else
                log "Removing conflicting connection: $canonical (Link ID: $link_id)"
                if pw-link -d "$link_id" >/dev/null 2>&1; then
                    echo "Removed conflicting: $canonical"
                    echo "removed" >> "$temp_file"
                else
                    echo "Failed to remove conflicting: $canonical"
                    echo "failed" >> "$temp_file"
                fi
            fi
        fi
    done
    
    # Count removed connections
    if [[ -f "$temp_file" ]]; then
        removed_count=$(grep -c "removed" "$temp_file" 2>/dev/null || echo 0)
        local failed_count=$(grep -c "failed" "$temp_file" 2>/dev/null || echo 0)
        rm -f "$temp_file"
        
        # Clean up any newlines in the count variables
        removed_count=$(echo "$removed_count" | tr -d '\n')
        failed_count=$(echo "$failed_count" | tr -d '\n')
        
        if [[ "$failed_count" -gt 0 ]]; then
            echo "Warning: Failed to remove $failed_count conflicting connection(s)"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "DRY RUN: Would remove $removed_count conflicting connection(s)"
        echo "DRY RUN: Would create exclusive connection $source_node:$source_port -> $target_node:$target_port"
        return 0
    fi
    
    echo "Removed $removed_count conflicting connection(s)"
    
    # Now create the desired connection
    echo "Creating exclusive connection..."
    
    # Check if the desired connection already exists
    local existing_connection
    existing_connection=$(get_pipewire_dump | jq -r --arg out_port "$source_port_id" --arg in_port "$target_port_id" '
        .[] |
        select(.type == "PipeWire:Interface:Link") |
        select(.info."output-port-id" == ($out_port | tonumber)) |
        select(.info."input-port-id" == ($in_port | tonumber)) |
        .id
    ' 2>/dev/null | head -1)
    
    if [[ -n "$existing_connection" ]]; then
        echo "Exclusive connection already exists (Link ID: $existing_connection)"
        return 0
    fi
    
    log "Creating exclusive connection: port $source_port_id -> port $target_port_id"
    
    # Use pw-link to create the connection
    if pw-link "$source_port_id" "$target_port_id" >/dev/null 2>&1; then
        echo "Successfully created exclusive connection: $source_node:$source_port -> $target_node:$target_port"
    else
        error "Failed to create exclusive connection: $source_node:$source_port -> $target_node:$target_port"
    fi
}

#########################################
# PATCHBAY SYNCHRONIZATION
#########################################

# Export current connection state to qpwgraph format
export_patchbay() {
    local output_file=""
    local patchbay_name="pw_indexed_export"
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                error "Unknown option for export command: $1"
                ;;
            *)
                if [[ -z "$output_file" ]]; then
                    output_file="$1"
                elif [[ -z "$patchbay_name" || "$patchbay_name" == "pw_indexed_export" ]]; then
                    patchbay_name="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$output_file" ]]; then
        error "Output file required. Usage: export file.qpwgraph [name]"
    fi
    
    log "Exporting current connections to: $output_file"
    create_node_mapping
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "DRY RUN: Would export current connections to: $output_file"
        # Count connections without creating the file
        local connection_count=0
        get_pipewire_dump | jq -r '
            .[] |
            select(.type == "PipeWire:Interface:Link") |
            select(.info.state == "active") |
            "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id")"
        ' 2>/dev/null | while IFS= read -r connection; do
            if [[ -n "$connection" ]]; then
                connection_count=$((connection_count + 1))
                # Parse connection for display
                local output_part input_part
                output_part=$(echo "$connection" | cut -d'-' -f1)
                input_part=$(echo "$connection" | cut -d'>' -f2)
                
                local output_node_id output_port_id input_node_id input_port_id
                output_node_id=$(echo "$output_part" | cut -d':' -f1)
                output_port_id=$(echo "$output_part" | cut -d':' -f2)
                input_node_id=$(echo "$input_part" | cut -d':' -f1)
                input_port_id=$(echo "$input_part" | cut -d':' -f2)
                
                # Get indexed names and port names
                local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
                local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
                local output_port_name input_port_name
                output_port_name=$(get_port_name_by_id "$output_port_id")
                input_port_name=$(get_port_name_by_id "$input_port_id")
                
                echo "  Would export: $output_indexed_name:$output_port_name -> $input_indexed_name:$input_port_name"
            fi
        done
        
        local total_connections=$(get_pipewire_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Link") | select(.info.state == "active")' 2>/dev/null | jq -s length 2>/dev/null)
        echo "DRY RUN: Would export $total_connections connections total"
        return 0
    fi
    
    # Create XML header
    cat > "$output_file" << EOF
<?xml version="1.0"?>
<!DOCTYPE patchbay>
<patchbay name="$patchbay_name" version="0.6.1">
 <items>
EOF
    
    # Get all active connections and convert to qpwgraph format
    get_pipewire_dump | jq -r '
        .[] |
        select(.type == "PipeWire:Interface:Link") |
        select(.info.state == "active") |
        "\(.info."output-node-id"):\(.info."output-port-id")->\(.info."input-node-id"):\(.info."input-port-id")"
    ' 2>/dev/null | while IFS= read -r connection; do
        if [[ -n "$connection" ]]; then
            # Parse connection
            local output_part input_part
            output_part=$(echo "$connection" | cut -d'-' -f1)
            input_part=$(echo "$connection" | cut -d'>' -f2)
            
            local output_node_id output_port_id input_node_id input_port_id
            output_node_id=$(echo "$output_part" | cut -d':' -f1)
            output_port_id=$(echo "$output_part" | cut -d':' -f2)
            input_node_id=$(echo "$input_part" | cut -d':' -f1)
            input_port_id=$(echo "$input_part" | cut -d':' -f2)
            
            # Get indexed names and port names
            local output_indexed_name="${node_instances[$output_node_id]:-node_$output_node_id}"
            local input_indexed_name="${node_instances[$input_node_id]:-node_$input_node_id}"
            local output_port_name input_port_name
            output_port_name=$(get_port_name_by_id "$output_port_id")
            input_port_name=$(get_port_name_by_id "$input_port_id")
            
            # Write XML item
            cat >> "$output_file" << EOF
  <item node-type="pipewire" port-type="pipewire-audio">
   <output node="$output_indexed_name" port="$output_indexed_name:$output_port_name"/>
   <input node="$input_indexed_name" port="$input_indexed_name:$input_port_name"/>
  </item>
EOF
        fi
    done
    
    # Close XML
    cat >> "$output_file" << EOF
 </items>
</patchbay>
EOF
    
    echo "Exported current connections to: $output_file"
    local connection_count=$(grep -c '<item' "$output_file" 2>/dev/null || echo 0)
    echo "Total connections exported: $connection_count"
}

# Import connections from qpwgraph patchbay file
import_patchbay() {
    local input_file=""
    local import_mode="add"  # add, replace, or merge
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --mode)
                if [[ -z "${2:-}" ]]; then
                    error "--mode option requires a value: add, replace, or merge"
                fi
                import_mode="$2"
                shift 2
                ;;
            -*)
                error "Unknown option for import command: $1"
                ;;
            *)
                if [[ -z "$input_file" ]]; then
                    input_file="$1"
                elif [[ "$import_mode" == "add" ]]; then
                    # If mode not explicitly set and we have a second positional arg, use it as mode
                    case "$1" in
                        "add"|"replace"|"merge")
                            import_mode="$1"
                            ;;
                        *)
                            error "Invalid import mode: $1. Use: add, replace, or merge"
                            ;;
                    esac
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$input_file" ]]; then
        error "Input file required. Usage: import file.qpwgraph [add|replace|merge] or import --mode MODE file.qpwgraph"
    fi
    
    if [[ ! -f "$input_file" ]]; then
        error "Patchbay file not found: $input_file"
    fi
    
    log "Importing connections from: $input_file (mode: $import_mode)"
    create_node_mapping
    
    # Count connections to import
    local total_connections=$(grep -c '<item' "$input_file" 2>/dev/null || echo 0)
    echo "Found $total_connections connections to import"
    
    # Handle replace mode - clear existing connections
    if [[ "$import_mode" == "replace" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "DRY RUN: Would remove all existing connections first"
        else
            echo "Removing all existing connections..."
            # Remove all active connections
            get_pipewire_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Link") | select(.info.state == "active") | .id' 2>/dev/null | while read -r link_id; do
                if [[ -n "$link_id" ]]; then
                    pw-link -d "$link_id" >/dev/null 2>&1
                fi
            done
            sleep 1  # Allow connections to clear
        fi
    fi
    
    local success_count=0
    local error_count=0
    local skip_count=0
    
    # Parse XML and create connections
    # Extract output/input pairs using xmllint or basic parsing
    if command -v xmllint >/dev/null 2>&1; then
        # Use xmllint if available - collect results to avoid subshell variable scoping issues
        local temp_results="/tmp/pw_indexed_xmllint_$$"
        xmllint --xpath '//item' "$input_file" 2>/dev/null | while read -r item; do
            process_patchbay_item "$item" >> "$temp_results"
        done
        
        # Process results from temp file
        if [[ -f "$temp_results" ]]; then
            while IFS= read -r result; do
                case "$result" in
                    "SUCCESS")
                        success_count=$((success_count + 1))
                        ;;
                    "ERROR")
                        error_count=$((error_count + 1))
                        ;;
                    "SKIP")
                        skip_count=$((skip_count + 1))
                        ;;
                    "DRY RUN: Would create connection:"*)
                        echo "$result"
                        success_count=$((success_count + 1))
                        ;;
                    "Failed to create:"*)
                        echo "$result"
                        error_count=$((error_count + 1))
                        ;;
                    *)
                        # Other output from process_patchbay_item
                        if [[ -n "$result" && "$result" != "SUCCESS" && "$result" != "ERROR" && "$result" != "SKIP" ]]; then
                            echo "$result"
                        fi
                        ;;
                esac
            done < "$temp_results"
            rm -f "$temp_results"
        fi
    else
        # Basic XML parsing
        local in_item=false
        local output_node="" output_port="" input_node="" input_port=""
        
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [[ "$line" == *"<item"* ]]; then
                in_item=true
                output_node=""; output_port=""; input_node=""; input_port=""
            elif [[ "$line" == *"</item>"* ]] && [[ "$in_item" == true ]]; then
                # Process the complete item
                if [[ -n "$output_node" && -n "$output_port" && -n "$input_node" && -n "$input_port" ]]; then
                    # Convert to our canonical format
                    local canonical="$output_node:$output_port->$input_node:$input_port"
                    
                    if [[ "$DRY_RUN" == true ]]; then
                        echo "DRY RUN: Would create connection: $canonical"
                        success_count=$((success_count + 1))
                    else
                        # Create the connection using make_connection logic
                        if create_single_connection "$canonical"; then
                            success_count=$((success_count + 1))
                            log "Created: $canonical"
                        else
                            error_count=$((error_count + 1))
                            echo "Failed to create: $canonical"
                        fi
                    fi
                fi
                in_item=false
            elif [[ "$in_item" == true ]]; then
                # Parse output and input lines
                if [[ "$line" == *"<output"* ]]; then
                    output_node=$(echo "$line" | sed 's/.*node="\([^"]*\)".*/\1/')
                    output_port=$(echo "$line" | sed 's/.*port="[^:]*:\([^"]*\)".*/\1/')
                elif [[ "$line" == *"<input"* ]]; then
                    input_node=$(echo "$line" | sed 's/.*node="\([^"]*\)".*/\1/')
                    input_port=$(echo "$line" | sed 's/.*port="[^:]*:\([^"]*\)".*/\1/')
                fi
            fi
        done < "$input_file"
    fi
    
    # Summary
    echo "=== Import Summary ==="
    echo "Total connections in file: $total_connections"
    echo "Successfully created: $success_count"
    if [[ "$error_count" -gt 0 ]]; then
        echo "Failed to create: $error_count"
    fi
    if [[ "$skip_count" -gt 0 ]]; then
        echo "Already existing (skipped): $skip_count"
    fi
    
    if [[ "$error_count" -gt 0 ]]; then
        return 1
    fi
}

# Helper function to process a single patchbay item from XML
process_patchbay_item() {
    local item_xml="$1"
    local output_node="" output_port="" input_node="" input_port=""
    
    # Extract output node and port from XML
    if [[ "$item_xml" == *"<output"* ]]; then
        output_node=$(echo "$item_xml" | sed -n 's/.*<output[^>]*node="\([^"]*\)".*/\1/p')
        output_port=$(echo "$item_xml" | sed -n 's/.*<output[^>]*port="[^:]*:\([^"]*\)".*/\1/p')
    fi
    
    # Extract input node and port from XML
    if [[ "$item_xml" == *"<input"* ]]; then
        input_node=$(echo "$item_xml" | sed -n 's/.*<input[^>]*node="\([^"]*\)".*/\1/p')
        input_port=$(echo "$item_xml" | sed -n 's/.*<input[^>]*port="[^:]*:\([^"]*\)".*/\1/p')
    fi
    
    # Process the connection if we have all parts
    if [[ -n "$output_node" && -n "$output_port" && -n "$input_node" && -n "$input_port" ]]; then
        # Convert to our canonical format
        local canonical="$output_node:$output_port->$input_node:$input_port"
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "DRY RUN: Would create connection: $canonical"
            echo "SUCCESS" # Signal success for counting
        else
            # Create the connection using make_connection logic
            if create_single_connection "$canonical"; then
                log "Created: $canonical"
                echo "SUCCESS" # Signal success for counting
            else
                echo "Failed to create: $canonical"
                echo "ERROR" # Signal error for counting
            fi
        fi
    else
        echo "SKIP" # Signal skip for counting
    fi
}

# Helper function to create a single connection
create_single_connection() {
    local connection_spec="$1"
    
    # Parse the connection specification
    local parsed
    if ! parsed=$(parse_connection_format "$connection_spec" 2>/dev/null); then
        return 1
    fi
    
    local source_node source_port target_node target_port
    source_node=$(echo "$parsed" | cut -d':' -f1)
    source_port=$(echo "$parsed" | cut -d':' -f2)
    target_node=$(echo "$parsed" | cut -d':' -f3)
    target_port=$(echo "$parsed" | cut -d':' -f4)
    
    # Resolve indexed node names to node IDs
    local source_node_id target_node_id
    source_node_id=$(resolve_node_id "$source_node")
    target_node_id=$(resolve_node_id "$target_node")
    
    if [[ -z "$source_node_id" || -z "$target_node_id" ]]; then
        return 1
    fi
    
    # Get port IDs
    local source_port_id target_port_id
    source_port_id=$(get_port_id "$source_node_id" "$source_port")
    target_port_id=$(get_port_id "$target_node_id" "$target_port")
    
    if [[ -z "$source_port_id" || -z "$target_port_id" ]]; then
        return 1
    fi
    
    # Check if connection already exists
    local existing_connection
    existing_connection=$(get_pipewire_dump | jq -r --arg out_port "$source_port_id" --arg in_port "$target_port_id" '
        .[] |
        select(.type == "PipeWire:Interface:Link") |
        select(.info."output-port-id" == ($out_port | tonumber)) |
        select(.info."input-port-id" == ($in_port | tonumber)) |
        .id
    ' 2>/dev/null | head -1)
    
    if [[ -n "$existing_connection" ]]; then
        return 0  # Already exists, treat as success
    fi
    
    # Create the connection
    pw-link "$source_port_id" "$target_port_id" >/dev/null 2>&1
}

# Sync current state with qpwgraph patchbay (bidirectional)
sync_patchbay() {
    local patchbay_file=""
    local sync_mode="export"  # export, import, or bidirectional
    
    # Parse command-specific options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --mode)
                if [[ -z "${2:-}" ]]; then
                    error "--mode option requires a value: export, import, or bidirectional"
                fi
                sync_mode="$2"
                shift 2
                ;;
            -*)
                error "Unknown option for sync command: $1"
                ;;
            *)
                if [[ -z "$patchbay_file" ]]; then
                    patchbay_file="$1"
                elif [[ "$sync_mode" == "export" ]]; then
                    # If mode not explicitly set and we have a second positional arg, use it as mode
                    case "$1" in
                        "export"|"import"|"bidirectional")
                            sync_mode="$1"
                            ;;
                        *)
                            error "Invalid sync mode: $1. Use: export, import, or bidirectional"
                            ;;
                    esac
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$patchbay_file" ]]; then
        error "Patchbay file required. Usage: sync file.qpwgraph [export|import|bidirectional] or sync --mode MODE file.qpwgraph"
    fi
    
    case "$sync_mode" in
        "export")
            echo "Syncing: Exporting current state to $patchbay_file"
            export_patchbay "$patchbay_file" "pw_indexed_sync_$(date +%Y%m%d_%H%M%S)"
            ;;
        "import")
            echo "Syncing: Importing connections from $patchbay_file"
            import_patchbay "$patchbay_file" "merge"
            ;;
        "bidirectional")
            echo "Bidirectional sync not yet implemented - use export or import"
            return 1
            ;;
        *)
            error "Invalid sync mode: $sync_mode. Use: export, import, or bidirectional"
            ;;
    esac
}

#########################################
# BATCH PROCESSING
#########################################

process_batch_file() {
    local batch_file="$1"
    
    if [[ ! -f "$batch_file" ]]; then
        error "Batch file not found: $batch_file"
    fi
    
    log "Processing batch file: $batch_file"
    
    local line_num=0
    local success_count=0
    local error_count=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Remove leading/trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        echo ">>> Line $line_num: $line"
        
        # Parse the command line into an array
        local cmd_args=()
        eval "cmd_args=($line)"
        
        # Execute the command by calling main recursively
        if main "${cmd_args[@]}"; then
            success_count=$((success_count + 1))
            log "Line $line_num: SUCCESS"
        else
            error_count=$((error_count + 1))
            echo "ERROR: Line $line_num failed: $line" >&2
            log "Line $line_num: FAILED"
        fi
        
        echo ""  # Blank line for readability
    done < "$batch_file"
    
    echo "=== Batch Processing Summary ==="
    echo "Total commands: $((success_count + error_count))"
    echo "Successful: $success_count"
    echo "Failed: $error_count"
    
    if [[ "$error_count" -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

#########################################
# MAIN COMMAND DISPATCHER
#########################################

main() {
    # Parse global options first
    while [[ $# -gt 0 ]]; do
        case $1 in
            --oneline)
                FORMAT="$FORMAT_ONELINE"
                shift
                ;;
            --json)
                FORMAT="$FORMAT_JSON"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --batch)
                if [[ -z "${2:-}" ]]; then
                    error "--batch option requires a file path"
                fi
                process_batch_file "$2"
                exit $?
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --version)
                echo "$SCRIPT_NAME version $VERSION"
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Ensure we have a command
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    # Dispatch to command handlers
    case "$command" in
        "nodes"|"n")
            list_nodes "$@"
            ;;
        "ports"|"p")
            list_ports "$@"
            ;;
        "connect"|"c"|"connections")
            list_connections "$@"
            ;;
        "make"|"m")
            make_connection "$@"
            ;;
        "remove"|"r"|"disconnect")
            remove_connection "$@"
            ;;
        "masked"|"mask")
            masked_remove_connection "$@"
            ;;
        "exclusive"|"e")
            exclusive_connection "$@"
            ;;
        "pause")
            if [[ "${1:-}" == "qpwgraph" ]]; then
                pause_qpwgraph
            else
                error "Usage: $SCRIPT_NAME pause qpwgraph"
            fi
            ;;
        "resume")
            if [[ "${1:-}" == "qpwgraph" ]]; then
                resume_qpwgraph
            else
                error "Usage: $SCRIPT_NAME resume qpwgraph"
            fi
            ;;
        "service")
            if [[ "${1:-}" == "status" ]]; then
                service_status
            else
                error "Usage: $SCRIPT_NAME service status"
            fi
            ;;
        "sync")
            sync_patchbay "$@"
            ;;
        "export")
            export_patchbay "$@"
            ;;
        "import")
            import_patchbay "$@"
            ;;
        *)
            error "Unknown command: $command. Use --help for usage."
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
