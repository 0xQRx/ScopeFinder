#!/bin/bash
# Resolver freshness - fetch + validate DNS resolvers before enumeration
#
# Public resolver lists rot: entries go offline, start rate-limiting, or begin
# answering NXDOMAIN-worthy names with wildcard/captive-portal lies. A stale
# baked-in list silently degrades active DNS resolution. This module refreshes
# the resolver list at runtime (fetch a current public list, validate each
# resolver with dig, keep only the healthy ones) and writes a validated
# resolvers.txt that downstream modules (subdomain_enum -> subfinder -rlist)
# pass to their DNS tooling. When a refresh can't happen it warns about the age
# of what it falls back to rather than failing the run.
#
# Env overrides (all optional):
#   RESOLVERS_URL             public resolver list to fetch (default: trickest trusted)
#   RESOLVERS_FILE            use this local list verbatim; skip fetching
#   RESOLVERS_CACHE_DIR       persist/reuse a validated list across runs (age-checked)
#   RESOLVERS_MAX_AGE_HOURS   staleness threshold for cache/fallback (default: 168 = 7d)
#   RESOLVERS_VALIDATE        "false" to skip dig validation (default: true)
#   RESOLVERS_VALIDATE_LIMIT  max resolvers to validate (default: 200)
#   RESOLVERS_ANCHOR          neutral hostname used to test resolvers (default: www.google.com)
#   SCOPEFINDER_SKIP_RESOLVER_REFRESH   set to skip this module entirely

MODULE_NAME="resolver_refresh"
MODULE_DESC="Fetch and validate fresh DNS resolvers (with staleness warnings) for enumeration"

module_init() {
    if [[ -n "${SCOPEFINDER_SKIP_RESOLVER_REFRESH:-}" ]]; then
        log_info "Resolver refresh skipped (SCOPEFINDER_SKIP_RESOLVER_REFRESH set)"
        return 1
    fi
    mkdir -p "${DIRS[RESOLVERS]}"
    return 0
}

# Default public list: trickest's trusted-resolver set is small and already
# curated, so validation stays fast and high-signal.
RESOLVERS_URL_DEFAULT="https://raw.githubusercontent.com/trickest/resolvers/main/resolvers-trusted.txt"
RESOLVERS_ANCHOR_DEFAULT="www.google.com"
RESOLVERS_MAX_AGE_HOURS_DEFAULT=168
RESOLVERS_VALIDATE_LIMIT_DEFAULT=200

# Age of a file in whole hours, or a very large number if it is missing.
_resolver_file_age_hours() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo 999999
        return
    fi
    local mtime now
    mtime="$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    echo $(( (now - mtime) / 3600 ))
}

# Keep only well-formed IPv4 / IPv6 resolver addresses, one per line.
_resolver_clean() {
    local src="$1" dst="$2"
    grep -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$|^[0-9a-fA-F:]+:[0-9a-fA-F:]+$' "$src" 2>/dev/null \
        | awk '!seen[$0]++' > "$dst" || true
}

# Validate one resolver: it must (1) resolve a neutral anchor to >=1 A record
# and (2) NOT return an A record for a random, almost-certainly-nonexistent name
# (which would mean it lies/wildcards). Prints the resolver on success.
_resolver_check_one() {
    local resolver="$1" anchor="$2"
    local good bad
    good="$(dig +short +time=2 +tries=1 "@${resolver}" "$anchor" A 2>/dev/null \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n1)"
    [[ -n "$good" ]] || return 1
    bad="$(dig +short +time=2 +tries=1 "@${resolver}" \
        "sf-nx-${RANDOM}${RANDOM}.${anchor}" A 2>/dev/null \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n1)"
    [[ -z "$bad" ]] || return 1
    echo "$resolver"
}

module_run() {
    local out_file="${DIRS[RESOLVERS]}/${FILES[RESOLVERS]}"
    local raw_file="${DIRS[RESOLVERS]}/${FILES[RESOLVERS_RAW]}"

    local url="${RESOLVERS_URL:-$RESOLVERS_URL_DEFAULT}"
    local anchor="${RESOLVERS_ANCHOR:-$RESOLVERS_ANCHOR_DEFAULT}"
    local max_age="${RESOLVERS_MAX_AGE_HOURS:-$RESOLVERS_MAX_AGE_HOURS_DEFAULT}"
    local validate="${RESOLVERS_VALIDATE:-true}"
    local vlimit="${RESOLVERS_VALIDATE_LIMIT:-$RESOLVERS_VALIDATE_LIMIT_DEFAULT}"
    local cache_dir="${RESOLVERS_CACHE_DIR:-}"
    local cache_file=""
    [[ -n "$cache_dir" ]] && cache_file="${cache_dir}/resolvers_validated.txt"

    # --- 0. Reuse a fresh shared cache, if configured ------------------------
    if [[ -n "$cache_file" && -s "$cache_file" ]]; then
        local cache_age
        cache_age="$(_resolver_file_age_hours "$cache_file")"
        if (( cache_age <= max_age )); then
            cp -f "$cache_file" "$out_file"
            log_info "Reusing cached validated resolvers (${cache_age}h old, $(grep -c . "$out_file") resolvers)"
            return 0
        fi
        log_warn "Cached resolvers are stale (${cache_age}h old, threshold ${max_age}h) - refreshing"
    fi

    # --- 1. Obtain a raw resolver list ---------------------------------------
    local source_desc=""
    if [[ -n "${RESOLVERS_FILE:-}" ]]; then
        if [[ -s "$RESOLVERS_FILE" ]]; then
            _resolver_clean "$RESOLVERS_FILE" "$raw_file"
            source_desc="user-provided file"
            local age
            age="$(_resolver_file_age_hours "$RESOLVERS_FILE")"
            if (( age > max_age )); then
                log_warn "RESOLVERS_FILE is ${age}h old (threshold ${max_age}h) - consider refreshing it"
            fi
        else
            log_warn "RESOLVERS_FILE set but empty/missing: $RESOLVERS_FILE"
        fi
    fi

    if [[ ! -s "$raw_file" ]]; then
        log_info "Fetching resolver list from: $url"
        pick_user_agent
        if curl -fsSL --max-time 60 -A "$SELECTED_UA" "$url" -o "${raw_file}.dl" 2>/dev/null \
            && [[ -s "${raw_file}.dl" ]]; then
            _resolver_clean "${raw_file}.dl" "$raw_file"
            source_desc="fetched from $url"
        fi
        rm -f "${raw_file}.dl"
    fi

    # Fall back to a stale cache rather than nothing.
    if [[ ! -s "$raw_file" && -n "$cache_file" && -s "$cache_file" ]]; then
        local cache_age
        cache_age="$(_resolver_file_age_hours "$cache_file")"
        cp -f "$cache_file" "$out_file"
        log_warn "Resolver refresh failed - falling back to STALE cache (${cache_age}h old). DNS resolution may be degraded."
        return 0
    fi

    if [[ ! -s "$raw_file" ]]; then
        log_warn "Could not obtain any resolver list - downstream tools will use their built-in defaults"
        return 0
    fi

    local raw_count
    raw_count="$(grep -c . "$raw_file")"
    log_info "Obtained $raw_count resolvers ($source_desc)"

    # --- 2. Validate with dig (bounded + parallel) ---------------------------
    if [[ "$validate" == "true" ]] && command -v dig >/dev/null 2>&1; then
        local to_check="$raw_file"
        if (( raw_count > vlimit )); then
            to_check="${raw_file}.head"
            head -n "$vlimit" "$raw_file" > "$to_check"
            log_info "Validating first $vlimit of $raw_count resolvers against '$anchor' (RESOLVERS_VALIDATE_LIMIT)"
        else
            log_info "Validating $raw_count resolvers against '$anchor'"
        fi

        export -f _resolver_check_one
        xargs -a "$to_check" -P 20 -I{} bash -c '_resolver_check_one "$@"' _ {} "$anchor" \
            2>/dev/null | awk '!seen[$0]++' > "${out_file}.tmp" || true
        [[ "$to_check" == "${raw_file}.head" ]] && rm -f "$to_check"

        local valid_count=0
        [[ -f "${out_file}.tmp" ]] && valid_count="$(grep -c . "${out_file}.tmp")"

        if (( valid_count > 0 )); then
            mv "${out_file}.tmp" "$out_file"
            log_info "Validated $valid_count healthy resolvers"
        else
            rm -f "${out_file}.tmp"
            cp -f "$raw_file" "$out_file"
            log_warn "No resolvers passed validation - using the unvalidated list. DNS resolution may be unreliable."
        fi
    else
        cp -f "$raw_file" "$out_file"
        [[ "$validate" == "true" ]] && log_warn "dig not available - skipping resolver validation"
    fi

    # --- 3. Persist to shared cache if configured ----------------------------
    if [[ -n "$cache_file" && -s "$out_file" ]]; then
        mkdir -p "$cache_dir" 2>/dev/null \
            && cp -f "$out_file" "$cache_file" \
            && log_info "Updated shared resolver cache: $cache_file"
    fi

    log_info "Resolver list ready: $out_file ($(grep -c . "$out_file" 2>/dev/null || echo 0) resolvers)"
    return 0
}

module_cleanup() {
    log_debug "Cleaning up resolver refresh artifacts"
    rm -f "${DIRS[RESOLVERS]}/${FILES[RESOLVERS_RAW]}.dl" \
          "${DIRS[RESOLVERS]}/${FILES[RESOLVERS_RAW]}.head" \
          "${DIRS[RESOLVERS]}/${FILES[RESOLVERS]}.tmp" 2>/dev/null || true
}
