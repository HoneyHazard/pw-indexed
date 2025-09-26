# pw-indexed Cache Improvement Proposal

## Current Problems

1. **Race Conditions**: Multiple processes can corrupt cache simultaneously  
2. **Inconsistent State**: Stale cache can mix old/new data within single operation
3. **No Failure Recovery**: `pw-dump` failures write invalid `'[]'` cache  
4. **No Validation**: No verification of cache validity
5. **Hard-coded Paths**: Not XDG-compliant, not user-configurable

## Performance Justification for Caching

- `get_pipewire_dump()` called **35 times** per script execution
- `pw-dump` takes ~0.113s per call  
- Without cache: **35 × 0.113s = ~4 seconds** per command
- With cache: **~0.1 seconds** (35x performance improvement)

**Conclusion: Caching is essential for usability**

## Proposed Solutions

### Option 1: Atomic + Locking (Recommended)
```bash
CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/pw_indexed_$$"  # Process-specific
CACHE_LOCK="$CACHE_DIR/cache.lock"

get_pipewire_dump() {
    local cache_file="$CACHE_DIR/pipewire_dump"
    local temp_file="$CACHE_DIR/pipewire_dump.tmp"
    
    # Process-specific cache eliminates most race conditions
    mkdir -p "$CACHE_DIR" 2>/dev/null
    
    if is_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Atomic update with validation
    if pw-dump 2>/dev/null > "$temp_file"; then
        # Validate JSON structure
        if jq -e '.[]' "$temp_file" >/dev/null 2>&1; then
            mv "$temp_file" "$cache_file"
            cat "$cache_file"
        else
            rm -f "$temp_file"
            error "Invalid PipeWire data received"
        fi
    else
        rm -f "$temp_file"
        error "pw-dump failed - is PipeWire running?"
    fi
}
```

### Option 2: Single-Call Architecture (Alternative)
```bash
# Call pw-dump once, store in memory for script lifetime
declare -g PIPEWIRE_DATA=""

init_pipewire_data() {
    if [[ -z "$PIPEWIRE_DATA" ]]; then
        PIPEWIRE_DATA=$(pw-dump 2>/dev/null) || error "pw-dump failed"
        # Validate
        echo "$PIPEWIRE_DATA" | jq -e '.[]' >/dev/null || error "Invalid PipeWire data"
    fi
}

get_pipewire_dump() {
    init_pipewire_data
    echo "$PIPEWIRE_DATA"
}
```

### Option 3: Optional Caching (User Choice)
```bash
# Add --no-cache flag
ENABLE_CACHE=true

get_pipewire_dump() {
    if [[ "$ENABLE_CACHE" == true ]]; then
        # Use improved atomic caching
        get_pipewire_dump_cached
    else
        # Direct call every time
        pw-dump 2>/dev/null || echo '[]'
    fi
}
```

## Recommended Implementation

**Hybrid Approach:**
1. **Default**: Process-specific atomic caching (Option 1)
2. **Fallback**: `--no-cache` flag for debugging (Option 3)  
3. **Future**: Consider single-call architecture for v2.0 (Option 2)

### Key Improvements
- **Process-specific cache dir**: Eliminates multi-user/multi-process races
- **Atomic writes**: `tmp → mv` prevents partial writes  
- **JSON validation**: Ensures cache contains valid data
- **Proper error handling**: Fails fast instead of corrupting cache
- **XDG compliance**: Uses `$XDG_RUNTIME_DIR` when available
- **User control**: `--no-cache` option for debugging

### Cache Location Strategy
```bash
# Priority order:
CACHE_DIR="${PW_INDEXED_CACHE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/pw_indexed_$$}"
```

1. User override: `PW_INDEXED_CACHE_DIR`
2. XDG runtime: `/run/user/1000/pw_indexed_$$` 
3. Fallback: `/tmp/pw_indexed_$$` (process-specific)

## Benefits
- ✅ **35x performance improvement preserved**
- ✅ **Race condition elimination** (process-specific paths)  
- ✅ **Atomic updates** (no corrupted cache states)
- ✅ **Failure recovery** (proper error handling)
- ✅ **User control** (--no-cache option)
- ✅ **XDG compliance** (proper cache locations)
- ✅ **Validation** (ensures cache contains valid JSON)