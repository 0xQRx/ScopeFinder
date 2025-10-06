#!/bin/bash
# URL extraction from downloaded content

MODULE_NAME="xnLinkFinder_url_extract"
MODULE_DESC="Extract URLs from downloaded content using xnLinkFinder"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS]}"
    mkdir -p "${DIRS[URLS_ARTIFACTS]}"
    mkdir -p "${DIRS[URLS_LINKFINDER]}"
    mkdir -p "${DIRS[URLS_LINKFINDER]}/xnLinkFinder"
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
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_output.txt | grep -v 'katana_downloaded_data' > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt" 2>/dev/null || true
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_parameters.txt > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_parameters.txt" 2>/dev/null || true
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_out_of_scope.txt > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_out_of_scope_urls.txt" 2>/dev/null || true

    # Process xnLinkFinder output - separate URLs without known domains
    if [[ -f "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt" ]]; then
        grep -vE '^https?://' "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt" > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/domain_not_known_xnLinkFinder_output.txt" 2>/dev/null || true
        grep -E '^https?://' "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt" > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/temp_xnLinkFinder_output.txt" 2>/dev/null || true
        [[ -f "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/temp_xnLinkFinder_output.txt" ]] && mv "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/temp_xnLinkFinder_output.txt" "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt"
    fi

    # Deduplicate all files
    dedupe_file "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt"
    dedupe_file "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_parameters.txt"
    dedupe_file "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_out_of_scope_urls.txt"
    dedupe_file "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/domain_not_known_xnLinkFinder_output.txt"

    # Count results
    local url_count=0
    local param_count=0
    [[ -f "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt" ]] && url_count=$(wc -l < "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_output.txt")
    [[ -f "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_parameters.txt" ]] && param_count=$(wc -l < "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_parameters.txt")

    log_info "Extracted $url_count URLs and $param_count parameters"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up URL extraction artifacts"
}