#!/bin/bash
# Generate Docker Hub Dorks with clickable links

MODULE_NAME="dockerhub_dorks"
MODULE_DESC="Generate Docker Hub dork links for container search"

module_init() {
    # Create output directory
    mkdir -p "${DIRS[DORKS]}"
}

module_run() {
    log_info "Generating Docker Hub dorks for: $DOMAIN"

    # Output file
    local output_file="${DIRS[DORKS]}/dockerhub_dorks.md"

    # Clear previous results
    > "$output_file"

    # URL encode function
    url_encode() {
        local string="${1}"
        echo -n "$string" | sed 's/ /%20/g; s/|/%7C/g; s/:/%3A/g; s/"/%22/g; s/\[/%5B/g; s/\]/%5D/g; s/&/%26/g'
    }

    # Function to generate Docker Hub dork link
    generate_dockerhub_dork() {
        local title="$1"
        local query="$2"
        local encoded_query=$(url_encode "$query")
        echo "### $title" >> "$output_file"
        echo "$query" >> "$output_file"
        echo "https://hub.docker.com/search?q=$encoded_query" >> "$output_file"
        echo "" >> "$output_file"
    }

    # Extract domain name without TLD (e.g., tesla.com -> tesla)
    local domain_without_tld="${DOMAIN%%.*}"

    # Generate Docker Hub dorks with full domain and domain name without TLD

    generate_dockerhub_dork "Search for full domain" \
        "$DOMAIN"

    generate_dockerhub_dork "Search for domain name without TLD" \
        "$domain_without_tld"

    # Count total dorks generated
    local dork_count=$(grep -c "^###" "$output_file")
    log_info "Generated $dork_count Docker Hub dork queries"
    log_info "Results saved to: $output_file"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up Docker Hub dorks generator artifacts"
}
