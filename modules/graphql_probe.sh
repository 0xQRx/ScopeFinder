#!/bin/bash
# Discover, confirm, audit GraphQL endpoints and export SDL

MODULE_NAME="graphql_probe"
MODULE_DESC="Discover, confirm, audit GraphQL endpoints and export SDL (graphql-cop)"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[GRAPHQL]}"
    mkdir -p "${DIRS[GRAPHQL_COP]}"
    mkdir -p "${DIRS[GRAPHQL_SDL]}"

    # Resolve optional input sources (all optional; warn + continue)
    LIVE_SUBS="${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"
    URL_SOURCES=(
        "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}"
        "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}"
        "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}"
        "${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}"
    )

    # Endpoints output file
    ENDPOINTS_FILE="${DIRS[GRAPHQL]}/${FILES[GRAPHQL_ENDPOINTS]}"

    # Curated common GraphQL paths for active probing
    GQL_COMMON_PATHS=(
        "/graphql" "/graphiql" "/api/graphql" "/v1/graphql" "/v2/graphql"
        "/graphql/console" "/graphql.php" "/index.php?graphql" "/gql"
        "/query" "/api" "/playground" "/subscriptions" "/altair"
        "/graphql/v1" "/api/gql"
    )

    # curl proxy flag (curl is always present; honor HTTP_PROXY_URL)
    CURL_PROXY=()
    if [[ -n "$HTTP_PROXY_URL" ]]; then
        CURL_PROXY=(-x "$HTTP_PROXY_URL")
    fi

    if ! check_file "$LIVE_SUBS"; then
        log_warn "No live subdomains found from previous step"
    fi
}

# Normalize a URL down to scheme://host/path (strip query string and fragment)
normalize_endpoint() {
    local url="$1"
    # Drop fragment, then drop query string
    url="${url%%#*}"
    url="${url%%\?*}"
    echo "$url"
}

# Turn an endpoint URL into a filesystem-safe slug (host + path)
slugify_endpoint() {
    local url="$1"
    # Strip scheme, then replace any non-alnum/dot/dash with underscore
    local stripped="${url#*://}"
    echo "$stripped" | sed -E 's/[^A-Za-z0-9._-]/_/g' | sed -E 's/_+/_/g;s/^_//;s/_$//'
}

module_run() {
    log_info "Starting GraphQL discovery for $DOMAIN"

    local candidates_file="${DIRS[GRAPHQL]}/.gql_candidates.txt"
    : > "$candidates_file"

    # --- Discovery A: HARVEST indicators from URL-source files ---
    local gql_regex='graphql|graphiql|/gql|/api/graphql|/v1/graphql|/v2/graphql|/query|/playground|/console|graphql\.php'
    local harvested=0
    for src in "${URL_SOURCES[@]}"; do
        [[ -f "$src" ]] || continue
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            # Only consider things that look like URLs
            [[ "$line" =~ ^https?:// ]] || continue
            local ep
            ep="$(normalize_endpoint "$line")"
            [[ -n "$ep" ]] && echo "$ep" >> "$candidates_file"
            ((harvested++))
        done < <(grep -iE "$gql_regex" "$src" 2>/dev/null || true)
    done
    log_info "Harvested $harvested GraphQL indicator(s) from URL sources"

    # --- Discovery B: ACTIVE PROBE common paths on each live subdomain ---
    if check_file "$LIVE_SUBS"; then
        while IFS= read -r base; do
            [[ -n "$base" ]] || continue
            [[ "$base" =~ ^https?:// ]] || continue
            # Strip any trailing slash on the base
            base="${base%/}"
            for p in "${GQL_COMMON_PATHS[@]}"; do
                echo "${base}${p}" >> "$candidates_file"
            done
        done < "$LIVE_SUBS"
    fi

    # Merge + sort unique
    dedupe_file "$candidates_file"
    sort -u "$candidates_file" -o "$candidates_file" 2>/dev/null || true

    local candidate_count=0
    [[ -f "$candidates_file" ]] && candidate_count=$(wc -l < "$candidates_file")
    log_info "Assembled $candidate_count candidate endpoint(s) to confirm"

    if [[ "$candidate_count" -eq 0 ]]; then
        log_warn "No GraphQL candidate endpoints to probe"
        : > "$ENDPOINTS_FILE"
        rm -f "$candidates_file"
        return 0
    fi

    # --- CONFIRM: POST a minimal query, keep only real GraphQL endpoints ---
    log_info "Confirming candidate endpoints (POST {__typename})..."
    local confirmed_file="${DIRS[GRAPHQL]}/.gql_confirmed.txt"
    : > "$confirmed_file"

    local query='{"query":"{__typename}"}'
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        local body
        body="$(curl -sk -m 10 "${CURL_PROXY[@]}" -X POST \
                    -H 'Content-Type: application/json' \
                    --data "$query" "$candidate" 2>/dev/null || true)"

        if [[ -z "$body" ]]; then
            # Retry with GET as a fallback
            body="$(curl -sk -m 10 "${CURL_PROXY[@]}" -G \
                        --data-urlencode 'query={__typename}' \
                        "$candidate" 2>/dev/null || true)"
        fi

        if [[ "$body" == *"__typename"* || "$body" == *'"data"'* || "$body" == *'"errors"'* ]]; then
            echo "$candidate" >> "$confirmed_file"
        fi
    done < "$candidates_file"

    dedupe_file "$confirmed_file"
    sort -u "$confirmed_file" -o "$confirmed_file" 2>/dev/null || true
    mv "$confirmed_file" "$ENDPOINTS_FILE"
    rm -f "$candidates_file"

    local confirmed_count=0
    [[ -f "$ENDPOINTS_FILE" ]] && confirmed_count=$(wc -l < "$ENDPOINTS_FILE")
    log_info "Confirmed $confirmed_count GraphQL endpoint(s)"

    if [[ "$confirmed_count" -eq 0 ]]; then
        return 0
    fi

    # --- AUDIT + SDL: only if graphql-cop is available ---
    if ! command -v graphql-cop &>/dev/null; then
        log_warn "graphql-cop not found in image; skipping audit and SDL export"
        log_info "GraphQL summary: endpoints found=$candidate_count confirmed=$confirmed_count sdl=0"
        return 0
    fi

    log_info "Auditing $confirmed_count endpoint(s) with graphql-cop..."
    local cop_err="${DIRS[GRAPHQL_COP]}/graphql_cop.err"
    local sdl_count=0

    while IFS= read -r ep; do
        [[ -n "$ep" ]] || continue
        local slug
        slug="$(slugify_endpoint "$ep")"
        [[ -n "$slug" ]] || slug="endpoint"

        # Security audit (JSON report to stdout)
        graphql-cop -t "$ep" -o json > "${DIRS[GRAPHQL_COP]}/${slug}.json" 2>>"$cop_err" || true

        # SDL export (tool writes file only when introspection is enabled)
        local sdl_file="${DIRS[GRAPHQL_SDL]}/${slug}.gql"
        graphql-cop -t "$ep" --export-schema "$sdl_file" >/dev/null 2>&1 || true

        if check_file "$sdl_file"; then
            ((sdl_count++))
        else
            rm -f "$sdl_file"
        fi
    done < "$ENDPOINTS_FILE"

    # Remove empty error log
    [[ -s "$cop_err" ]] || rm -f "$cop_err"

    log_info "GraphQL summary: endpoints found=$candidate_count confirmed=$confirmed_count sdl=$sdl_count"

    return 0
}

module_cleanup() {
    rm -f "${DIRS[GRAPHQL]}/.gql_candidates.txt" "${DIRS[GRAPHQL]}/.gql_confirmed.txt"
    log_debug "Cleaning up graphql_probe artifacts"
}
