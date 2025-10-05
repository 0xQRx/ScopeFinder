#!/bin/bash
# URL extraction from downloaded content

MODULE_NAME="xnLinkFinder_url_extract"
MODULE_DESC="Extract URLs from downloaded content using xnLinkFinder"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS]}"
    mkdir -p "${DIRS[URLS_ARTIFACTS]}"
    mkdir -p "${DIRS[URLS_LINKFINDER]}"
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

    # Combine all xnLinkFinder outputs to linkfinder_output directory
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_output.txt > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt" 2>/dev/null || true
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_parameters.txt > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_parameters.txt" 2>/dev/null || true
    cat "${DIRS[URLS_ARTIFACTS]}"/xnLinkFinder_*_out_of_scope.txt > "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_out_of_scope_urls.txt" 2>/dev/null || true

    # Process xnLinkFinder output - separate URLs without known domains
    if [[ -f "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt" ]]; then
        grep -vE '^https?://' "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt" > "${DIRS[URLS_LINKFINDER]}/domain_not_known_xnLinkFinder_output.txt" 2>/dev/null || true
        grep -E '^https?://' "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt" > "${DIRS[URLS_LINKFINDER]}/temp_xnLinkFinder_output.txt" 2>/dev/null || true
        [[ -f "${DIRS[URLS_LINKFINDER]}/temp_xnLinkFinder_output.txt" ]] && mv "${DIRS[URLS_LINKFINDER]}/temp_xnLinkFinder_output.txt" "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt"
    fi

    # Deduplicate all files
    dedupe_file "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt"
    dedupe_file "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_parameters.txt"
    dedupe_file "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_out_of_scope_urls.txt"
    dedupe_file "${DIRS[URLS_LINKFINDER]}/domain_not_known_xnLinkFinder_output.txt"

    # Extract inline scripts that might have dynamic URLs
    log_info "Extracting inline scripts..."
    mkdir -p "${DIRS[URLS]}/extracted_inline_scripts"
    local output_file="${DIRS[URLS]}/extracted_inline_scripts/scripts.html"
    : > "$output_file"  # Clear previous output

    declare -A seen_hashes  # Deduplication map

    # Folders to scan
    local folders=()
    [[ -d "${DIRS[WAYMORE_DATA]}" ]] && folders+=("${DIRS[WAYMORE_DATA]}")
    [[ -d "${DIRS[KATANA_DATA]}" ]] && folders+=("${DIRS[KATANA_DATA]}")

    for folder in "${folders[@]}"; do
        log_info "Processing folder: $folder"

        for src in "$folder"/*; do
            [[ -f "$src" ]] || continue  # skip if not a file

            while IFS= read -r -d '' block; do
                [[ -z "$block" ]] && continue

                # Hash for deduplication
                local hash=$(printf "%s" "$block" | md5sum | cut -d' ' -f1)
                [[ -n "${seen_hashes[$hash]:-}" ]] && continue
                seen_hashes[$hash]=1

                # Check for behavioral patterns
                printf "%s" "$block" | grep -Pqzi '<script(?![^>]*\bsrc=)[^>]*>(?=[\s\S]*?(fetch\(|\.open\(|new\s+XMLHttpRequest|\.send\(|\$\.ajax\(|\$\.get\(|\$\.post\(|\$\.patch\(|\.sendBeacon\(|new\s+WebSocket|new\s+EventSource|postMessage\(|axios\.|io\(|\.write\())[\s\S]*?</script>' || continue

                # Append to output file
                printf "%s\n\n" "$block" >> "$output_file"
            done < <(grep -Pzo '<script(?![^>]*\bsrc=)[^>]*>[\s\S]*?</script>' "$src" 2>/dev/null)
        done
    done

    # Count results
    local url_count=0
    local param_count=0
    local script_count=0
    [[ -f "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt" ]] && url_count=$(wc -l < "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_output.txt")
    [[ -f "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_parameters.txt" ]] && param_count=$(wc -l < "${DIRS[URLS_LINKFINDER]}/xnLinkFinder_parameters.txt")
    [[ -f "${DIRS[URLS]}/extracted_inline_scripts/scripts.html" ]] && script_count=$(grep -c '<script' "${DIRS[URLS]}/extracted_inline_scripts/scripts.html" 2>/dev/null || echo "0")

    log_info "Extracted $url_count URLs, $param_count parameters, and $script_count inline scripts"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up URL extraction artifacts"
}