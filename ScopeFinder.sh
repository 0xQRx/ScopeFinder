#!/bin/bash
# ScopeFinder 2.0 - Modular reconnaissance framework

set -euo pipefail

# Handle Ctrl+C to exit immediately
trap 'echo -e "\n\nInterrupted by user. Exiting..."; exit 130' SIGINT SIGTERM

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
FROM_MODULE=""
FRESH_RUN=false
APP_MODE=false

# Help function
usage() {
    cat << EOF
Usage: ScopeFinder [domain] [options]

Modular domain reconnaissance framework

Options:
    --list-modules            List all available modules
    --status                  Show completion status of each module
    --replay module1,module2  Force re-run specific modules (requires prior run)
    --replay-from module      Start execution from specified module onwards
    --fresh                  Clear all checkpoints and run everything from scratch
    --app                    Application-layer-only mode: run just the app-layer
                             modules (web crawl, JS/URL extraction, GraphQL/API
                             docs, WordPress, dork generators) and skip all
                             network/DNS discovery and infrastructure/port/ASN
                             enumeration. The supplied host IS the target.
    --proxy URL              HTTP proxy URL for httpx and katana tools only
                             (Use http:// not https://, and Docker host IP 172.17.0.1)
    --dry-run                Show what would be executed
    -h, --help               Show this help

Example:
    ScopeFinder example.com
    ScopeFinder www.example.com --app                        # app-layer only, this host
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
            --replay-from)
                FROM_MODULE="$2"
                shift 2
                ;;
            --fresh)
                [[ -z "${DOMAIN:-}" ]] && { echo "Error: Domain required for --fresh"; exit 1; }
                FRESH_RUN=true
                shift
                ;;
            --app)
                APP_MODE=true
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
                # Always normalize the domain to lowercase - hostnames are
                # case-insensitive and downstream tools/dedup treat differing
                # cases as distinct entries otherwise.
                DOMAIN="${1,,}"
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

# Seed the application target for --app mode.
#
# The app-layer modules (katana, graphql_probe, api_docs_probe, wordpress_scan,
# and the URL/JS chain downstream of them) consume a live-host list that is
# normally produced by subdomain enumeration + httpx probing - both of which are
# network-layer and skipped in --app mode. In --app mode the supplied host IS the
# application target, so seed those inputs directly from it.
#
# The target host is appended if missing (never clobbering a list left by a prior
# full run), so --app works both standalone and layered on top of an earlier scan.
seed_app_targets() {
    # Derive a bare host even if a scheme/path slipped into the argument.
    local host="${DOMAIN#http://}"
    host="${host#https://}"
    host="${host%%/*}"
    [[ -n "$host" ]] || { log_warn "[--app] Could not derive a target host from '$DOMAIN'"; return 0; }

    mkdir -p "${DIRS[SUBDOMAINS]}"
    local subs="${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS]}"
    local live="${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"

    # live_subdomains.txt / subdomains.txt: bare hostnames (format the app
    # modules expect). Append-if-missing so prior-run data is preserved.
    local f
    for f in "$live" "$subs"; do
        if [[ ! -f "$f" ]] || ! grep -qxF "$host" "$f" 2>/dev/null; then
            printf '%s\n' "$host" >> "$f"
            sort -u "$f" -o "$f" 2>/dev/null || true
        fi
    done

    # wordpress_scan reads a URL list and skips when it is absent; seed the
    # target as a URL so WPScan evaluates it (it self-detects non-WordPress
    # targets and exits without a finding).
    mkdir -p "${DIRS[WORDPRESS]}"
    local wp="${DIRS[WORDPRESS]}/${FILES[WORDPRESS_SITES]}"
    local wp_url="https://${host}"
    if [[ ! -f "$wp" ]] || ! grep -qxF "$wp_url" "$wp" 2>/dev/null; then
        printf '%s\n' "$wp_url" >> "$wp"
        sort -u "$wp" -o "$wp" 2>/dev/null || true
    fi

    log_info "[--app] Application target seeded: $host"
}

# Main execution
main() {
    parse_args "$@"

    # Validate environment
    validate_environment

    # Set up environment for domain
    export DOMAIN
    init_dirs "$DOMAIN"

    # Handle fresh run - clear checkpoints before proceeding
    if [[ "$FRESH_RUN" == "true" ]]; then
        log_info "Fresh run requested - clearing all checkpoints"
        reset_checkpoints
    fi

    # Handle replay-from - clear checkpoints from specified module onwards
    if [[ -n "$FROM_MODULE" ]]; then
        log_info "Clearing checkpoints from $FROM_MODULE onwards"
        # Load modules to get the order
        load_all_modules
        local found=false
        for module in "${MODULES_ORDER[@]}"; do
            if [[ "$module" == "$FROM_MODULE" ]]; then
                found=true
            fi
            if [[ "$found" == "true" ]]; then
                rm -f "${DIRS[CHECKPOINTS_DIR]}/${module}.done"
                rm -f "${DIRS[CHECKPOINTS_DIR]}/${module}.skipped"
                rm -f "${DIRS[CHECKPOINTS_DIR]}/${module}.start"
            fi
        done
    fi

    # Initialize workspace
    if [[ "$DRY_RUN" == "false" ]]; then
        init_workspace
        # In --app mode the supplied host IS the application target; seed the
        # live-host inputs the app modules expect (normally produced by the
        # network-layer subdomain enum + httpx probe, which --app skips).
        if [[ "$APP_MODE" == "true" ]]; then
            seed_app_targets
        fi
    fi

    # Load and execute modules
    load_all_modules

    local modules_to_run=()
    determine_modules_to_run modules_to_run

    # Application-layer-only mode: drop the network/infra modules, keeping just
    # the app-layer chain. Applies on top of normal/replay/from selection.
    if [[ "$APP_MODE" == "true" ]]; then
        filter_app_modules modules_to_run
        log_info "[--app] Application-layer-only mode: network/infrastructure modules excluded"
    fi

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
        # Aggregate any warnings/errors recorded by modules during this run so
        # problems that were previously swallowed by "|| true / 2>/dev/null"
        # are visible at a glance instead of buried in per-module output.
        local total_warn mods_with
        total_warn=$(cat "${DIRS[CHECKPOINTS_DIR]}"/*.warnings 2>/dev/null | grep -c . || echo 0)
        mods_with=$(find "${DIRS[CHECKPOINTS_DIR]}" -name '*.warnings' -size +0c 2>/dev/null | wc -l | tr -d ' ')
        if [[ "${total_warn:-0}" -gt 0 ]]; then
            echo -e "${YELLOW}⚠ Run completed with ${total_warn} warning(s)/error(s) across ${mods_with} module(s).${NC}"
            echo -e "${DIM}  Review with: ScopeFinder ${DOMAIN} --status   (details in ${DIRS[CHECKPOINTS_DIR]}/*.warnings)${NC}"
        fi

        log_info "ScopeFinder completed successfully!"
        log_info "Results available at: ${DIRS[WORK_DIR]}"
    fi
}

# Run main
main "$@"