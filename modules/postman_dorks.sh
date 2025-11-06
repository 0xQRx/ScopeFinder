#!/bin/bash
# Generate Postman Dorks with clickable links

MODULE_NAME="postman_dorks"
MODULE_DESC="Generate Postman dork links for API collection search"

module_init() {
    # Create output directory
    mkdir -p "${DIRS[DORKS]}"
}

module_run() {
    log_info "Generating Postman dorks for: $DOMAIN"

    # Output file
    local output_file="${DIRS[DORKS]}/postman_dorks.md"

    # Clear previous results
    > "$output_file"

    # Add authentication notice at the top
    echo "# Postman Dorks" >> "$output_file"
    echo "" >> "$output_file"
    echo "**Note: You need to be authenticated to Postman to use these searches**" >> "$output_file"
    echo "" >> "$output_file"

    # URL encode function
    url_encode() {
        local string="${1}"
        echo -n "$string" | sed 's/ /%20/g; s/|/%7C/g; s/:/%3A/g; s/"/%22/g; s/\[/%5B/g; s/\]/%5D/g; s/&/%26/g'
    }

    # Function to generate Postman dork link
    generate_postman_dork() {
        local title="$1"
        local query="$2"
        local encoded_query=$(url_encode "$query")
        echo "### $title" >> "$output_file"
        echo "$query" >> "$output_file"
        echo "https://postman.co/search?q=$encoded_query&type=all&workspaceType=all&isPrivateNetworkActive=false" >> "$output_file"
        echo "" >> "$output_file"
    }

    # Extract domain name without TLD (e.g., tesla.com -> tesla)
    local domain_without_tld="${DOMAIN%%.*}"

    # Generate Postman dorks with full domain and domain name without TLD

    generate_postman_dork "Search for full domain" \
        "$DOMAIN"

    generate_postman_dork "Search for domain name without TLD" \
        "$domain_without_tld"

    # Count total dorks generated
    local dork_count=$(grep -c "^###" "$output_file")
    log_info "Generated $dork_count Postman dork queries"
    log_info "Results saved to: $output_file"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up Postman dorks generator artifacts"
}
