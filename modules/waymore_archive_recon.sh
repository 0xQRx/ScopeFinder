#!/bin/bash
# URL collection from web archives

MODULE_NAME="waymore_archive_recon"
MODULE_DESC="Collect URLs from web archives using waymore"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS]}"
    mkdir -p "${DIRS[URLS_ARTIFACTS]}"
    mkdir -p "${DIRS[WAYMORE_DATA]}"
}

module_run() {
    log_info "Collecting URLs from web archives for: $DOMAIN"

    # Check for waymore
    if ! command -v waymore &> /dev/null; then
        log_warn "waymore not found - skipping archive collection"
        return 0
    fi

    # Run waymore - download archives to waymore_data directory
    log_info "Running waymore (this may take several hours)..."
    waymore -i "$DOMAIN" -mode B -f \
            -oU "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}" \
            -url-filename \
            -oR "${DIRS[WAYMORE_DATA]}" > /dev/null 2>&1 || true

    # Deduplicate URLs
    dedupe_file "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}"

    # Separate URLs with and without parameters
    if [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}" ]]; then
        grep -oP 'https?://[^\s"]+\?[^\s"]*' "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}" > "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITH_PARAMS]}" 2>/dev/null || true
        grep -oP 'https?://[^\s"]+' "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}" | grep -v '\?' > "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITHOUT_PARAMS]}" 2>/dev/null || true

        dedupe_file "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITH_PARAMS]}"
        dedupe_file "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITHOUT_PARAMS]}"
    fi

    # Count results
    local total_urls=0
    local with_params=0
    local without_params=0
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}" ]] && total_urls=$(wc -l < "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}")
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITH_PARAMS]}" ]] && with_params=$(wc -l < "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITH_PARAMS]}")
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITHOUT_PARAMS]}" ]] && without_params=$(wc -l < "${DIRS[URLS_ARTIFACTS]}/${FILES[WAYMORE_URLS_WITHOUT_PARAMS]}")

    log_info "Collected $total_urls total URLs ($with_params with params, $without_params without)"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up URL archive artifacts"
}