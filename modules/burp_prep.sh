#!/bin/bash
# Burp Suite preparation and parameter fuzzing

MODULE_NAME="burp_prep"
MODULE_DESC="Prepare URLs for Burp Suite and parameter fuzzing using urldedup and x8"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS_BURP]}"

    # Get live URLs from dedup step
    LIVE_URLS="${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}"
}

module_run() {
    log_info "Preparing URLs for Burp Suite"

    if ! check_file "$LIVE_URLS"; then
        log_info "No live URLs with parameters found"
        return 0
    fi

    # Run urldedup if available
    if command -v urldedup &> /dev/null; then
        log_info "Running urldedup for Burp preparation..."

        urldedup -f "$LIVE_URLS" \
                 -ignore "css,js,png,jpg,jpeg,gif,svg,woff,woff2,ttf,eot,otf,ico,webp,mp4,pdf" \
                 -examples 1 \
                 -validate \
                 -t 20 \
                 -out-burp "${DIRS[URLS_BURP]}/${FILES[BURP_URLS]}" \
                 -out-burp-gap "${DIRS[URLS_BURP]}/${FILES[BURP_GAP_URLS]}" 2>/dev/null || true
    else
        log_warn "urldedup not found - creating basic Burp files"
        # Fallback: just copy the live URLs
        cp "$LIVE_URLS" "${DIRS[URLS_BURP]}/${FILES[BURP_URLS]}"
        touch "${DIRS[URLS_BURP]}/${FILES[BURP_GAP_URLS]}"
    fi

    # Parameter fuzzing with x8
    if command -v x8 &> /dev/null && [[ -f "${DIRS[URLS_BURP]}/${FILES[BURP_URLS]}" || -f "${DIRS[URLS_BURP]}/${FILES[BURP_GAP_URLS]}" ]]; then
        log_info "Running x8 for parameter discovery..."

        # Combine Burp URLs for fuzzing
        cat "${DIRS[URLS_BURP]}/${FILES[BURP_GAP_URLS]}" "${DIRS[URLS_BURP]}/${FILES[BURP_URLS]}" > "${DIRS[URLS_BURP]}/fuzz_params_urls.txt" 2>/dev/null || true

        if [[ -s "${DIRS[URLS_BURP]}/fuzz_params_urls.txt" ]] && [[ -f "/wordlists/burp-parameter-names.txt" ]]; then
            x8 -u "${DIRS[URLS_BURP]}/fuzz_params_urls.txt" \
               -w "/wordlists/burp-parameter-names.txt" \
               --one-worker-per-host \
               -W2 \
               -O url \
               -o "${DIRS[URLS_BURP]}/${FILES[BURP_X8_URLS]}" \
               --remove-empty > /dev/null 2>&1 || true

            rm -f "${DIRS[URLS_BURP]}/fuzz_params_urls.txt"
        else
            log_warn "Skipping x8 - missing input files or wordlist"
        fi
    else
        log_warn "x8 not found or no URLs to fuzz"
    fi

    # Count results
    local burp_count=0
    local gap_count=0
    local x8_count=0
    [[ -f "${DIRS[URLS_BURP]}/${FILES[BURP_URLS]}" ]] && burp_count=$(wc -l < "${DIRS[URLS_BURP]}/${FILES[BURP_URLS]}")
    [[ -f "${DIRS[URLS_BURP]}/${FILES[BURP_GAP_URLS]}" ]] && gap_count=$(wc -l < "${DIRS[URLS_BURP]}/${FILES[BURP_GAP_URLS]}")
    [[ -f "${DIRS[URLS_BURP]}/${FILES[BURP_X8_URLS]}" ]] && x8_count=$(wc -l < "${DIRS[URLS_BURP]}/${FILES[BURP_X8_URLS]}")

    log_info "Prepared $burp_count Burp URLs, $gap_count GAP URLs, and found $x8_count URLs with custom params"

    return 0
}

module_cleanup() {
    rm -f "${DIRS[URLS_BURP]}/fuzz_params_urls.txt"
    log_debug "Cleaning up Burp preparation artifacts"
}