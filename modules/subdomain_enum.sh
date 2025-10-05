#!/bin/bash
# Subdomain enumeration from multiple sources

MODULE_NAME="subdomain_enum"
MODULE_DESC="Enumerate subdomains using subfinder, godigger, crtsh-tool, and shosubgo"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[SUBDOMAINS]}"

    # Set up output files
    SUBDOMAINS_FILE="${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS]}"
    WILDCARD_FILE="${DIRS[SUBDOMAINS]}/${FILES[WILDCARD_SUBDOMAINS]}"
}

module_run() {
    log_info "Enumerating subdomains for: $DOMAIN"

    # Run subfinder
    log_info "Running subfinder..."
    subfinder -d "$DOMAIN" -all -recursive -silent >> "$SUBDOMAINS_FILE" 2>/dev/null || true

    # Run godigger
    log_info "Running godigger..."
    godigger -domain "$DOMAIN" -search subdomains -t 20 >> "$SUBDOMAINS_FILE" 2>/dev/null || true

    # Run crtsh-tool
    log_info "Running crtsh-tool..."
    crtsh_tool_output=$(crtsh-tool --domain "$DOMAIN" 2>/dev/null || true)
    echo "$crtsh_tool_output" | grep -v '[DEBUG]' | grep -v '\*\.' >> "$SUBDOMAINS_FILE" || true
    echo "$crtsh_tool_output" | grep -v '[DEBUG]' | grep '\*\.' >> "$WILDCARD_FILE" || true

    # Run shosubgo
    log_info "Running shosubgo..."
    if [[ -n "${SHODAN_API_KEY:-}" ]]; then
        shosubgo_output=$(shosubgo -d "$DOMAIN" -s "$SHODAN_API_KEY" 2>/dev/null || true)
        echo "$shosubgo_output" | grep -v 'No subdomains found' | grep -v 'apishodan.JsonSubDomain' | grep -v '\*\.' >> "$SUBDOMAINS_FILE" || true
        echo "$shosubgo_output" | grep '\*\.' >> "$WILDCARD_FILE" || true
    else
        log_warn "Skipping shosubgo - SHODAN_API_KEY not set"
    fi

    # Deduplicate and sort
    log_info "Deduplicating results..."
    dedupe_file "$SUBDOMAINS_FILE"
    dedupe_file "$WILDCARD_FILE"

    # Count results
    local sub_count=0
    local wild_count=0
    [[ -f "$SUBDOMAINS_FILE" ]] && sub_count=$(wc -l < "$SUBDOMAINS_FILE")
    [[ -f "$WILDCARD_FILE" ]] && wild_count=$(wc -l < "$WILDCARD_FILE")

    log_info "Found $sub_count subdomains and $wild_count wildcard entries"

    return 0
}

module_cleanup() {
    # Cleanup on failure
    log_debug "Cleaning up subdomain enumeration artifacts"
}