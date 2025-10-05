#!/bin/bash
# Port scanning with smap

MODULE_NAME="smap_port_scan"
MODULE_DESC="Scan ports on discovered hosts using smap"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[SCANS]}"
    mkdir -p "${DIRS[SCANS_SMAP]}"

    # Get input from subdomain enumeration
    SUBDOMAINS_FILE="${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS]}"

    if ! check_file "$SUBDOMAINS_FILE"; then
        log_warn "No subdomains found, creating empty file"
        touch "$SUBDOMAINS_FILE"
    fi
}

module_run() {
    log_info "Scanning ports on discovered hosts"

    local input_count=$(wc -l < "$SUBDOMAINS_FILE" 2>/dev/null || echo "0")
    log_info "Scanning $input_count hosts..."

    if [[ "$input_count" -gt 0 ]]; then
        # Run smap
        smap -iL "$SUBDOMAINS_FILE" -oA "${DIRS[SCANS_SMAP]}/open_ports" 2>/dev/null || true

        # Extract web servers
        if [[ -f "${DIRS[SCANS_SMAP]}/open_ports.gnmap" ]]; then
            grep -E "443|80" "${DIRS[SCANS_SMAP]}/open_ports.gnmap" | \
                awk '/Host:/ {if ($3 ~ /\(/) {print $2, $3} else {print $2, "(No domain)"}}' | \
                sed 's/[()]//g' > "${DIRS[SCANS]}/${FILES[WEB_SERVERS]}" || true
        fi

        # Also extract all IPs
        if [[ -f "${DIRS[SCANS_SMAP]}/open_ports.gnmap" ]]; then
            grep "Host:" "${DIRS[SCANS_SMAP]}/open_ports.gnmap" | \
                awk '{print $2}' | sort -u > "${DIRS[SCANS]}/ips.txt" || true
        fi
    else
        log_warn "No hosts to scan"
        touch "${DIRS[SCANS]}/${FILES[WEB_SERVERS]}"
    fi

    # Count results
    local server_count=0
    [[ -f "${DIRS[SCANS]}/${FILES[WEB_SERVERS]}" ]] && server_count=$(wc -l < "${DIRS[SCANS]}/${FILES[WEB_SERVERS]}")
    log_info "Found $server_count web servers"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up port scan artifacts"
}