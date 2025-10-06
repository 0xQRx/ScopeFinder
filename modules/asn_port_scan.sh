#!/bin/bash
# ASN expansion - scan and enumerate discovered ASN ranges

MODULE_NAME="asn_port_scan"
MODULE_DESC="Expand reconnaissance to ASN ranges using smap"

module_init() {
    # Create output directory
    # Fixed paths
    mkdir -p "${DIRS[ASN]}"

    # Get ASN ranges from previous step
    
    ASN_RANGES="${DIRS[ASN]}/${FILES[ASN_RANGES]}"

    if ! check_file "$ASN_RANGES"; then
        log_warn "No ASN ranges found from previous step"
        return 1
    fi
}

module_run() {
    local range_count=$(wc -l < "$ASN_RANGES")
    log_info "Expanding reconnaissance to $range_count ASN ranges"

    # Port scanning with smap on ASN ranges
    log_info "Scanning ports on ASN ranges..."
    mkdir -p "${DIRS[ASN_SMAP]}"
    smap -iL "$ASN_RANGES" -oA "${DIRS[ASN_SMAP]}/open_ports" 2>/dev/null || true

    # Extract web servers from ASN scan
    if [[ -f "${DIRS[ASN_SMAP]}/open_ports.gnmap" ]]; then
        grep -E "443|80" "${DIRS[ASN_SMAP]}/open_ports.gnmap" | \
            awk '/Host:/ {if ($3 ~ /\(/) {print $2, $3} else {print $2, "(No domain)"}}' | \
            sed 's/[()]//g' > "${DIRS[ASN]}/${FILES[ASN_WEBSERVERS]}" || true
    fi

    # Count results
    local server_count=0
    [[ -f "${DIRS[ASN]}/${FILES[ASN_WEBSERVERS]}" ]] && server_count=$(wc -l < "${DIRS[ASN]}/${FILES[ASN_WEBSERVERS]}")
    log_info "Found $server_count web servers in ASN ranges"

    # Update latest symlink

    return 0
}

module_cleanup() {
    log_debug "Cleaning up ASN expansion artifacts"
}