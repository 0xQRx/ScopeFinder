#!/bin/bash
# WordPress vulnerability scanning

MODULE_NAME="wordpress_scan"
MODULE_DESC="Scan WordPress sites for vulnerabilities using WPScan"

module_init() {
    # Get WordPress sites from service probe step
    WP_SITES="${DIRS[WORDPRESS]}/${FILES[WORDPRESS_SITES]}"

    if ! check_file "$WP_SITES"; then
        log_info "No WordPress sites found from previous step - skipping WordPress scanning"
        return 1  # Return non-zero to skip module_run
    fi

    # Only create directories if WordPress sites exist
    mkdir -p "${DIRS[WORDPRESS]}"
    mkdir -p "${DIRS[WORDPRESS_SCANS]}"
}

module_run() {
    # Double-check that we have WordPress sites
    if ! check_file "$WP_SITES"; then
        return 0  # Skip gracefully
    fi

    local site_count=$(wc -l < "$WP_SITES")
    log_info "Scanning $site_count WordPress sites with WPScan..."

    if ! command -v wpscan &> /dev/null; then
        log_warn "wpscan not found - skipping WordPress scanning"
        return 0
    fi

    if [[ -z "${WPSCAN_API_KEY:-}" ]]; then
        log_warn "WPSCAN_API_KEY not set - running without vulnerability database"
    fi

    # Scan each WordPress site
    while read -r SUBDOMAIN; do
        local output_file="${DIRS[WORDPRESS_SCANS]}/wpscan_$(echo "$SUBDOMAIN" | sed 's|https\?://||g; s|/|_|g').txt"
        log_info "Scanning: $SUBDOMAIN"

        wpscan -t 1 \
               --api-token="${WPSCAN_API_KEY:-}" \
               --enumerate vp,vt,u \
               --connect-timeout 10 \
               --request-timeout 30 \
               --stealthy \
               --throttle 700 \
               -o "$output_file" \
               -f cli-no-color \
               --disable-tls-checks \
               --update \
               --url "$SUBDOMAIN" 2>/dev/null || true
    done < "$WP_SITES"

    # Count scan results
    local scan_count=$(find "${DIRS[WORDPRESS_SCANS]}" -name "*.txt" -type f | wc -l)
    log_info "Completed $scan_count WordPress scans"

    # Check for vulnerabilities
    if grep -r "vulnerabilit" "${DIRS[WORDPRESS_SCANS]}/" 2>/dev/null | grep -qi "identified"; then
        log_warn "⚠️  WordPress vulnerabilities found! Check results in: ${DIRS[WORDPRESS_SCANS]}/"
    fi

    return 0
}

module_cleanup() {
    log_debug "Cleaning up WordPress scan artifacts"
}