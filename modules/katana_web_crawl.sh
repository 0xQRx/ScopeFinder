#!/bin/bash
# Web crawling with Katana

MODULE_NAME="katana_web_crawl"
MODULE_DESC="Crawl live subdomains using katana"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS]}"
    mkdir -p "${DIRS[KATANA_DATA]}"

    # Get all live subdomains from service probe step
    LIVE_SUBS="${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"

    if ! check_file "$LIVE_SUBS"; then
        log_warn "No live subdomains found from previous step"
        touch "$LIVE_SUBS"  # Create empty file to continue
    fi
}

module_run() {
    local input_count=$(wc -l < "$LIVE_SUBS" 2>/dev/null || echo "0")

    if [[ "$input_count" -eq 0 ]]; then
        log_warn "No live subdomains to crawl"
        return 0
    fi

    log_info "Crawling $input_count live subdomains using Katana..."

    # Get proxy flag
    local proxy_flag=$(get_proxy_flag "katana")

    # Restrict crawling to the target domain and its subdomains.
    # Dots escaped so "example.com" matches as a literal suffix, not any char.
    # This prevents katana from spidering external CDNs/third-party domains;
    # external JS URLs are still discovered and output (useful for recon) but
    # not followed. Downstream httpx_url_probe already filters output to scope.
    local scope_regex="${DOMAIN//./\\.}"

    katana -list "$LIVE_SUBS" \
           -headless -no-sandbox -jc \
           -d 2 -c 10 -p 2 -rl 10 -rlm 120 -ct 5m -mrs 10485760 \
           -timeout 5 -retry 2 \
           -ss -ssd 2000 \
           -cs "$scope_regex" \
           -o "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}" \
           -silent -sr -srd "${DIRS[KATANA_DATA]}" \
           -ef png,jpg,jpeg,gif,svg,woff,woff2,ttf,eot,otf,ico,webp,mp4,pdf,css \
           $proxy_flag >/dev/null 2>>"${DIRS[URLS_ARTIFACTS]}/katana.err" || true

    [[ -s "${DIRS[URLS_ARTIFACTS]}/katana.err" ]] || rm -f "${DIRS[URLS_ARTIFACTS]}/katana.err"
    
    # Deduplicate
    dedupe_file "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}"

    # Count results
    local url_count=0
    [[ -f "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}" ]] && url_count=$(wc -l < "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}")
    log_info "Crawled $url_count URLs"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up web crawl artifacts"
}