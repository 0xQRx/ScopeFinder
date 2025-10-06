#!/bin/bash
# Service probing with httpx

MODULE_NAME="httpx_subdomain_probe"
MODULE_DESC="Probe services and take screenshots using httpx"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[HTTPX]}"
    mkdir -p "${DIRS[HTTPX_OUTPUT]}"
    mkdir -p "${DIRS[HTTPX_RESPONSE]}"
    mkdir -p "${DIRS[HTTPX_SCREENSHOT]}"

    # Get subdomains from subdomain enumeration
    SUBDOMAINS_FILE="${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS]}"

    if ! check_file "$SUBDOMAINS_FILE"; then
        log_error "No subdomains found from subdomain enumeration"
        return 1
    fi
}

module_run() {
    log_info "Probing services with httpx"

    local input_count=$(wc -l < "$SUBDOMAINS_FILE")
    log_info "Probing $input_count subdomains..."

    # Get proxy flag
    local proxy_flag=$(get_proxy_flag "httpx")

    # Debug: Log proxy configuration
    if [[ -n "$proxy_flag" ]]; then
        log_info "Using proxy for httpx: $proxy_flag"
    else
        log_debug "No proxy configured for httpx (HTTP_PROXY_URL='$HTTP_PROXY_URL')"
    fi

    # Run httpx - filter out Burp proxy error pages
    httpx -status-code -title -tech-detect \
          -list "$SUBDOMAINS_FILE" \
          -sid 10 -ss -fr \
          -fs "Burp Suite" \
          -o "${DIRS[HTTPX]}/${FILES[HTTPX_OUTPUT]}" \
          -no-color $proxy_flag > /dev/null 2>&1 || true

    # Move screenshots and responses if they exist
    if [[ -d "output/screenshot" ]]; then
        mv output/screenshot/* "${DIRS[HTTPX_SCREENSHOT]}/" 2>/dev/null || true
    fi
    if [[ -d "output/response" ]]; then
        mv output/response/* "${DIRS[HTTPX_RESPONSE]}/" 2>/dev/null || true
    fi
    [[ -d "output" ]] && rm -rf output

    # Extract subdomains based on response status
    if [[ -f "${DIRS[HTTPX]}/${FILES[HTTPX_OUTPUT]}" ]]; then
        # Clear output files
        > "${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS_200]}"
        > "${DIRS[SUBDOMAINS]}/${FILES[REDIRECTED_TO_SUBDOMAINS]}"
        > "${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"

        # Filter out any Burp Suite proxy error pages that might have slipped through
        grep -E '\[.*\]' "${DIRS[HTTPX]}/${FILES[HTTPX_OUTPUT]}" | grep -v "Burp Suite" | while read -r line; do
            # Extract original URL and subdomain
            original_url=$(echo "$line" | awk '{print $1}')
            original_subdomain=$(echo "$original_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

            # Skip if not in our domain
            if [[ ! "$original_subdomain" == "$DOMAIN" && ! "$original_subdomain" == *.$DOMAIN ]]; then
                continue
            fi

            # Add to live_subdomains.txt (all responsive subdomains)
            echo "$original_subdomain" >> "${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"

            # Extract status codes
            status_codes=$(echo "$line" | grep -oP '\[\K[^\]]+(?=\])' | head -n1)

            if [[ "$status_codes" =~ (^|,)30[0-9](,|$) ]]; then
                # Check if it's a redirect
                final_url=$(echo "$line" | grep -oP '\[https?://[^\]]+\]' | tail -n1 | tr -d '[]')
                if [[ -n "$final_url" ]]; then
                    final_subdomain=$(echo "$final_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

                    if [[ "$final_subdomain" == "$DOMAIN" || "$final_subdomain" == *.$DOMAIN ]]; then
                        # Redirected but still in our domain - add to 200_subdomains.txt
                        echo "$final_subdomain" >> "${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS_200]}"
                    else
                        # Redirected to external domain - add mapping to redirected_to_subdomains.txt
                        echo "$original_subdomain -> $final_subdomain" >> "${DIRS[SUBDOMAINS]}/${FILES[REDIRECTED_TO_SUBDOMAINS]}"
                    fi
                fi
            elif [[ "$status_codes" == "200" ]]; then
                # Direct 200 response (no redirect) - add to 200_subdomains.txt
                echo "$original_subdomain" >> "${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS_200]}"
            fi
            # If it's 404, 500, etc., it's only in live_subdomains.txt
        done

        # Deduplicate files
        sort -u "${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS_200]}" -o "${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS_200]}"
        sort -u "${DIRS[SUBDOMAINS]}/${FILES[REDIRECTED_TO_SUBDOMAINS]}" -o "${DIRS[SUBDOMAINS]}/${FILES[REDIRECTED_TO_SUBDOMAINS]}"
        sort -u "${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}" -o "${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"

        # Extract WordPress sites only if found
        if grep -qiE '\[.*wordpress.*\]' "${DIRS[HTTPX]}/${FILES[HTTPX_OUTPUT]}" 2>/dev/null; then
            mkdir -p "${DIRS[WORDPRESS]}"
            grep -iE '\[.*wordpress.*\]' "${DIRS[HTTPX]}/${FILES[HTTPX_OUTPUT]}" | \
                awk '{print $1}' | sort -u > "${DIRS[WORDPRESS]}/${FILES[WORDPRESS_SITES]}" || true
        fi
    fi

    # Count results
    local live_count=0
    local wp_count=0
    [[ -f "${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}" ]] && live_count=$(wc -l < "${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}")
    [[ -f "${DIRS[WORDPRESS]}/${FILES[WORDPRESS_SITES]}" ]] && wp_count=$(wc -l < "${DIRS[WORDPRESS]}/${FILES[WORDPRESS_SITES]}")

    log_info "Found $live_count live subdomains, including $wp_count WordPress sites"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up service probe artifacts"
    [[ -d "output" ]] && rm -rf output
}