#!/bin/bash
# IP address discovery from various sources

MODULE_NAME="ip_discovery"
MODULE_DESC="Discover IP addresses using godigger (AlienVault, Common Crawl, urlscan.io, VirusTotal, WebArchive)"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[SCANS]}"
}

module_run() {
    log_info "Discovering IP addresses for: $DOMAIN"

    # Run godigger for IP discovery
    if command -v godigger &> /dev/null; then
        log_info "Running godigger for IP discovery..."
        godigger -domain "$DOMAIN" -search ips -t 20 > "${DIRS[SCANS]}/${FILES[IPS_FROM_SOURCES]}" 2>/dev/null || true
        dedupe_file "${DIRS[SCANS]}/${FILES[IPS_FROM_SOURCES]}"
    else
        log_warn "godigger not found - skipping IP discovery"
    fi

    # Count results
    local ip_count=0
    [[ -f "${DIRS[SCANS]}/${FILES[IPS_FROM_SOURCES]}" ]] && ip_count=$(wc -l < "${DIRS[SCANS]}/${FILES[IPS_FROM_SOURCES]}")
    log_info "Found $ip_count IP addresses from open sources"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up IP discovery artifacts"
}