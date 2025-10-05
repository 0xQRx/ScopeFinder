#!/bin/bash
# JavaScript file download and analysis

MODULE_NAME="js_download"
MODULE_DESC="Download JavaScript files using wget"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[URLS_ARTIFACTS]}"
    mkdir -p "${DIRS[JS_DOWNLOADED]}"

    # Combine URLs from multiple sources
    TEMP_JS_FILE="${DIRS[URLS_ARTIFACTS]}/js_urls_temp.txt"
    > "$TEMP_JS_FILE"

    # Get URLs from archive step
    if [[ -f "${DIRS[URLS_ARTIFACTS]}/collected_urls.txt" ]]; then
        grep -E '\.js(\?.*)?$' "${DIRS[URLS_ARTIFACTS]}/collected_urls.txt" >> "$TEMP_JS_FILE" 2>/dev/null || true
    fi

    # Get URLs from crawl step
    if [[ -f "${DIRS[URLS_ARTIFACTS]}/katana_crawled_urls.txt" ]]; then
        grep -E '\.js(\?.*)?$' "${DIRS[URLS_ARTIFACTS]}/katana_crawled_urls.txt" >> "$TEMP_JS_FILE" 2>/dev/null || true
    fi
}

module_run() {
    log_info "Processing JavaScript files"

    # Filter out common libraries - your exact filter preserved
    local filter_pattern='jquery|jquery-ui|jquery\.min|react|react-dom|angular|angularjs|vue|vue\.min|ember|backbone|underscore|lodash|moment|dayjs|d3|three|chartjs|chart\.js|highcharts|gsap|animejs|popper|bootstrap|semantic-ui|materialize|tailwind|axios|fetch|zepto|modernizr|requirejs|next|nuxt|svelte|lit|redux|mobx|handlebars|mustache|express|rxjs|fastify|inertia|meteor|mithril|knockout|ractive|canjs|alpinejs|solid-js|preact|pixi|leaflet|openlayers|fullcalendar|zurb|enyo|fabric|svg\.js|velocity|vivus|particles\.js|zxcvbn|quill|tinymce|ckeditor|codemirror|highlight|mathjax|pdfjs|videojs|plyr|jwplayer|soundjs|howler|createjs|p5|stats\.js|tracking\.js|fancybox|lightbox|swiper|slick-carousel|flickity|lazysizes|barba|scrollmagic|locomotive|skrollr|headroom|turbolinks|stimulus|alpine\.js|instantclick|htmx|wix|avada|fusion|awb|modernizr|thunderbolt|Blazor|gtm\.js|blazor|win\.js|wp-*'

    grep -vE "$filter_pattern" "$TEMP_JS_FILE" > "${DIRS[JS_ENDPOINTS]}/${FILES[JS_ENDPOINTS]}" 2>/dev/null || true

    # Deduplicate with uro if available
    if command -v uro &> /dev/null; then
        uro -i "${DIRS[JS_ENDPOINTS]}/${FILES[JS_ENDPOINTS]}" > "${DIRS[JS_ENDPOINTS]}/js_endpoints_dedup.txt"
        mv "${DIRS[JS_ENDPOINTS]}/js_endpoints_dedup.txt" "${DIRS[JS_ENDPOINTS]}/${FILES[JS_ENDPOINTS]}"
    else
        dedupe_file "${DIRS[JS_ENDPOINTS]}/${FILES[JS_ENDPOINTS]}"
    fi

    # Download JS files - your exact command preserved
    local js_count=$(wc -l < "${DIRS[JS_ENDPOINTS]}/${FILES[JS_ENDPOINTS]}" 2>/dev/null || echo "0")
    if [[ "$js_count" -gt 0 ]]; then
        log_info "Downloading $js_count JavaScript files..."

        cat "${DIRS[JS_ENDPOINTS]}/${FILES[JS_ENDPOINTS]}" | xargs -P10 -I{} bash -c '
            url="{}"
            hash=$(echo -n "$url" | md5sum | cut -d" " -f1)
            ext="js"
            outfile="'"${DIRS[JS_DOWNLOADED]}"'/${hash}.${ext}"
            [ -f "$outfile" ] && { exit 0; }
            content=$(wget -q --no-check-certificate --retry-connrefused --wait=1 --random-wait --timeout=5 --tries=2 -O - "$url")
            [ -n "$content" ] && { echo "// Original URL: $url"; echo "$content"; } > "$outfile"
        ' 2>/dev/null || true
    fi

    # Count results
    local downloaded_count=$(find "${DIRS[JS_DOWNLOADED]}" -name "*.js" -type f | wc -l)
    log_info "Downloaded $downloaded_count JavaScript files"

    return 0
}

module_cleanup() {
    rm -f "${DIRS[URLS_ARTIFACTS]}/js_urls_temp.txt"
    log_debug "Cleaning up JavaScript download artifacts"
}