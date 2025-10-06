#!/bin/bash
# URL extraction from downloaded content

MODULE_NAME="xnLinkFinder_url_extract"
MODULE_DESC="Extract URLs from downloaded content using xnLinkFinder"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS]}"
    mkdir -p "${DIRS[URLS_ARTIFACTS]}"
    mkdir -p "${DIRS[URLS_LINKFINDER]}"
    mkdir -p "${DIRS[XNLINKFINDER]}"
}

module_run() {
    log_info "Extracting URLs from downloaded content"

    # Run xnLinkFinder on waymore data
    if [[ -d "${DIRS[WAYMORE_DATA]}" ]] && command -v xnLinkFinder &> /dev/null; then
        log_info "Running xnLinkFinder on archived data..."
        xnLinkFinder -i "${DIRS[WAYMORE_DATA]}" \
                     -sp "$DOMAIN" -sf "$DOMAIN" \
                     -o "${DIRS[URLS_ARTIFACTS]}/xnLinkFinder_archive_output.txt" \
                     -op "${DIRS[URLS_ARTIFACTS]}/xnLinkFinder_archive_parameters.txt" \
                     -oo "${DIRS[URLS_ARTIFACTS]}/xnLinkFinder_archive_out_of_scope.txt" > /dev/null 2>&1 || true
    fi

    # Run xnLinkFinder on katana data
    if [[ -d "${DIRS[KATANA_DATA]}" ]] && command -v xnLinkFinder &> /dev/null; then
        log_info "Running xnLinkFinder on crawled data..."
        xnLinkFinder -i "${DIRS[KATANA_DATA]}" \
                     -sp "$DOMAIN" -sf "$DOMAIN" \
                     -o "${DIRS[URLS_ARTIFACTS]}/xnLinkFinder_crawl_output.txt" \
                     -op "${DIRS[URLS_ARTIFACTS]}/xnLinkFinder_crawl_parameters.txt" \
                     -oo "${DIRS[URLS_ARTIFACTS]}/xnLinkFinder_crawl_out_of_scope.txt" > /dev/null 2>&1 || true
    fi

    # Combine all xnLinkFinder outputs to linkfinder_output/xnLinkFinder directory
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_output.txt | grep -v 'katana_downloaded_data' > "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}" 2>/dev/null || true
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_parameters.txt > "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_PARAMS]}" 2>/dev/null || true
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_out_of_scope.txt > "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUT_OF_SCOPE]}" 2>/dev/null || true

    # Process xnLinkFinder output - separate URLs without known domains
    if [[ -f "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}" ]]; then
        grep -vE '^https?://' "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}" > "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_DOMAIN_UNKNOWN]}" 2>/dev/null || true
        grep -E '^https?://' "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}" > "${DIRS[XNLINKFINDER]}/temp_xnLinkFinder_output.txt" 2>/dev/null || true
        [[ -f "${DIRS[XNLINKFINDER]}/temp_xnLinkFinder_output.txt" ]] && mv "${DIRS[XNLINKFINDER]}/temp_xnLinkFinder_output.txt" "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}"
    fi

    # Deduplicate all files
    dedupe_file "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}"
    dedupe_file "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_PARAMS]}"
    dedupe_file "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUT_OF_SCOPE]}"
    dedupe_file "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_DOMAIN_UNKNOWN]}"

    # Count results
    local url_count=0
    local param_count=0
    [[ -f "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}" ]] && url_count=$(wc -l < "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}")
    [[ -f "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_PARAMS]}" ]] && param_count=$(wc -l < "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_PARAMS]}")

    log_info "Extracted $url_count URLs and $param_count parameters"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up URL extraction artifacts"
}