#!/bin/bash
# Parameter analysis and extraction

MODULE_NAME="extract_params"
MODULE_DESC="Extract URL parameters"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[PARAMETERS]}"
    mkdir -p "${DIRS[URLS_ARTIFACTS]}"

    # Collect URLs from multiple sources
    TEMP_URLS="${DIRS[URLS_ARTIFACTS]}/all_urls_temp.txt"
    > "$TEMP_URLS"

    # Get URLs from archive step
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}" ]] && cat "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}" >> "$TEMP_URLS"

    # Get URLs from crawl step
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}" ]] && cat "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}" >> "$TEMP_URLS"

    # Get URLs from extraction step
    [[ -f "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}" ]] && cat "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_OUTPUT]}" >> "$TEMP_URLS"
}

module_run() {
    log_info "Analyzing URL parameters"

    # Extract URLs with parameters
    grep -oP 'https?://[^\s"]+\?[^\s"]*' "$TEMP_URLS" > "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS]}" 2>/dev/null || true

    # Extract URLs without parameters
    grep -oP 'https?://[^\s"]+' "$TEMP_URLS" | grep -v '\?' > "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS]}" 2>/dev/null || true

    # Deduplicate
    dedupe_file "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS]}"
    dedupe_file "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS]}"

    # Use uro for unique URLs
    if command -v uro &> /dev/null; then
        log_info "Deduplicating URLs with uro..."
        uro -i "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS]}" > "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS_UNIQ]}" 2>/dev/null || true
        uro -i "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS]}" > "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS_UNIQ]}" 2>/dev/null || true
    else
        cp "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS]}" "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS_UNIQ]}"
        cp "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS]}" "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS_UNIQ]}"
    fi

    # Extract all unique parameters
    log_info "Extracting unique parameters..."
    grep -hoP 'https?://[^\s"<>]+?\?[^\s"<>]*' "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS_UNIQ]}" | \
        sed -E 's/.*\?//' | tr '&' '\n' | sed -E 's/=.*//' | \
        sort -u > "${DIRS[PARAMETERS]}/${FILES[PARAMETERS]}" 2>/dev/null || true

    # Count results
    local with_params=0
    local without_params=0
    local param_count=0
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS_UNIQ]}" ]] && with_params=$(wc -l < "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS_UNIQ]}")
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS_UNIQ]}" ]] && without_params=$(wc -l < "${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS_UNIQ]}")
    [[ -f "${DIRS[PARAMETERS]}/${FILES[PARAMETERS]}" ]] && param_count=$(wc -l < "${DIRS[PARAMETERS]}/${FILES[PARAMETERS]}")

    log_info "Found $with_params unique URLs with params, $without_params without params, and $param_count unique parameters"

    # Clean up temp file
    rm -f "$TEMP_URLS"

    return 0
}

module_cleanup() {
    rm -f "${DIRS[URLS_ARTIFACTS]}/all_urls_temp.txt"
    log_debug "Cleaning up parameter analysis artifacts"
}