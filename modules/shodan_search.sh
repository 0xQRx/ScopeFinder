#!/bin/bash
# Shodan IP and certificate search

MODULE_NAME="shodan_search"
MODULE_DESC="Search Shodan for IPs and certificates using Shodan API"

# Return the most frequently occurring org across the SSL search matches.
# The most common org is the most likely true owner of the certificate set,
# which makes a better unattended auto-pick than an alphabetical first entry.
# Emits only the org name on stdout (nothing else) so it is safe in $(...).
_shodan_most_common_org() {
    local raw="$1"
    [[ -s "$raw" ]] || return 0
    jq -r '.matches[]? | .org // empty' "$raw" 2>/dev/null \
        | sed '/^[[:space:]]*$/d' \
        | sort | uniq -c | sort -rn | head -n1 \
        | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//'
}

# Decide what to do when nobody picks an org (prompt timed out, or the run is
# non-interactive with no SHODAN_ORG override). Prints the chosen org name on
# stdout, or nothing to skip. Logs go to stderr so they don't pollute $(...).
_shodan_timeout_default() {
    local mode="$1" raw="$2"
    case "${mode,,}" in
        auto)
            local org
            org="$(_shodan_most_common_org "$raw")"
            if [[ -n "$org" ]]; then
                log_info "No organization selected - auto-selecting most common org: $org" >&2
                printf '%s\n' "$org"
            else
                log_info "No organization selected and none to auto-pick - skipping org scan" >&2
            fi
            ;;
        *)
            log_info "No organization selected - skipping organization scan" >&2
            ;;
    esac
}

# Run a Shodan search for a specific organization and record the results.
_shodan_scan_org() {
    local org="$1"
    log_info "Searching Shodan for organization: $org"

    # URL encode the organization
    local encoded_org
    encoded_org=$(jq -rn --arg org "$org" '$org|@uri')

    # Search by organization
    curl -s "https://api.shodan.io/shodan/host/search?key=${SHODAN_API_KEY}&query=org:\"${encoded_org}\"" \
        > "${DIRS[SHODAN_ARTIFACTS]}/shodan_org_raw.json"

    # Extract IPs from org results
    jq -r '.matches[] | "\(.ip_str):\(.port)/\(.transport)"' "${DIRS[SHODAN_ARTIFACTS]}/shodan_org_raw.json" \
        > "${DIRS[SHODAN]}/${FILES[IPS_FROM_ORG]}" 2>/dev/null || true

    printf '%s\n' "$org" > "${DIRS[SHODAN]}/${FILES[SELECTED_ORG]}"
}

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
    local encoded_domain
    encoded_domain=$(jq -rn --arg d "$DOMAIN" '$d|@uri')

    # Search by SSL certificate subject CN
    log_info "Searching by SSL certificate..."
    local ssl_raw="${DIRS[SHODAN_ARTIFACTS]}/shodan_ssl_subject_raw.json"
    curl -s "https://api.shodan.io/shodan/host/search?key=${SHODAN_API_KEY}&query=ssl.cert.subject.cn:${encoded_domain}" \
        > "$ssl_raw"

    # Extract IPs from SSL cert results
    jq -r '.matches[] | "\(.ip_str):\(.port)/\(.transport)"' "$ssl_raw" \
        > "${DIRS[SHODAN]}/${FILES[IPS_FROM_SSL]}" 2>/dev/null || true

    # Extract organizations
    jq -r '.matches[] | .org // "UNKNOWN"' "$ssl_raw" | \
        sort -u > "${DIRS[SHODAN]}/${FILES[ORGS_LIST]}" 2>/dev/null || true

    # ------------------------------------------------------------------
    # Decide which organization (if any) to scan, WITHOUT blocking an
    # unattended run forever. Precedence:
    #   1. SHODAN_ORG set to a name  -> scan that org, no prompt
    #   2. SHODAN_ORG=skip|none|no   -> explicitly skip the org scan
    #   3. SHODAN_ORG=auto           -> auto-pick the most common org
    #   4. interactive TTY           -> prompt with a timeout, then fall
    #                                   back to SHODAN_ORG_ON_TIMEOUT
    #   5. non-interactive, no var   -> SHODAN_ORG_ON_TIMEOUT immediately
    # ------------------------------------------------------------------
    local orgs_file="${DIRS[SHODAN]}/${FILES[ORGS_LIST]}"
    local prompt_timeout="${SHODAN_ORG_TIMEOUT:-30}"
    local on_timeout="${SHODAN_ORG_ON_TIMEOUT:-skip}"
    local selected_org=""

    if [[ -n "${SHODAN_ORG:-}" ]]; then
        case "${SHODAN_ORG,,}" in
            skip|none|no)
                log_info "SHODAN_ORG=${SHODAN_ORG} - skipping organization scan"
                ;;
            auto)
                selected_org="$(_shodan_most_common_org "$ssl_raw")"
                if [[ -n "$selected_org" ]]; then
                    log_info "SHODAN_ORG=auto - selected most common org: $selected_org"
                else
                    log_info "SHODAN_ORG=auto - no organizations discovered to scan"
                fi
                ;;
            *)
                selected_org="$SHODAN_ORG"
                log_info "SHODAN_ORG set - scanning organization: $selected_org"
                ;;
        esac
    elif [[ -s "$orgs_file" ]]; then
        if [[ -t 0 ]]; then
            # Interactive: present the menu but never block indefinitely.
            echo ""
            log_info "Discovered organizations:"
            mapfile -t ORG_LIST < "$orgs_file"
            echo "0) Skip organization scan"
            local i
            for i in "${!ORG_LIST[@]}"; do
                printf "%d) %s\n" "$((i+1))" "${ORG_LIST[$i]}"
            done
            echo ""

            local CHOICE=""
            # read -t returns non-zero on timeout/EOF; guard it so set -e
            # does not abort the module when the prompt times out.
            if read -t "$prompt_timeout" -r \
                -p "Select an organization to scan (0 to skip) [${prompt_timeout}s timeout]: " CHOICE; then
                if [[ "$CHOICE" != "0" && "$CHOICE" =~ ^[0-9]+$ ]]; then
                    selected_org="${ORG_LIST[$((CHOICE - 1))]:-}"
                    [[ -z "$selected_org" ]] && log_warn "Invalid selection: $CHOICE - skipping org scan"
                else
                    log_info "Skipping organization scan"
                fi
            else
                echo ""
                log_info "No input after ${prompt_timeout}s - applying default (${on_timeout})"
                selected_org="$(_shodan_timeout_default "$on_timeout" "$ssl_raw")"
            fi
        else
            # Non-interactive with no override: take the default action now
            # instead of silently dead-ending the org scan.
            selected_org="$(_shodan_timeout_default "$on_timeout" "$ssl_raw")"
        fi
    fi

    if [[ -n "$selected_org" ]]; then
        _shodan_scan_org "$selected_org"
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
