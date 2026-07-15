#!/bin/bash
# Discover and confirm API documentation (OpenAPI/Swagger/ReDoc/Postman) endpoints

MODULE_NAME="api_docs_probe"
MODULE_DESC="Discover and confirm API documentation endpoints (OpenAPI/Swagger/ReDoc) and save specs"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[API_DOCS]}"
    mkdir -p "${DIRS[API_DOCS_SPECS]}"

    # Resolve optional input sources (all optional; warn + continue)
    LIVE_SUBS="${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"
    URL_SOURCES=(
        "${DIRS[URLS_ARTIFACTS]}/${FILES[CRAWLED_URLS]}"
        "${DIRS[URLS_ARTIFACTS]}/${FILES[COLLECTED_URLS]}"
        "${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}"
        "${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}"
    )

    # Endpoints output file (one confirmed URL + type per line)
    ENDPOINTS_FILE="${DIRS[API_DOCS]}/${FILES[API_DOCS_ENDPOINTS]}"

    # Common API-documentation paths for active probing, GENERATED from a
    # base × version × file matrix rather than hand-listed so version formats stay
    # easy to tune. The version set includes dotted/semver forms (v1.0, 1.0, 1.0.0)
    # so routes like /api/1.0.0/schema.yaml are probed directly. Machine-readable
    # spec files are emitted FIRST (they are the high-value artifact), then human
    # UI pages — order matters because active-probe stops on a host after its first
    # confirmed hit, so a probed spec is preferred over a UI page on the same host.
    # graphql/graphiql paths are intentionally excluded — the dedicated
    # graphql_probe module already covers those. The long tail of arbitrary version
    # strings is caught by the harvest phase (see api_regex in module_run) rather
    # than brute-forced here.
    local api_bases=( "" "/api" )
    local api_versions=( "" "/v1" "/v2" "/v3" "/v1.0" "/1.0" "/1.0.0" )
    local api_spec_files=(
        "openapi.json" "openapi.yaml" "swagger.json" "swagger.yaml"
        "schema.json" "schema.yaml" "api-docs"
    )
    local api_ui_files=(
        "swagger" "swagger-ui.html" "swagger/index.html"
        "redoc" "docs" "api/documentation"
    )

    API_DOCS_PATHS=()
    local _b _v _f
    # Spec files first (highest value)
    for _b in "${api_bases[@]}"; do
        for _v in "${api_versions[@]}"; do
            for _f in "${api_spec_files[@]}"; do
                API_DOCS_PATHS+=( "${_b}${_v}/${_f}" )
            done
        done
    done
    # Then UI pages
    for _b in "${api_bases[@]}"; do
        for _v in "${api_versions[@]}"; do
            for _f in "${api_ui_files[@]}"; do
                API_DOCS_PATHS+=( "${_b}${_v}/${_f}" )
            done
        done
    done
    # Fixed extras that don't fit the matrix
    API_DOCS_PATHS+=(
        "/swagger/swagger.json" "/swagger/v1/swagger.json"
        "/swagger/v2/swagger.json" "/swagger/v3/swagger.json"
        "/docs/openapi.json" "/docs/openapi.yaml"
        "/api/docs/openapi.json" "/api/docs/openapi.yaml"
        "/redoc.html" "/postman.json" "/api/postman.json"
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
    url="${url%%#*}"
    url="${url%%\?*}"
    echo "$url"
}

# Turn an endpoint URL into a filesystem-safe slug (host + path)
slugify_endpoint() {
    local url="$1"
    local stripped="${url#*://}"
    echo "$stripped" | sed -E 's/[^A-Za-z0-9._-]/_/g' | sed -E 's/_+/_/g;s/^_//;s/_$//'
}

# Decide whether a response body is an OpenAPI/Swagger/AsyncAPI spec document.
# Matches both JSON (quoted keys) and YAML (top-level key) spec files.
is_openapi_spec() {
    local body="$1"
    [[ -n "$body" ]] || return 1
    # JSON-style: "openapi": "3.0.x" / "swagger": "2.0"
    [[ "$body" == *'"swagger"'* || "$body" == *'"openapi"'* || "$body" == *'"asyncapi"'* ]] && return 0
    # YAML-style: top-of-document  openapi: 3.0.0  /  swagger: "2.0"
    printf '%s' "$body" | grep -qiE '^[[:space:]]*(swagger|openapi|asyncapi)[[:space:]]*:' && return 0
    return 1
}

# Decide whether a response body is a rendered API-docs UI page.
is_api_docs_ui() {
    local body="$1"
    [[ -n "$body" ]] || return 1
    printf '%s' "$body" | grep -qiE 'swagger-?ui|swaggeruibundle|redoc|rapidoc|stoplight-elements|swagger ui' && return 0
    return 1
}

module_run() {
    log_info "Starting API docs discovery for $DOMAIN"

    local candidates_file="${DIRS[API_DOCS]}/.apidocs_candidates.txt"
    : > "$candidates_file"

    # --- Discovery A: HARVEST indicators from URL-source files ---
    # Tight regex: only specific doc markers (bare /docs is too noisy to harvest,
    # active probing covers it anyway).
    local api_regex='swagger|openapi|api-docs|apidocs|redoc|postman\.json|schema\.(json|ya?ml)'
    local harvested=0
    for src in "${URL_SOURCES[@]}"; do
        [[ -f "$src" ]] || continue
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            [[ "$line" =~ ^https?:// ]] || continue
            local ep
            ep="$(normalize_endpoint "$line")"
            [[ -n "$ep" ]] || continue
            # Skip static assets (swagger-ui.js/.css bundles match by name but are
            # not the doc endpoint itself).
            [[ "$ep" =~ \.(js|css|map|png|jpe?g|gif|svg|woff2?|ttf|ico|webp)$ ]] && continue
            echo "$ep" >> "$candidates_file"
            ((harvested++))
        done < <(grep -iE "$api_regex" "$src" 2>/dev/null || true)
    done
    log_info "Harvested $harvested API-docs indicator(s) from URL sources"

    # --- Discovery B: ACTIVE PROBE common paths on each live subdomain ---
    # live_subdomains.txt holds bare hostnames (e.g. api.example.com); crawl entries
    # are full URLs. Accept both: prepend https:// to scheme-less hosts.
    if check_file "$LIVE_SUBS"; then
        while IFS= read -r base; do
            [[ -n "$base" ]] || continue
            base="${base%/}"
            if [[ ! "$base" =~ ^https?:// ]]; then
                base="https://${base}"
            fi
            for p in "${API_DOCS_PATHS[@]}"; do
                echo "${base}${p}" >> "$candidates_file"
            done
        done < "$LIVE_SUBS"
    fi

    # Remove duplicates but PRESERVE order (harvested first, then active-probe
    # paths in spec-first likelihood order). Order decides which path per host is
    # confirmed first before the per-host short-circuit kicks in.
    dedupe_file "$candidates_file"

    local candidate_count=0
    [[ -f "$candidates_file" ]] && candidate_count=$(wc -l < "$candidates_file")
    log_info "Assembled $candidate_count candidate endpoint(s) to confirm"

    if [[ "$candidate_count" -eq 0 ]]; then
        log_warn "No API-docs candidate endpoints to probe"
        : > "$ENDPOINTS_FILE"
        rm -f "$candidates_file"
        return 0
    fi

    # --- CONFIRM: GET each candidate, keep only real spec/UI responses ---
    # API docs are always served over GET. A response is confirmed only if its body
    # is an OpenAPI/Swagger spec or a rendered docs UI — a plain 200 (SPA index,
    # generic page) is not enough, which keeps false positives low.
    # Stop probing a host once one doc endpoint is confirmed on it (spec paths are
    # ordered first, so the machine-readable spec wins). Set API_DOCS_PROBE_ALL=1
    # to probe every path exhaustively instead.
    log_info "Confirming candidate endpoints (GET)..."
    local confirmed_file="${DIRS[API_DOCS]}/.apidocs_confirmed.txt"
    : > "$confirmed_file"

    local stop_on_first=1
    [[ "${API_DOCS_PROBE_ALL:-0}" == "1" ]] && stop_on_first=0

    local spec_count=0 ui_count=0
    declare -A host_done=()
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue

        local host
        host="$(printf '%s' "$candidate" | sed -E 's#^(https?://[^/]+).*#\1#')"
        if [[ "$stop_on_first" -eq 1 && -n "${host_done[$host]:-}" ]]; then
            continue
        fi

        local body
        body="$(curl -sk -m 10 -L --max-redirs 3 "${CURL_PROXY[@]}" \
                    -H 'Accept: application/json, application/yaml, text/html' \
                    "$candidate" 2>/dev/null || true)"
        [[ -n "$body" ]] || continue

        local slug
        slug="$(slugify_endpoint "$candidate")"
        [[ -n "$slug" ]] || slug="endpoint"

        if is_openapi_spec "$body"; then
            # Save the spec document (JSON if it looks like JSON, else YAML)
            local ext="yaml"
            [[ "$body" == *'"openapi"'* || "$body" == *'"swagger"'* || "$body" == *'"asyncapi"'* ]] && ext="json"
            printf '%s' "$body" > "${DIRS[API_DOCS_SPECS]}/${slug}.${ext}"
            echo -e "${candidate}\tspec" >> "$confirmed_file"
            ((spec_count++))
            [[ "$stop_on_first" -eq 1 ]] && host_done[$host]=1
            continue
        fi

        if is_api_docs_ui "$body"; then
            echo -e "${candidate}\tui" >> "$confirmed_file"
            ((ui_count++))
            [[ "$stop_on_first" -eq 1 ]] && host_done[$host]=1
        fi
    done < "$candidates_file"

    sort -u "$confirmed_file" -o "$confirmed_file" 2>/dev/null || true
    mv "$confirmed_file" "$ENDPOINTS_FILE"
    rm -f "$candidates_file"

    local confirmed_count=0
    [[ -f "$ENDPOINTS_FILE" ]] && confirmed_count=$(wc -l < "$ENDPOINTS_FILE")

    log_info "API docs summary: candidates=$candidate_count confirmed=$confirmed_count (spec=$spec_count ui=$ui_count)"

    return 0
}

module_cleanup() {
    rm -f "${DIRS[API_DOCS]}/.apidocs_candidates.txt" "${DIRS[API_DOCS]}/.apidocs_confirmed.txt"
    log_debug "Cleaning up api_docs_probe artifacts"
}
