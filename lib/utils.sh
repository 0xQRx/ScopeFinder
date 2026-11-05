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

# Name of the module currently executing, set by the MODULE wrapper so that
# warnings and errors can be attributed to the module that produced them.
CURRENT_MODULE=""

# Record a warning/error against the current module (best-effort, never fails
# the caller even under 'set -e'). Each module's issues accumulate in a
# <module>.warnings file inside the checkpoints dir, which --status, the
# end-of-run aggregate, and summary.json all read. This is what turns the
# pervasive "|| true / 2>/dev/null" swallowing into something visible: a tool
# that warns (or a module that notices empty output) leaves a durable trace
# instead of silently checkpointing as a clean "completed".
_record_issue() {
    local level="$1"; shift
    local dir="${DIRS[CHECKPOINTS_DIR]:-}"
    [[ -n "$dir" && -d "$dir" ]] || return 0
    printf '[%s] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$level" "$*" \
        >> "${dir}/${CURRENT_MODULE:-_main}.warnings" 2>/dev/null || true
    return 0
}

log_error() {
    echo -e "${DIM}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${RED}[ERROR]${NC} $*" >&2
    _record_issue ERROR "$*"
}

log_warn() {
    echo -e "${DIM}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW}[WARN]${NC} $*"
    _record_issue WARN "$*"
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

# Pick a browser User-Agent for curl-based probing and store it in the global
# SELECTED_UA. The stock curl/<ver> UA is a common WAF/CDN block trigger, so
# target-facing curl calls send one of these real browser UAs instead, rotated
# across calls. Export a single HTTP_USER_AGENT to force one UA instead.
#
# This sets a variable rather than echoing on purpose: callers use it as
#   pick_user_agent; curl -A "$SELECTED_UA" ...
# NOT as "$(pick_user_agent)". Command substitution forks a subshell that inherits
# the parent's $RANDOM seed, so an echo-based picker returns the SAME index every
# call and never rotates. Running in the parent shell lets $RANDOM advance normally.
SELECTED_UA=""
pick_user_agent() {
    if [[ -n "${HTTP_USER_AGENT:-}" ]]; then
        SELECTED_UA="$HTTP_USER_AGENT"
        return
    fi
    # Re-declare locally since indexed arrays can't be exported to subprocesses
    local -a uas=(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:152.0) Gecko/20100101 Firefox/152.0"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"
    )
    SELECTED_UA="${uas[RANDOM % ${#uas[@]}]}"
}

# File operations
check_file() {
    local file=$1
    [[ -f "$file" && -s "$file" ]]
}

# Assert that a step produced output. If the expected file is missing or empty,
# emit a recorded warning (so it surfaces at run end) and return non-zero so the
# caller can branch. Use this after a tool that is expected to produce results
# to catch silent crashes that would otherwise checkpoint as a clean completion.
check_output() {
    local file=$1
    local label="${2:-$(basename "$file")}"
    if [[ ! -s "$file" ]]; then
        log_warn "${label}: produced no output (missing or empty: ${file})"
        return 1
    fi
    return 0
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

    # Attribute any warnings/errors emitted below to this module, and clear any
    # stale record from a previous run so the count reflects only this run.
    CURRENT_MODULE="$module_name"
    rm -f "${DIRS[CHECKPOINTS_DIR]}/${module_name}.warnings"

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
        local warn_rec="${DIRS[CHECKPOINTS_DIR]}/${module_name}.warnings"
        if [[ -s "$warn_rec" ]]; then
            local warn_n
            warn_n=$(grep -c . "$warn_rec" 2>/dev/null || echo 0)
            echo -e "${YELLOW}⚠ Module completed with ${warn_n} warning(s)/error(s): ${module_name}${NC}"
            echo -e "${DIM}  (details: ${warn_rec})${NC}"
        else
            echo -e "${GREEN}✓ Module completed: ${module_name}${NC}"
        fi
        CURRENT_MODULE=""
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