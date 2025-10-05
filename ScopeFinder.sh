#!/bin/bash
# ScopeFinder 2.0 - Modular reconnaissance framework

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/registry.sh"

# Global variables
DOMAIN=""
HTTP_PROXY_URL=""
DRY_RUN=false
REPLAY_MODULES=""
NO_RESUME=false

# Help function
usage() {
    cat << EOF
Usage: ScopeFinder [domain] [options]

Modular domain reconnaissance framework

Options:
    --list-modules            List all available modules
    --status                  Show completion status of each module
    --replay module1,module2  Force re-run specific modules (requires prior run)
    --no-resume              Ignore checkpoints, run everything fresh
    --reset                  Clear all checkpoints
    --proxy URL              HTTP proxy URL for httpx and katana tools only
                             (Use http:// not https://, and Docker host IP 172.17.0.1)
    --dry-run                Show what would be executed
    -h, --help               Show this help

Example:
    ScopeFinder example.com
    ScopeFinder example.com --replay subdomain_enum,port_scan
    ScopeFinder example.com --proxy http://172.17.0.1:8080  # Docker host IP for Burp/ZAP

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list-modules)
                list_all_modules
                exit 0
                ;;
            --status)
                [[ -z "${DOMAIN:-}" ]] && { echo "Error: Domain required for status"; exit 1; }
                init_dirs "$DOMAIN"
                show_module_status
                exit 0
                ;;
            --replay)
                # Check if domain has been run before
                if [[ -n "${DOMAIN:-}" ]]; then
                    init_dirs "$DOMAIN"
                    if [[ ! -d "${DIRS[CHECKPOINTS_DIR]}" ]]; then
                        echo "Error: No previous run found for domain: ${DOMAIN}"
                        echo "Run without --replay first to create initial checkpoints"
                        exit 1
                    fi
                    # Validate that requested modules were completed before
                    IFS=',' read -ra modules_to_replay <<< "$2"
                    for module in "${modules_to_replay[@]}"; do
                        if [[ ! -f "${DIRS[CHECKPOINTS_DIR]}/${module}.done" ]]; then
                            echo "Error: Module '$module' has not been completed yet and cannot be replayed"
                            echo "Use --status to see which modules have been completed"
                            exit 1
                        fi
                    done
                fi
                REPLAY_MODULES="$2"
                shift 2
                ;;
            --no-resume)
                NO_RESUME=true
                shift
                ;;
            --proxy)
                HTTP_PROXY_URL="$2"
                log_info "Proxy configured for httpx and katana only: $HTTP_PROXY_URL"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --reset)
                [[ -z "${DOMAIN:-}" ]] && { echo "Error: Domain required for reset"; exit 1; }
                init_dirs "$DOMAIN"
                reset_checkpoints
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                DOMAIN="$1"
                shift
                ;;
        esac
    done
}

# Validate environment
validate_environment() {
    # Check domain
    if [[ -z "$DOMAIN" ]]; then
        echo "Error: No domain provided"
        usage
        exit 1
    fi

    # Check required environment variables
    local required_vars=(
        "SHODAN_API_KEY"
        "DEHASHED_API_KEY"
        "HUNTERIO_API_KEY"
        "PDCP_API_KEY"
        "URLSCAN_API_KEY"
        "VIRUSTOTAL_API_KEY"
        "WPSCAN_API_KEY"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "Warning: Missing environment variables:"
        printf " - %s\n" "${missing_vars[@]}"
        echo ""
        echo "Some features may not work without these API keys."
        echo "Continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Initialize workspace
init_workspace() {
    log_info "Initializing workspace for domain: $DOMAIN"

    # Create only essential directories (skip ones that modules will create as needed)
    # Skip: WORDPRESS, WORDPRESS_SCANS - created only if WordPress sites found
    # Skip: various ARTIFACTS dirs - created by modules when needed
    for dir_key in "${!DIRS[@]}"; do
        # Skip directories that should be created conditionally by modules
        case "$dir_key" in
            WORDPRESS|WORDPRESS_SCANS|*_ARTIFACTS|*_DATA|*_OUTPUT|*_SCREENSHOT|*_RESPONSE|*_SMAP|JS_*|*_LINKFINDER|*_BURP)
                continue
                ;;
            *)
                mkdir -p "${DIRS[$dir_key]}"
                ;;
        esac
    done

    log_info "Workspace initialized at: ${DIRS[WORK_DIR]}"
}

# Main execution
main() {
    parse_args "$@"

    # Validate environment
    validate_environment

    # Set up environment for domain
    export DOMAIN
    init_dirs "$DOMAIN"

    # Initialize workspace
    if [[ "$DRY_RUN" == "false" ]]; then
        init_workspace
    fi

    # Load and execute modules
    load_all_modules

    local modules_to_run=()
    determine_modules_to_run modules_to_run

    if [[ ${#modules_to_run[@]} -eq 0 ]]; then
        log_info "No modules to run"
        exit 0
    fi

    log_info "Will run ${#modules_to_run[@]} modules"
    echo ""

    # Execute modules
    for module in "${modules_to_run[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "$module - ${MODULE_DESC[$module]:-No description}"
        else
            if ! MODULE "$module"; then
                log_error "Module failed: $module"
                exit 1
            fi
        fi
    done

    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "ScopeFinder completed successfully!"
        log_info "Results available at: ${DIRS[WORK_DIR]}"
    fi
}

# Run main
main "$@"