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

    # Common GraphQL paths for active probing. Merged from SecLists
    # Discovery/Web-Content/graphql.txt (static .css/.js assets excluded) plus a
    # few extras (/gql, /query, /index.php?graphql). IDE/schema paths are kept so
    # exposed GraphiQL/Playground/schema dumps are probed too.
    # Ordered by likelihood: real API endpoint paths first, then IDE pages
    # (graphiql/playground/altair/…), then schema dumps, then the generic /api.
    # Order matters because active-probe stops on a host after its first hit.
    GQL_COMMON_PATHS=(
        "/___graphql" "/api/gql" "/api/graphql" "/gql"
        "/graphql" "/graphql.php" "/graphql/api" "/graphql/graphql"
        "/graphql/v1" "/index.php?graphql" "/je/graphql" "/query"
        "/server/api/graphql" "/subscriptions" "/v1/api/graphql" "/v1/graphql"
        "/v1/graphql.php" "/v1/subscriptions" "/v2/api/graphql" "/v2/graphql"
        "/v2/graphql.php" "/v2/subscriptions" "/v3/api/graphql" "/v3/graphql"
        "/v3/graphql.php" "/v3/subscriptions" "/v4/api/graphql" "/v4/graphql"
        "/v4/graphql.php" "/v4/subscriptions" "/altair" "/explorer"
        "/graph" "/graphiql" "/graphiql.php" "/graphiql/finland"
        "/graphql-explorer" "/graphql/console" "/playground" "/v1/altair"
        "/v1/explorer" "/v1/graph" "/v1/graphiql" "/v1/graphiql.php"
        "/v1/graphiql/finland" "/v1/graphql-explorer" "/v1/graphql/console" "/v1/playground"
        "/v2/altair" "/v2/explorer" "/v2/graph" "/v2/graphiql"
        "/v2/graphiql.php" "/v2/graphiql/finland" "/v2/graphql-explorer" "/v2/graphql/console"
        "/v2/playground" "/v3/altair" "/v3/explorer" "/v3/graph"
        "/v3/graphiql" "/v3/graphiql.php" "/v3/graphiql/finland" "/v3/graphql-explorer"
        "/v3/graphql/console" "/v3/playground" "/v4/altair" "/v4/explorer"
        "/v4/graph" "/v4/graphiql" "/v4/graphiql.php" "/v4/graphiql/finland"
        "/v4/graphql-explorer" "/v4/graphql/console" "/v4/playground" "/graphql/schema.json"
        "/graphql/schema.xml" "/graphql/schema.yaml" "/v1/graphql/schema.json" "/v1/graphql/schema.xml"
        "/v1/graphql/schema.yaml" "/v2/graphql/schema.json" "/v2/graphql/schema.xml" "/v2/graphql/schema.yaml"
        "/v3/graphql/schema.json" "/v3/graphql/schema.xml" "/v3/graphql/schema.yaml" "/v4/graphql/schema.json"
        "/v4/graphql/schema.xml" "/v4/graphql/schema.yaml" "/api"
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

# Decide whether a response body looks like a GraphQL reply to {__typename}.
# A bare `"data"`/`"errors"` substring is NOT enough: soft-404 JSON APIs (that
# answer any path with 200 + {"errors":["not found"]}) would false-positive, and
# the per-host short-circuit would then lock in a bogus endpoint. Require real
# GraphQL evidence instead:
#   1. the server echoed __typename back (a resolved {__typename} query), or
#   2. an `errors` array carrying GraphQL-specific markers (locations/extensions
#      or GraphQL parser/validation error text) — never a generic REST error.
is_graphql_response() {
    local body="$1"
    [[ -n "$body" ]] || return 1
    # 1) __typename echoed => the query actually resolved against a GraphQL schema
    [[ "$body" == *'"__typename"'* ]] && return 0
    [[ "$body" == *'__typename'* && "$body" == *'"data"'* ]] && return 0
    # 2) GraphQL-shaped error envelope (distinguish from a generic REST error)
    if [[ "$body" == *'"errors"'* ]]; then
        printf '%s' "$body" | grep -qiE '"locations"|"extensions"|Cannot query field|Syntax Error|must provide (a )?query|GraphQL|Unknown argument|Unexpected (token|Name)|did you mean' && return 0
    fi
    return 1
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
            [[ -n "$ep" ]] || continue
            # Skip static assets (e.g. graphql-*.js bundles) — they match the
            # indicator regex by filename but are never live GraphQL endpoints.
            [[ "$ep" =~ \.(js|css|map|png|jpe?g|gif|svg|woff2?|ttf|ico|webp)$ ]] && continue
            echo "$ep" >> "$candidates_file"
            ((harvested++))
        done < <(grep -iE "$gql_regex" "$src" 2>/dev/null || true)
    done
    log_info "Harvested $harvested GraphQL indicator(s) from URL sources"

    # --- Discovery B: ACTIVE PROBE common paths on each live subdomain ---
    # live_subdomains.txt holds bare hostnames (e.g. api.example.com),
    # but crawl/waymore entries are full URLs. Accept both: prepend https:// to
    # scheme-less hosts so each host is probed at every common GraphQL path.
    if check_file "$LIVE_SUBS"; then
        while IFS= read -r base; do
            [[ -n "$base" ]] || continue
            # Strip any trailing slash on the base
            base="${base%/}"
            if [[ ! "$base" =~ ^https?:// ]]; then
                base="https://${base}"
            fi
            for p in "${GQL_COMMON_PATHS[@]}"; do
                echo "${base}${p}" >> "$candidates_file"
            done
        done < "$LIVE_SUBS"
    fi

    # Remove duplicates but PRESERVE order (harvested first, then active-probe
    # paths in likelihood order). Do not sort: order decides which path is tried
    # first per host before the per-host short-circuit below kicks in.
    dedupe_file "$candidates_file"

    local candidate_count=0
    [[ -f "$candidates_file" ]] && candidate_count=$(wc -l < "$candidates_file")
    log_info "Assembled $candidate_count candidate endpoint(s) to confirm"

    if [[ "$candidate_count" -eq 0 ]]; then
        log_warn "No GraphQL candidate endpoints to probe"
        : > "$ENDPOINTS_FILE"
        rm -f "$candidates_file"
        return 0
    fi

    # --- CONFIRM: probe with a minimal query, keep only real GraphQL endpoints ---
    # POST is the primary probe (most GraphQL servers are POST-only), with a GET
    # fallback whenever POST does not confirm — this covers POST-only endpoints,
    # GET-only endpoints, and cases where one method is blocked (WAF/CSRF) while
    # the other still answers.
    # Stop probing a host once one GraphQL endpoint is confirmed on it: no point
    # hammering the other ~90 paths of a host we've already fingerprinted. We keep
    # the FIRST (highest-likelihood) endpoint per host. Set GRAPHQL_PROBE_ALL=1 to
    # probe every path exhaustively (find multiple endpoints per host) instead.
    log_info "Confirming candidate endpoints (POST then GET {__typename})..."
    local confirmed_file="${DIRS[GRAPHQL]}/.gql_confirmed.txt"
    : > "$confirmed_file"

    local stop_on_first=1
    [[ "${GRAPHQL_PROBE_ALL:-0}" == "1" ]] && stop_on_first=0

    local query='{"query":"{__typename}"}'
    declare -A host_done=()
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue

        # host key = scheme://netloc; skip if this host already yielded an endpoint
        local host
        host="$(printf '%s' "$candidate" | sed -E 's#^(https?://[^/]+).*#\1#')"
        if [[ "$stop_on_first" -eq 1 && -n "${host_done[$host]:-}" ]]; then
            continue
        fi

        # Rotate the browser User-Agent per candidate (same UA for its POST + GET)
        pick_user_agent

        # 1) POST application/json (primary)
        local body
        body="$(curl -sk -m 10 "${CURL_PROXY[@]}" -A "$SELECTED_UA" -X POST \
                    -H 'Content-Type: application/json' \
                    --data "$query" "$candidate" 2>/dev/null || true)"

        if is_graphql_response "$body"; then
            echo "$candidate" >> "$confirmed_file"
            [[ "$stop_on_first" -eq 1 ]] && host_done[$host]=1
            continue
        fi

        # 2) GET ?query={__typename} (fallback whenever POST did not confirm)
        body="$(curl -sk -m 10 "${CURL_PROXY[@]}" -A "$SELECTED_UA" -G \
                    --data-urlencode 'query={__typename}' \
                    "$candidate" 2>/dev/null || true)"

        if is_graphql_response "$body"; then
            echo "$candidate" >> "$confirmed_file"
            [[ "$stop_on_first" -eq 1 ]] && host_done[$host]=1
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
