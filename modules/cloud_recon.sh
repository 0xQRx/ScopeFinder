#!/bin/bash
# Cloud infrastructure reconnaissance

MODULE_NAME="cloud_recon"
MODULE_DESC="Perform cloud infrastructure reconnaissance using msftrecon & kaeferjaeger.gay"

module_init() {
    # Create output directory
    # Fixed paths
    mkdir -p "${DIRS[CLOUD]}"

    # Extract base domain name
    DOMAIN_BASE_NAME=$(echo "$DOMAIN" | awk -F'.' '{print $(NF-1)}')
}

module_run() {
    log_info "Performing cloud reconnaissance for: $DOMAIN"

    # Run msftrecon for Microsoft cloud resources
    if command -v msftrecon &> /dev/null; then
        log_info "Running msftrecon..."
        msftrecon -d "$DOMAIN" >> "${DIRS[CLOUD]}/${FILES[MSFTRECON_OUTPUT]}" 2>/dev/null || true
    else
        log_warn "msftrecon not found - skipping Microsoft cloud reconnaissance"
    fi

    # Search cloud SNI ranges
    log_info "Searching cloud SNI ranges..."

    # Define SNI URLs
    local SNI_URLS=(
        "https://kaeferjaeger.gay/sni-ip-ranges/amazon/ipv4_merged_sni.txt"
        "https://kaeferjaeger.gay/sni-ip-ranges/digitalocean/ipv4_merged_sni.txt"
        "https://kaeferjaeger.gay/sni-ip-ranges/google/ipv4_merged_sni.txt"
        "https://kaeferjaeger.gay/sni-ip-ranges/microsoft/ipv4_merged_sni.txt"
        "https://kaeferjaeger.gay/sni-ip-ranges/oracle/ipv4_merged_sni.txt"
    )

    > "${DIRS[CLOUD]}/${FILES[CLOUD_SNI_DOMAINS]}"

    for url in "${SNI_URLS[@]}"; do
        local provider=$(echo "$url" | sed -n 's|.*/sni-ip-ranges/\([^/]*\)/.*|\1|p')
        log_info "Checking $provider SNI ranges..."

        curl -s "$url" | grep -iE "$DOMAIN|$DOMAIN_BASE_NAME" >> "${DIRS[CLOUD]}/${FILES[CLOUD_SNI_DOMAINS]}" 2>/dev/null || true
    done

    # Deduplicate results
    dedupe_file "${DIRS[CLOUD]}/${FILES[CLOUD_SNI_DOMAINS]}"

    # Count results
    local sni_count=0

    # Check for Microsoft recon results
    if [[ -f "${DIRS[CLOUD]}/${FILES[MSFTRECON_OUTPUT]}" ]]; then
        if grep -q "Namespace Type: Unknown" "${DIRS[CLOUD]}/${FILES[MSFTRECON_OUTPUT]}"; then
            log_info "Microsoft cloud resources not detected (namespace unknown)"
        else
            log_info "Microsoft cloud resources detected during reconnaissance"
        fi
    else
        log_info "Microsoft reconnaissance not performed or output missing"
    fi

    # Count SNI entries if file exists
    if [[ -f "${DIRS[CLOUD]}/${FILES[CLOUD_SNI_DOMAINS]}" ]]; then
        sni_count=$(wc -l < "${DIRS[CLOUD]}/${FILES[CLOUD_SNI_DOMAINS]}")
    fi

    # Report final cloud status
    log_info "Found $sni_count cloud SNI entries"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up cloud reconnaissance artifacts"
}