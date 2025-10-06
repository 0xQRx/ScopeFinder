#!/bin/bash
# URL deduplication and live probing

MODULE_NAME="httpx_url_probe"
MODULE_DESC="Deduplicate URLs and probe for live endpoints using httpx"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS]}"
    mkdir -p "${DIRS[URLS_ARTIFACTS]}"

    # Get URLs from parameter analysis
    URLS_WITH="${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS_UNIQ]}"
    URLS_WITHOUT="${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS_UNIQ]}"
}

# Function to filter in-scope URLs
filter_in_scope_urls() {
    local input_file="$1"

    # If the file doesn't exist, just return silently
    if [[ ! -f "$input_file" ]]; then
        log_warn "File not found: $input_file"
        return 0
    fi

    # Filter out Burp Suite proxy error pages
    grep -E '\[.*200.*\]' "$input_file" 2>/dev/null | grep -v "Burp Suite" | while read -r line; do
        # Extract original URL and host
        local original_url=$(echo "$line" | awk '{print $1}')
        local original_host=$(echo "$original_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

        # Extract status codes
        local status_codes=$(echo "$line" | grep -oP '\[\K[^\]]+(?=\])' | head -n1)

        if [[ "$status_codes" =~ (^|,)200(,|$) ]]; then
            if [[ "$original_host" == "$DOMAIN" || "$original_host" == *.$DOMAIN ]]; then
                echo "$original_url"
            fi
        else
            # Extract final redirected URL
            local final_url=$(echo "$line" | grep -oP '\[https?://[^\]]+\]' | tail -n1 | tr -d '[]')
            local final_host=$(echo "$final_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

            if [[ "$original_host" == "$DOMAIN" || "$original_host" == *.$DOMAIN ]]; then
                if [[ "$final_host" == "$DOMAIN" || "$final_host" == *.$DOMAIN ]]; then
                    echo "$final_url"
                fi
            fi
        fi
    done | sort -u
}

module_run() {
    log_info "Deduplicating and probing URLs"

    # Get proxy flag
    local proxy_flag=$(get_proxy_flag "httpx")

    # Probe URLs with parameters
    if check_file "$URLS_WITH"; then
        local with_count=$(wc -l < "$URLS_WITH")
        log_info "Probing $with_count URLs with parameters..."

        httpx -status-code -list "$URLS_WITH" -fr -no-color \
              -fs "Burp Suite" \
              -o "${DIRS[URLS_ARTIFACTS]}/httpx_live_links_with_params_output.txt" \
              $proxy_flag > /dev/null 2>&1 || true

        # Filter in-scope live URLs
        filter_in_scope_urls "${DIRS[URLS_ARTIFACTS]}/httpx_live_links_with_params_output.txt" | \
            grep -oP 'https?://[^\s"]+\?[^\s"]*' | \
            grep -Ev '\.js(\?.*)?$' > "${DIRS[URLS]}/live_urls_with_params_temp.txt" 2>/dev/null || true

        # Final deduplication
        if command -v uro &> /dev/null; then
            uro -i "${DIRS[URLS]}/live_urls_with_params_temp.txt" > "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}" 2>/dev/null || true
        else
            dedupe_file "${DIRS[URLS]}/live_urls_with_params_temp.txt"
            mv "${DIRS[URLS]}/live_urls_with_params_temp.txt" "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}"
        fi
    fi

    # Probe URLs without parameters
    if check_file "$URLS_WITHOUT"; then
        local without_count=$(wc -l < "$URLS_WITHOUT")
        log_info "Probing $without_count URLs without parameters..."

        httpx -status-code -list "$URLS_WITHOUT" -fr -no-color \
              -fs "Burp Suite" \
              -o "${DIRS[URLS_ARTIFACTS]}/httpx_live_links_without_params_output.txt" \
              $proxy_flag > /dev/null 2>&1 || true

        # Filter in-scope live URLs
        filter_in_scope_urls "${DIRS[URLS_ARTIFACTS]}/httpx_live_links_without_params_output.txt" | \
            grep -v '\?' > "${DIRS[URLS]}/live_urls_without_params_temp.txt" 2>/dev/null || true

        # Also check for URLs with params from without-params probing
        filter_in_scope_urls "${DIRS[URLS_ARTIFACTS]}/httpx_live_links_without_params_output.txt" | \
            grep -oP 'https?://[^\s"]+\?[^\s"]*' | \
            grep -Ev '\.js(\?.*)?$' >> "${DIRS[URLS]}/live_urls_with_params_temp2.txt" 2>/dev/null || true

        # Final deduplication
        if command -v uro &> /dev/null; then
            uro -i "${DIRS[URLS]}/live_urls_without_params_temp.txt" > "${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}" 2>/dev/null || true
            [[ -f "${DIRS[URLS]}/live_urls_with_params_temp2.txt" ]] && \
                uro -i "${DIRS[URLS]}/live_urls_with_params_temp2.txt" >> "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}" 2>/dev/null || true
        else
            dedupe_file "${DIRS[URLS]}/live_urls_without_params_temp.txt"
            mv "${DIRS[URLS]}/live_urls_without_params_temp.txt" "${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}"
        fi
    fi

    # Final deduplication of live URLs
    dedupe_file "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}"
    dedupe_file "${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}"

    # Count results
    local live_with=0
    local live_without=0
    [[ -f "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}" ]] && live_with=$(wc -l < "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}")
    [[ -f "${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}" ]] && live_without=$(wc -l < "${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}")

    log_info "Found $live_with live URLs with params and $live_without without params"

    # Clean up temp files
    rm -f "${DIRS[URLS]}"/live_urls_*_temp*.txt

    return 0
}

module_cleanup() {
    rm -f "${DIRS[URLS]}"/live_urls_*_temp*.txt
    log_debug "Cleaning up URL deduplication artifacts"
}