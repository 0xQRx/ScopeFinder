#!/bin/bash
# JavaScript analysis with linkfinder

MODULE_NAME="linkfinder_analysis"
MODULE_DESC="Find links in files with linkfinder & xnLinkFinder"

module_init() {
    # Get JS files from download step
    JS_DIR="${DIRS[JS_DOWNLOADED]}"

    if ! [[ -d "$JS_DIR" ]] || [[ -z "$(ls -A "$JS_DIR" 2>/dev/null)" ]]; then
        log_info "No JavaScript files found from previous step - skipping JS analysis"
        return 1  # Return non-zero to skip module_run
    fi

    # Create output directories only if we have JS files to analyze
    mkdir -p "${DIRS[URLS_LINKFINDER]}"
    mkdir -p "${DIRS[URLS_LINKFINDER]}/xnLinkFinder"
}

module_run() {
    log_info "Analyzing JavaScript files"

    local js_count=$(find "$JS_DIR" -name "*.js" -type f | wc -l)
    log_info "Analyzing $js_count JavaScript files..."

    # Run linkfinder
    if command -v linkfinder &> /dev/null; then
        log_info "Running linkfinder..."
        linkfinder -i "$JS_DIR" \
                   --out-dir "${DIRS[URLS_LINKFINDER]}" \
                   --unknown-domain "${DIRS[URLS_LINKFINDER]}/unknown_domain_urls.txt" > /dev/null 2>&1 || true

        # Process linkfinder output files
        for file in "${DIRS[URLS_LINKFINDER]}"/*.txt; do
            [[ -f "$file" ]] && dedupe_file "$file"
        done
    else
        log_warn "linkfinder not found - skipping JavaScript link analysis"
    fi

    # Run additional xnLinkFinder on JS files
    if command -v xnLinkFinder &> /dev/null; then
        log_info "Running xnLinkFinder on JavaScript files..."
        xnLinkFinder -i "$JS_DIR" \
                     -sp "$DOMAIN" -sf "$DOMAIN" \
                     -o "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_js_output.txt" \
                     -op "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_js_parameters.txt" \
                     -oo "${DIRS[URLS_LINKFINDER]}/xnLinkFinder/xnLinkFinder_js_out_of_scope_urls.txt" > /dev/null 2>&1 || true

        # Deduplicate xnLinkFinder files
        for file in "${DIRS[URLS_LINKFINDER]}/xnLinkFinder"/*.txt; do
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

    # Update latest symlink

    return 0
}

module_cleanup() {
    log_debug "Cleaning up JavaScript analysis artifacts"
}