#!/bin/bash
# JavaScript analysis with linkfinder

MODULE_NAME="linkfinder_analysis"
MODULE_DESC="Find links in files with linkfinder & xnLinkFinder"

module_init() {
    # Collect all directories that contain JS/response files to analyze.
    # downloaded_js_files/ — explicitly fetched .js files (via js_download)
    # katana_downloaded_data/ — raw responses stored by katana -sr, includes
    #   JS fetched via scroll-triggered or dynamically injected requests that
    #   never made it into the httpx probe list and therefore missed js_download.
    declare -ga JS_DIRS=()
    [[ -d "${DIRS[JS_DOWNLOADED]}" ]] && [[ -n "$(ls -A "${DIRS[JS_DOWNLOADED]}" 2>/dev/null)" ]] && \
        JS_DIRS+=("${DIRS[JS_DOWNLOADED]}")
    [[ -d "${DIRS[KATANA_DATA]}" ]] && [[ -n "$(ls -A "${DIRS[KATANA_DATA]}" 2>/dev/null)" ]] && \
        JS_DIRS+=("${DIRS[KATANA_DATA]}")

    if [[ ${#JS_DIRS[@]} -eq 0 ]]; then
        log_info "No JavaScript files found from previous steps - skipping JS analysis"
        return 1
    fi

    mkdir -p "${DIRS[URLS_LINKFINDER]}"
    mkdir -p "${DIRS[XNLINKFINDER]}"
}

module_run() {
    log_info "Analyzing JavaScript files"

    local js_count=0
    for dir in "${JS_DIRS[@]}"; do
        js_count=$((js_count + $(find "$dir" -type f | wc -l)))
    done
    log_info "Analyzing $js_count files across ${#JS_DIRS[@]} source(s): ${JS_DIRS[*]}"

    # Run linkfinder against each source directory
    if command -v linkfinder &> /dev/null; then
        log_info "Running linkfinder..."
        for dir in "${JS_DIRS[@]}"; do
            linkfinder -i "$dir" \
                       --out-dir "${DIRS[URLS_LINKFINDER]}" \
                       --unknown-domain "${DIRS[URLS_LINKFINDER]}/${FILES[LINKFINDER_UNKNOWN_DOMAINS]}" > /dev/null 2>&1 || true
        done

        for file in "${DIRS[URLS_LINKFINDER]}"/*.txt; do
            [[ -f "$file" ]] && dedupe_file "$file"
        done
    else
        log_warn "linkfinder not found - skipping JavaScript link analysis"
    fi

    # Run xnLinkFinder against each source directory
    if command -v xnLinkFinder &> /dev/null; then
        log_info "Running xnLinkFinder on JavaScript files..."
        for dir in "${JS_DIRS[@]}"; do
            xnLinkFinder -i "$dir" \
                         -sp "$DOMAIN" -sf "$DOMAIN" \
                         -o "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_JS_OUTPUT]}" \
                         -op "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_JS_PARAMS]}" \
                         -oo "${DIRS[XNLINKFINDER]}/${FILES[XNLINKFINDER_JS_OUT_OF_SCOPE]}" > /dev/null 2>&1 || true
        done

        for file in "${DIRS[XNLINKFINDER]}"/*.txt; do
            [[ -f "$file" ]] && dedupe_file "$file"
        done
    fi

    # Count results
    local found_files=$(find "${DIRS[URLS_LINKFINDER]}" -name "*.txt" -type f | wc -l)
    local total_urls=0
    for file in "${DIRS[URLS_LINKFINDER]}"/*.txt; do
        [[ -f "$file" ]] && total_urls=$((total_urls + $(wc -l < "$file")))
    done

    log_info "Found $total_urls URLs/endpoints across $found_files output files"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up JavaScript analysis artifacts"
}