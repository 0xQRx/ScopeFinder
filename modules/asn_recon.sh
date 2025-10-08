#!/bin/bash
# ASN reconnaissance using SSL certificate analysis

MODULE_NAME="asn_recon"
MODULE_DESC="Analyze ASN SSL certificates using CloudRecon and probe with httpx"

module_init() {
    # Get ASN ranges from previous step
    ASN_RANGES="${DIRS[ASN]}/${FILES[ASN_RANGES]}"

    if ! check_file "$ASN_RANGES"; then
        log_info "No ASN ranges available for SSL certificate analysis"
        return 1  # Skip module if no ASN ranges or file is empty
    fi

    # Create output directory
    mkdir -p "${DIRS[ASN]}"
    mkdir -p "${DIRS[ASN]}/artifacts"
    mkdir -p "${DIRS[ASN]}/tld_domains_recon"

    # Extract base domain name
    DOMAIN_BASE_NAME=$(echo "$DOMAIN" | awk -F'.' '{print $(NF-1)}')
}

module_run() {

    # Run CloudRecon to obtain SSL Certificate information
    if command -v CloudRecon &> /dev/null; then
        log_info "Scraping SSL Certificate data using CloudRecon..."
        CloudRecon scrape -i "$ASN_RANGES" -j >> "${DIRS[ASN]}/artifacts/${FILES[CLOUDRECON_RAW]}" 2>/dev/null || true
    else
        log_warn "CloudRecon not found - skipping SSL certificate analysis"
        return 0
    fi

    # Process CloudRecon data
    if [[ -f "${DIRS[ASN]}/artifacts/${FILES[CLOUDRECON_RAW]}" ]] && [[ -s "${DIRS[ASN]}/artifacts/${FILES[CLOUDRECON_RAW]}" ]]; then
        log_info "Processing SSL certificate data..."

        # Ensure the output file for TLDs is clean
        > "${DIRS[ASN]}/tld_domains_recon/${FILES[TOP_LEVEL_DOMAINS]}"

        # Extract commonName and categorize by TLD
        cat "${DIRS[ASN]}/artifacts/${FILES[CLOUDRECON_RAW]}" | jq -r '.commonName' | while read -r common_name; do
            # Extract top-level domain from commonName
            top_level_domain=$(echo "$common_name" | awk -F'.' '{print $(NF-1)"."$NF}')

            # Add the TLD to the unique TLD file
            echo "$top_level_domain" >> "${DIRS[ASN]}/tld_domains_recon/${FILES[TOP_LEVEL_DOMAINS]}"

            # Create the directory for the TLD if it doesn't already exist
            local tld_dir="${DIRS[ASN]}/tld_domains_recon/${top_level_domain}"
            if [[ ! -d "$tld_dir" ]]; then
                mkdir -p "$tld_dir"
            fi

            # Check if it has a wildcard and output accordingly
            if [[ "$common_name" == \** ]]; then
                echo "$common_name" >> "${tld_dir}/wildcard_subdomains.txt"
            else
                echo "$common_name" | sed 's/\*\.//' >> "${tld_dir}/subdomains.txt"
            fi

            # Extract SAN entries and append to the appropriate file
            jq -r '.san | split(",")[]' "${DIRS[ASN]}/artifacts/${FILES[CLOUDRECON_RAW]}" | \
                sed 's/^\s*//;s/\s*$//' | grep -v '\*\.' | grep "$top_level_domain" >> "${tld_dir}/subdomains.txt" 2>/dev/null || true
        done

        # Ensure each subdomain file has unique and sorted entries
        for dir in "${DIRS[ASN]}/tld_domains_recon"/*/; do
            # Check for and process subdomain files
            if [[ -f "${dir}subdomains.txt" ]]; then
                sort -u "${dir}subdomains.txt" -o "${dir}subdomains.txt"
            fi
            if [[ -f "${dir}wildcard_subdomains.txt" ]]; then
                sort -u "${dir}wildcard_subdomains.txt" -o "${dir}wildcard_subdomains.txt"
            fi
        done

        # Ensure top-level domains are unique and sorted
        sort -u "${DIRS[ASN]}/tld_domains_recon/${FILES[TOP_LEVEL_DOMAINS]}" -o "${DIRS[ASN]}/tld_domains_recon/${FILES[TOP_LEVEL_DOMAINS]}"

        # Run httpx on discovered subdomains
        for dir in "${DIRS[ASN]}/tld_domains_recon"/*/; do
            if [[ -f "${dir}subdomains.txt" ]]; then
                # Get directory name
                local dirname=$(basename "$dir")
                log_info "Running httpx for domain: $dirname"

                # Create httpx output directory
                mkdir -p "${dir}/httpx"

                # Get proxy flag
                local proxy_flag=$(get_proxy_flag "httpx")

                # Run httpx against subdomains (with -fr flag to avoid following redirects outside scope)
                httpx -status-code -title -tech-detect \
                      -list "${dir}subdomains.txt" \
                      -sid 10 -ss -fr \
                      -fs "Burp Suite" \
                      -o "${dir}/httpx/httpx_output.txt" \
                      -no-color $proxy_flag > /dev/null 2>&1 || true

                # Move screenshots and responses if they exist
                if [[ -d "output/screenshot" ]]; then
                    mkdir -p "${dir}/httpx/screenshots"
                    mv output/screenshot/* "${dir}/httpx/screenshots/" 2>/dev/null || true
                fi
                if [[ -d "output/response" ]]; then
                    mkdir -p "${dir}/httpx/responses"
                    mv output/response/* "${dir}/httpx/responses/" 2>/dev/null || true
                fi
                # Clean up the output directory
                [[ -d "output" ]] && rm -rf output
            fi
        done
    fi

    # Count TLDs
    local tld_count=0
    [[ -f "${DIRS[ASN]}/tld_domains_recon/${FILES[TOP_LEVEL_DOMAINS]}" ]] && tld_count=$(wc -l < "${DIRS[ASN]}/tld_domains_recon/${FILES[TOP_LEVEL_DOMAINS]}")
    log_info "Found $tld_count unique top-level domains from SSL certificates"

    # Update latest symlink

    return 0
}

module_cleanup() {
    log_debug "Cleaning up SSL certificate analysis artifacts"
    # Clean up any leftover output directory
    [[ -d "output" ]] && rm -rf output
}