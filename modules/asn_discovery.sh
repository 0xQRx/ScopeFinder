#!/bin/bash
# ASN range discovery

MODULE_NAME="asn_discovery"
MODULE_DESC="Discover ASN ranges for the organization using asnmap"

module_init() {
    # Create output directory
    # Fixed paths
    mkdir -p "${DIRS[ASN]}"

    # Extract base domain name
    DOMAIN_BASE_NAME=$(echo "$DOMAIN" | awk -F'.' '{print $(NF-1)}')
}

module_run() {
    log_info "Discovering ASN ranges for: $DOMAIN_BASE_NAME"

    # Run asnmap
    if command -v asnmap &> /dev/null; then
        asnmap -d "$DOMAIN_BASE_NAME" -silent >> "${DIRS[ASN]}/${FILES[ASN_RANGES]}" 2>/dev/null || true
    else
        log_warn "asnmap not found - skipping ASN discovery"
        return 0
    fi

    # Count results
    local range_count=0
    [[ -f "${DIRS[ASN]}/${FILES[ASN_RANGES]}" ]] && range_count=$(wc -l < "${DIRS[ASN]}/${FILES[ASN_RANGES]}")

    if [[ "$range_count" -eq 0 ]]; then
        log_info "No ASN ranges found for $DOMAIN_BASE_NAME"
    else
        log_info "Found $range_count ASN IP ranges"
    fi

    return 0
}

module_cleanup() {
    log_debug "Cleaning up ASN discovery artifacts"
}