#!/bin/bash
# Core utility functions

# Color codes for output
RED='\033[0;31m'      # Red for errors
GREEN='\033[0;32m'    # Green for success
YELLOW='\033[1;33m'   # Yellow for warnings
BLUE='\033[0;34m'     # Blue for debug
CYAN='\033[0;36m'     # Cyan for module names
MAGENTA='\033[0;35m'  # Magenta for important highlights
DIM='\033[2m'         # Dim for timestamps
BOLD='\033[1m'        # Bold for emphasis
NC='\033[0m'          # No Color

# Logging functions
log_info() {
    echo -e "${DIM}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${CYAN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${DIM}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${DIM}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW}[WARN]${NC} $*"
}

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo -e "${DIM}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${BLUE}[DEBUG]${NC} $*"
}

# Each step will write directly to its category folder

# Checkpoint functions
checkpoint_start() {
    local module_name=$1
    echo "$(date +%s)" > "${DIRS[CHECKPOINTS_DIR]}/${module_name}.start"
}

checkpoint_complete() {
    local module_name=$1
    echo "$(date +%s)" > "${DIRS[CHECKPOINTS_DIR]}/${module_name}.done"
}

is_module_complete() {
    local module_name=$1
    [[ -f "${DIRS[CHECKPOINTS_DIR]}/${module_name}.done" ]]
}

reset_checkpoints() {
    log_info "Resetting all checkpoints for domain: $DOMAIN"
    rm -rf "${DIRS[CHECKPOINTS_DIR]}"/*
    log_info "Checkpoints cleared"
}

# Get proxy flag for specific tool
# Only httpx and katana support proxy flags
get_proxy_flag() {
    local tool=$1
    # Re-declare PROXY_FLAGS here since associative arrays can't be exported
    declare -A PROXY_FLAGS=(
        [httpx]="-http-proxy"
        [katana]="-proxy"
    )
    if [[ -n "$HTTP_PROXY_URL" && -n "${PROXY_FLAGS[$tool]}" ]]; then
        echo "${PROXY_FLAGS[$tool]} $HTTP_PROXY_URL"
    fi
}

# File operations
check_file() {
    local file=$1
    [[ -f "$file" && -s "$file" ]]
}

dedupe_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        awk '!seen[$0]++' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
}

# Module execution wrapper
MODULE() {
    local module_name=$1
    local module_file="${SCRIPT_DIR}/modules/${module_name}.sh"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    # Check checkpoint
    if is_module_complete "$module_name" && ! should_replay_module "$module_name"; then
        log_info "Module already complete: $module_name (use --replay to re-run)"
        return 0
    fi

    echo -e "${CYAN}=========================================${NC}"
    echo -e "${BOLD}${CYAN}Executing: ${module_name}${NC}"
    if [[ -n "${MODULE_DESC[$module_name]:-}" ]]; then
        echo -e "${DIM}Description: ${MODULE_DESC[$module_name]}${NC}"
    fi
    echo -e "${CYAN}=========================================${NC}"

    # Export environment for module
    export_env

    # Source the module file
    source "$module_file"

    # Initialize module
    if declare -f module_init >/dev/null; then
        if ! module_init; then
            log_info "Module skipped: $module_name"
            echo "$(date +%s)" > "${DIRS[CHECKPOINTS_DIR]}/${module_name}.skipped"
            return 0  # Return success to continue with other modules
        fi
    fi

    # Start checkpoint
    checkpoint_start "$module_name"

    # Run the module
    if module_run; then
        checkpoint_complete "$module_name"
        echo -e "${GREEN}✓ Module completed: ${module_name}${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Module failed: ${module_name}${NC}"
        # Run cleanup if defined
        if declare -f module_cleanup >/dev/null; then
            module_cleanup
        fi
        return 1
    fi
}

# Check if module should be replayed
should_replay_module() {
    local module=$1
    # Replay if in REPLAY_MODULES list or if it's the FROM_MODULE
    if [[ -n "$REPLAY_MODULES" ]] && [[ ",$REPLAY_MODULES," == *",$module,"* ]]; then
        return 0
    fi
    if [[ -n "$FROM_MODULE" ]] && [[ "$module" == "$FROM_MODULE" ]]; then
        return 0
    fi
    return 1
}