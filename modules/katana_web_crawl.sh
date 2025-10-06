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

    # Your exact katana command preserved
    katana -list "$LIVE_SUBS" \
           -headless -no-sandbox -jc \
           -d 2 -c 10 -p 2 -rl 10 -rlm 120 \
           -timeout 5 -retry 2 \
           -o "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}" \
           -silent -sr -srd "${DIRS[KATANA_DATA]}" \
           -ef png,jpg,jpeg,gif,svg,woff,woff2,ttf,eot,otf,ico,webp,mp4,pdf,css \
           $proxy_flag > /dev/null 2>&1 || true

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