#!/bin/bash
# Extract inline scripts with dynamic URL patterns

MODULE_NAME="extracted_inline_scripts"
MODULE_DESC="Extract inline scripts that might have dynamic URLs"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS]}/extracted_inline_scripts"
}

module_run() {
    log_info "Extracting inline scripts with dynamic URL patterns"

    local output_file="${DIRS[URLS]}/extracted_inline_scripts/scripts.html"
    : > "$output_file"  # Clear previous output

    declare -A seen_hashes  # Deduplication map

    # Folders to scan
    local folders=()
    [[ -d "${DIRS[WAYMORE_DATA]}" ]] && folders+=("${DIRS[WAYMORE_DATA]}")
    [[ -d "${DIRS[KATANA_DATA]}" ]] && folders+=("${DIRS[KATANA_DATA]}")

    if [[ ${#folders[@]} -eq 0 ]]; then
        log_warn "No downloaded data found to extract inline scripts from"
        return 0
    fi

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

                # Check for behavioral patterns - expanded patterns for more API methods
                printf "%s" "$block" | grep -Pqzi '<script(?![^>]*\bsrc=)[^>]*>(?=[\s\S]*?(fetch\(|\.open\(|new\s+XMLHttpRequest|\.send\(|\$\.ajax\(|\$\.get\(|\$\.post\(|\$\.patch\(|\$\.put\(|\$\.delete\(|\.get\("|\.post\("|\.put\("|\.patch\("|\.delete\("|\.request\(|\.sendBeacon\(|new\s+WebSocket|new\s+EventSource|postMessage\(|axios\.|axios\(|io\(|\.write\(|\.emit\(|\.subscribe\(|\.publish\(|http\.request\(|https\.request\(|superagent\.|request\(|got\(|node-fetch|ky\(|cross-fetch|unfetch\(|isomorphic-fetch|graphql\(|apollo|relay|urql|swr\(|useQuery\(|useMutation\(|useLazyQuery\(|api\(|apiCall\(|apiRequest\(|makeRequest\(|doRequest\(|sendRequest\(|httpClient\.|restClient\.|graphqlClient\.|websocketClient\.|socketClient\.)[\s\S]*?</script>' || continue

                # Append to output file
                printf "%s\n\n" "$block" >> "$output_file"
            done < <(grep -Pzo '<script(?![^>]*\bsrc=)[^>]*>[\s\S]*?</script>' "$src" 2>/dev/null)
        done
    done

    # Count results
    local script_count=0
    [[ -f "$output_file" ]] && script_count=$(grep -c '<script' "$output_file" 2>/dev/null || echo "0")

    log_info "Extracted $script_count inline scripts with dynamic URL patterns"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up inline script extraction artifacts"
}