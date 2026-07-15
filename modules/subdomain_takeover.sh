#!/bin/bash
# Subdomain takeover detection with nuclei (takeover-tagged templates)

MODULE_NAME="subdomain_takeover"
MODULE_DESC="Check enumerated subdomains for takeover vulnerabilities using nuclei"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[SUBDOMAIN_TAKEOVER]}"

    # Get input from subdomain enumeration (all enumerated subdomains, not
    # just live ones - a dangling/takeover-able DNS record often won't
    # respond as "live" through normal httpx probing)
    SUBDOMAINS_FILE="${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS]}"

    if ! check_file "$SUBDOMAINS_FILE"; then
        log_warn "No subdomains found, creating empty file"
        touch "$SUBDOMAINS_FILE"
    fi
}

module_run() {
    log_info "Checking for subdomain takeover vulnerabilities"

    local input_count=$(wc -l < "$SUBDOMAINS_FILE" 2>/dev/null || echo "0")
    local results_file="${DIRS[SUBDOMAIN_TAKEOVER]}/${FILES[TAKEOVER_RESULTS]}"

    if [[ "$input_count" -gt 0 ]]; then
        log_info "Scanning $input_count hosts with nuclei (takeover templates)..."

        # Keep templates current before scanning
        nuclei -update-templates -silent -nc \
            >/dev/null 2>>"${DIRS[SUBDOMAIN_TAKEOVER]}/nuclei.err" || true

        # Run nuclei against all enumerated subdomains, tagged for takeover checks
        nuclei -l "$SUBDOMAINS_FILE" \
               -tags takeover \
               -o "$results_file" \
               -silent -nc \
               >/dev/null 2>>"${DIRS[SUBDOMAIN_TAKEOVER]}/nuclei.err" || true

        [[ -s "${DIRS[SUBDOMAIN_TAKEOVER]}/nuclei.err" ]] || rm -f "${DIRS[SUBDOMAIN_TAKEOVER]}/nuclei.err"
    else
        log_warn "No subdomains to scan"
        touch "$results_file"
    fi

    # Count results
    local finding_count=0
    [[ -f "$results_file" ]] && finding_count=$(grep -c . "$results_file" 2>/dev/null || echo "0")
    log_info "Found $finding_count potential subdomain takeover findings"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up subdomain takeover artifacts"
}
