#!/bin/bash
# Shodan IP and certificate search

MODULE_NAME="shodan_search"
MODULE_DESC="Search Shodan for IPs and certificates using Shodan API"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[SHODAN]}"
    mkdir -p "${DIRS[SHODAN_ARTIFACTS]}"

    # Check for API key
    if [[ -z "${SHODAN_API_KEY:-}" ]]; then
        log_error "SHODAN_API_KEY not set - skipping Shodan search"
        return 1
    fi
}

module_run() {
    log_info "Running Shodan searches for: $DOMAIN"

    # URL encode the domain
    local encoded_domain=$(jq -rn --arg d "$DOMAIN" '$d|@uri')

    # Search by SSL certificate subject CN
    log_info "Searching by SSL certificate..."
    curl -s "https://api.shodan.io/shodan/host/search?key=${SHODAN_API_KEY}&query=ssl.cert.subject.cn:${encoded_domain}" \
        > "${DIRS[SHODAN_ARTIFACTS]}/shodan_ssl_subject_raw.json"

    # Extract IPs from SSL cert results
    jq -r '.matches[] | "\(.ip_str):\(.port)/\(.transport)"' "${DIRS[SHODAN_ARTIFACTS]}/shodan_ssl_subject_raw.json" \
        > "${DIRS[SHODAN]}/${FILES[IPS_FROM_SSL]}" 2>/dev/null || true

    # Extract organizations
    jq -r '.matches[] | .org // "UNKNOWN"' "${DIRS[SHODAN_ARTIFACTS]}/shodan_ssl_subject_raw.json" | \
        sort -u > "${DIRS[SHODAN]}/${FILES[ORGS_LIST]}" 2>/dev/null || true

    # Interactive org selection (skip in non-interactive mode)
    if [[ -t 0 ]] && [[ -f "${DIRS[SHODAN]}/${FILES[ORGS_LIST]}" ]] && [[ -s "${DIRS[SHODAN]}/${FILES[ORGS_LIST]}" ]]; then
        echo ""
        log_info "Discovered organizations:"
        mapfile -t ORG_LIST < "${DIRS[SHODAN]}/${FILES[ORGS_LIST]}"

        echo "0) Skip organization scan"
        for i in "${!ORG_LIST[@]}"; do
            printf "%d) %s\n" "$((i+1))" "${ORG_LIST[$i]}"
        done

        echo ""
        read -p "Select an organization to scan (0 to skip): " CHOICE

        if [[ "$CHOICE" != "0" ]] && [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
            local ORG="${ORG_LIST[$((CHOICE - 1))]}"
            if [[ -n "$ORG" ]]; then
                log_info "Searching for organization: $ORG"

                # URL encode the organization
                local encoded_org=$(jq -rn --arg org "$ORG" '$org|@uri')

                # Search by organization
                curl -s "https://api.shodan.io/shodan/host/search?key=${SHODAN_API_KEY}&query=org:\"${encoded_org}\"" \
                    > "${DIRS[SHODAN_ARTIFACTS]}/shodan_org_raw.json"

                # Extract IPs from org results
                jq -r '.matches[] | "\(.ip_str):\(.port)/\(.transport)"' "${DIRS[SHODAN_ARTIFACTS]}/shodan_org_raw.json" \
                    > "${DIRS[SHODAN]}/${FILES[IPS_FROM_ORG]}" 2>/dev/null || true

                echo "$ORG" > "${DIRS[SHODAN]}/${FILES[SELECTED_ORG]}"
            fi
        else
            log_info "Skipping organization scan"
        fi
    fi

    # Combine and deduplicate IPs
    cat "${DIRS[SHODAN]}"/${FILES[IPS_FROM_SSL]} "${DIRS[SHODAN]}"/${FILES[IPS_FROM_ORG]} 2>/dev/null | sort -u > "${DIRS[SHODAN]}/${FILES[ALL_SHODAN_IPS]}" || true

    local ip_count=0
    [[ -f "${DIRS[SHODAN]}/${FILES[ALL_SHODAN_IPS]}" ]] && ip_count=$(wc -l < "${DIRS[SHODAN]}/${FILES[ALL_SHODAN_IPS]}")
    log_info "Found $ip_count unique IP:port combinations"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up Shodan search artifacts"
}