#!/bin/bash
# Structured run summary + run-over-run diffing
#
# Emits a machine-readable summary.json of the discovered surface (subdomains,
# live hosts, open ports, URLs, findings) so a run can be consumed by external
# tooling/pipelines instead of parsing per-module text files. Each run also
# writes a timestamped copy under summaries/, and a stable summary.json at the
# work-dir root always points at the newest. When a previous summary exists,
# a diff.json flags the NEW surface (new subdomains, newly live hosts, newly
# open ports) relative to that baseline - high value for the
# baseline-before-engagement workflow.
#
# It also writes export.json: a manifest of every raw result file the run
# produced (path relative to the work dir, data format, producing module, line
# and byte counts). summary.json carries counts; export.json tells a consumer
# where the full data lives so it can ingest the actual items.

MODULE_NAME="run_summary"
MODULE_DESC="Emit machine-readable summary.json of the discovered surface and diff it against the previous run"

# Schema version for summary.json / diff.json. Bump when the shape changes so
# downstream consumers can detect incompatibilities.
SUMMARY_SCHEMA_VERSION=1

module_init() {
    mkdir -p "${DIRS[SUMMARIES]}"
    return 0
}

# Schema version for export.json (independent of the summary schema).
EXPORT_SCHEMA_VERSION=1

# Raw artifacts listed in export.json, one per line:
#   name|DIRS key|file (FILES key, or a literal name prefixed with '=')|module|format|description
# "format" tells a consumer how to parse each line:
#   host          bare hostname
#   url           absolute URL
#   ip            IPv4/IPv6 address
#   cidr          CIDR range
#   email         email address
#   param         parameter name
#   redirect      "<source host> -> <final host>"
#   ip_host       "<ip> <hostname|No domain>"
#   httpx         httpx text: "<url> [status] [title] [tech,...]" (fields optional)
#   gnmap         nmap grepable output
#   nuclei        nuclei text result line
#   secret        "[<type>] <value> (Source: <file>)"
#   trufflehog    trufflehog multi-line text (findings open with "Found ... result")
#   colon_pair    "<identity>:<secret>"
#   text          free-form text, one item per line
#   dir           directory of files (lines = number of files)
_EXPORT_ARTIFACTS='
subdomains|SUBDOMAINS|SUBDOMAINS|subdomain_enum|host|All discovered subdomains
wildcard_subdomains|SUBDOMAINS|WILDCARD_SUBDOMAINS|subdomain_enum|host|Subdomains resolving under a wildcard
live_subdomains|SUBDOMAINS|LIVE_SUBDOMAINS|httpx_subdomain_probe|host|Subdomains that answered HTTP(S)
http_200_subdomains|SUBDOMAINS|SUBDOMAINS_200|httpx_subdomain_probe|host|Subdomains whose final response was 200
redirected_subdomains|SUBDOMAINS|REDIRECTED_TO_SUBDOMAINS|httpx_subdomain_probe|redirect|Subdomains redirecting to another in-scope host
httpx_hosts|HTTPX|HTTPX_OUTPUT|httpx_subdomain_probe|httpx|httpx probe of subdomains (status, title, tech)
subdomain_takeover|SUBDOMAIN_TAKEOVER|TAKEOVER_RESULTS|subdomain_takeover|nuclei|Subdomain takeover candidates
open_ports_gnmap|SCANS_SMAP|=open_ports.gnmap|smap_port_scan|gnmap|Port scan of subdomains
web_servers|SCANS|WEB_SERVERS|smap_port_scan|ip_host|Hosts with 80/443 open
ips_from_smap|SCANS|IPS_FROM_SMAP|smap_port_scan|ip|IPs seen by the subdomain port scan
ips_from_sources|SCANS|IPS_FROM_SOURCES|ip_discovery|ip|IPs from open sources
ips_from_ssl|SHODAN|IPS_FROM_SSL|shodan_search|ip|IPs presenting the domain in TLS certificates
ips_from_org|SHODAN|IPS_FROM_ORG|shodan_search|ip|IPs belonging to the selected organization
asn_ranges|ASN|ASN_RANGES|asn_discovery|cidr|IP ranges announced by the organization ASNs
asn_open_ports_gnmap|ASN_SMAP|=open_ports.gnmap|asn_port_scan|gnmap|Port scan of ASN ranges
asn_web_servers|ASN|ASN_WEBSERVERS|asn_port_scan|ip_host|ASN hosts with 80/443 open
cloud_sni_domains|CLOUD|CLOUD_SNI_DOMAINS|cloud_recon|text|Cloud SNI dataset hits for the domain
emails|CREDENTIALS|EMAILS|credential_intel|email|Email addresses
leaked_email_passwd|CREDENTIALS|LEAKED_EMAIL_PASSWD|credential_intel|colon_pair|Leaked email:password pairs
leaked_username_passwd|CREDENTIALS|LEAKED_USERNAME_PASSWD|credential_intel|colon_pair|Leaked username:password pairs
urls_with_params|URLS_ARTIFACTS|URLS_WITH_PARAMS_UNIQ|extract_params|url|Collected URLs with parameters (deduplicated, unprobed)
urls_without_params|URLS_ARTIFACTS|URLS_WITHOUT_PARAMS_UNIQ|extract_params|url|Collected URLs without parameters (deduplicated, unprobed)
parameters|PARAMETERS|PARAMETERS|extract_params|param|Unique parameter names
live_urls_with_params|URLS|LIVE_URLS_WITH_PARAMS|httpx_url_probe|url|Live URLs with parameters
live_urls_without_params|URLS|LIVE_URLS_WITHOUT_PARAMS|httpx_url_probe|url|Live URLs without parameters
httpx_urls_with_params|URLS_ARTIFACTS|HTTPX_URLS_WITH_PARAMS_OUTPUT|httpx_url_probe|httpx|httpx probe of URLs with parameters
httpx_urls_without_params|URLS_ARTIFACTS|HTTPX_URLS_WITHOUT_PARAMS_OUTPUT|httpx_url_probe|httpx|httpx probe of URLs without parameters
js_files|JS_ENDPOINTS|JS_ENDPOINTS|js_download|url|Live JavaScript file URLs
js_chunk_urls|URLS_ARTIFACTS|JS_CHUNK_URLS|js_chunk_discovery|url|Lazy-loaded / webpack chunk URLs
jsluice_urls|URLS_LINKFINDER|JSLUICE_URLS|linkfinder_analysis|text|URLs and paths extracted from JS by jsluice
xnlinkfinder_js_urls|XNLINKFINDER|XNLINKFINDER_JS_OUTPUT|linkfinder_analysis|text|URLs and paths extracted from JS by xnLinkFinder
xnlinkfinder_js_params|XNLINKFINDER|XNLINKFINDER_JS_PARAMS|linkfinder_analysis|param|Parameter names extracted from JS
graphql_endpoints|GRAPHQL|GRAPHQL_ENDPOINTS|graphql_probe|url|Confirmed GraphQL endpoints
graphql_sdl|GRAPHQL_SDL|=|graphql_probe|dir|Exported GraphQL SDL files
api_docs_endpoints|API_DOCS|API_DOCS_ENDPOINTS|api_docs_probe|url|Confirmed API documentation endpoints
api_docs_specs|API_DOCS_SPECS|=|api_docs_probe|dir|Downloaded OpenAPI/Swagger specs
wordpress_sites|WORDPRESS|WORDPRESS_SITES|httpx_subdomain_probe|url|WordPress sites
secrets_jshunter|SECRETS|JSHUNTER_ALL|secret_scan|secret|jshunter secret hits
secrets_jsluice|SECRETS|JSLUICE_ALL|secret_scan|secret|jsluice secret hits
secrets_trufflehog|SECRETS|TRUFFLEHOG_ALL|secret_scan|trufflehog|trufflehog results
'

# Write export.json to $1. Paths are relative to the work dir, so the manifest
# stays valid if the whole work dir is moved or copied elsewhere.
_summary_write_export() {
    local out="$1" now_iso="$2" now_epoch="$3"
    local work="${DIRS[WORK_DIR]}"
    local artifacts_json="{}"
    local name dkey fspec module fmt desc dir path rel exists lines bytes
    while IFS='|' read -r name dkey fspec module fmt desc; do
        [[ -n "$name" ]] || continue
        dir="${DIRS[$dkey]:-}"
        [[ -n "$dir" ]] || continue
        if [[ "$fspec" == "=" ]]; then
            path="$dir"
        elif [[ "$fspec" == =* ]]; then
            path="${dir}/${fspec#=}"
        else
            path="${dir}/${FILES[$fspec]:-}"
        fi
        rel="${path#"${work}"/}"
        exists=false; lines=0; bytes=0
        if [[ "$fmt" == "dir" ]]; then
            if [[ -d "$path" ]]; then
                exists=true
                lines="$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')"
                bytes="$(find "$path" -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')"
            fi
        elif [[ -f "$path" ]]; then
            exists=true
            lines="$(_summary_count "$path")"
            bytes="$(wc -c < "$path" 2>/dev/null | tr -d ' ')"
        fi
        artifacts_json="$(jq --arg name "$name" --arg path "$rel" --arg module "$module" \
            --arg format "$fmt" --arg desc "$desc" --argjson exists "$exists" \
            --argjson lines "${lines:-0}" --argjson bytes "${bytes:-0}" \
            '. + {($name): {path: $path, format: $format, module: $module,
                            description: $desc, exists: $exists,
                            lines: $lines, bytes: $bytes}}' <<< "$artifacts_json")"
    done <<< "$_EXPORT_ARTIFACTS"

    jq -n \
        --argjson schema "$EXPORT_SCHEMA_VERSION" \
        --arg domain "$DOMAIN" \
        --arg generated_at "$now_iso" \
        --argjson generated_at_epoch "$now_epoch" \
        --arg summary "${FILES[RUN_SUMMARY]}" \
        --arg diff "${FILES[RUN_DIFF]}" \
        --argjson artifacts "$artifacts_json" \
        '{
            schema_version: $schema,
            tool: "ScopeFinder",
            domain: $domain,
            generated_at: $generated_at,
            generated_at_epoch: $generated_at_epoch,
            paths_relative_to: "work_dir",
            summary: $summary,
            diff: $diff,
            artifacts: $artifacts
        }' > "$out"
}

# Count non-empty lines in a file; 0 if the file is missing or empty.
_summary_count() {
    local file="$1" n
    [[ -f "$file" ]] || { echo 0; return; }
    # `grep -c .` already prints the count (including "0") on its own, but it
    # EXITS 1 when there is no match. A trailing `|| echo 0` would then ALSO
    # fire and append a second line, yielding "0\n0" - which is invalid JSON
    # when handed to `jq --argjson`. Swallow the non-zero exit with `|| true`
    # (no extra output) and default to 0 only if grep printed nothing at all.
    n="$(grep -c . "$file" 2>/dev/null || true)"
    echo "${n:-0}"
}

# Count lines matching an extended regex; 0 if the file is missing/empty.
# Used where one finding spans several lines (e.g. trufflehog's text output,
# where each finding opens with "Found verified result" / "Found unverified
# result" followed by detector/raw/file lines) so a plain line count would
# overstate findings - and would count tool banners as findings.
_summary_count_matching() {
    local file="$1" re="$2" n
    [[ -f "$file" ]] || { echo 0; return; }
    n="$(grep -cE "$re" "$file" 2>/dev/null || true)"
    echo "${n:-0}"
}

# Emit a JSON array of the non-empty, trimmed lines of a file (compact, one
# call). Missing/empty file -> []. Lines are sorted & de-duplicated so the
# array is a stable set, which keeps diffs meaningful.
_summary_json_array() {
    local file="$1"
    # Treat missing AND empty files the same: an existing-but-empty file must
    # not fall through to the pipeline below, where a no-match grep returns 1
    # and (under 'set -o pipefail') would both trip the fallback and emit jq's
    # own [], yielding invalid "[]\n[]".
    if [[ ! -s "$file" ]]; then
        echo "[]"
        return
    fi
    # strip surrounding whitespace, drop blank lines (sed, not grep, so an
    # all-blank file still exits 0), unique-sort, then let jq do the JSON
    # string escaping via raw-input slurp.
    sed 's/[[:space:]]*$//; s/^[[:space:]]*//; /^$/d' "$file" \
        | sort -u \
        | jq -R . | jq -s . 2>/dev/null || echo "[]"
}

# Extract "host:port" pairs for open TCP ports from an smap/nmap .gnmap file.
# Prefers the resolved hostname in parentheses, falls back to the IP. Output is
# one host:port per line (unsorted); callers pipe through _summary_json_array.
_summary_open_ports_from_gnmap() {
    local gnmap="$1"
    [[ -f "$gnmap" ]] || return 0
    awk '
        /Host:/ {
            # host token: prefer "(hostname)" when present, else the IP in $2
            host = $2
            if (match($0, /\(([^)]+)\)/)) {
                host = substr($0, RSTART+1, RLENGTH-2)
            }
            # isolate the "Ports:" section
            p = index($0, "Ports:")
            if (p == 0) next
            ports = substr($0, p+6)
            n = split(ports, arr, ",")
            for (i = 1; i <= n; i++) {
                # each entry looks like: 80/open/tcp//http///
                split(arr[i], f, "/")
                portnum = f[1]; gsub(/[^0-9]/, "", portnum)
                state = f[2]
                if (portnum != "" && state == "open") {
                    print host ":" portnum
                }
            }
        }
    ' "$gnmap" 2>/dev/null || true
}

module_run() {
    log_info "Building structured run summary"

    local now_epoch now_iso ts
    now_epoch="$(date +%s)"
    now_iso="$(date -u -d "@${now_epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
        || date -u -r "${now_epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
        || date -u '+%Y-%m-%dT%H:%M:%SZ')"
    ts="$(date -u -d "@${now_epoch}" '+%Y%m%dT%H%M%SZ' 2>/dev/null \
        || date -u -r "${now_epoch}" '+%Y%m%dT%H%M%SZ' 2>/dev/null \
        || date -u '+%Y%m%dT%H%M%SZ')"

    # --- Resolve input paths -------------------------------------------------
    local sub_all="${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS]}"
    local sub_live="${DIRS[SUBDOMAINS]}/${FILES[LIVE_SUBDOMAINS]}"
    local sub_200="${DIRS[SUBDOMAINS]}/${FILES[SUBDOMAINS_200]}"
    local sub_wild="${DIRS[SUBDOMAINS]}/${FILES[WILDCARD_SUBDOMAINS]}"
    local sub_redir="${DIRS[SUBDOMAINS]}/${FILES[REDIRECTED_TO_SUBDOMAINS]}"

    local web_servers="${DIRS[SCANS]}/${FILES[WEB_SERVERS]}"
    local gnmap="${DIRS[SCANS_SMAP]}/open_ports.gnmap"

    local takeover="${DIRS[SUBDOMAIN_TAKEOVER]}/${FILES[TAKEOVER_RESULTS]}"
    local graphql="${DIRS[GRAPHQL]}/${FILES[GRAPHQL_ENDPOINTS]}"
    local api_docs="${DIRS[API_DOCS]}/${FILES[API_DOCS_ENDPOINTS]}"
    local wordpress="${DIRS[WORDPRESS]}/${FILES[WORDPRESS_SITES]}"

    local js_endpoints="${DIRS[JS_ENDPOINTS]}/${FILES[JS_ENDPOINTS]}"
    local urls_wp="${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITH_PARAMS_UNIQ]}"
    local urls_wop="${DIRS[URLS_ARTIFACTS]}/${FILES[URLS_WITHOUT_PARAMS_UNIQ]}"
    local urls_live_wp="${DIRS[URLS]}/${FILES[LIVE_URLS_WITH_PARAMS]}"
    local urls_live_wop="${DIRS[URLS]}/${FILES[LIVE_URLS_WITHOUT_PARAMS]}"
    local params="${DIRS[PARAMETERS]}/${FILES[PARAMETERS]}"

    local emails="${DIRS[CREDENTIALS]}/${FILES[EMAILS]}"
    local leak_ep="${DIRS[CREDENTIALS]}/${FILES[LEAKED_EMAIL_PASSWD]}"
    local leak_up="${DIRS[CREDENTIALS]}/${FILES[LEAKED_USERNAME_PASSWD]}"

    local secrets_js="${DIRS[SECRETS]}/${FILES[JSHUNTER_ALL]}"
    local secrets_th="${DIRS[SECRETS]}/${FILES[TRUFFLEHOG_ALL]}"
    local secrets_jl="${DIRS[SECRETS]}/${FILES[JSLUICE_ALL]}"

    local asn_ranges="${DIRS[ASN]}/${FILES[ASN_RANGES]}"
    local ips_ssl="${DIRS[SHODAN]}/${FILES[IPS_FROM_SSL]}"
    local ips_org="${DIRS[SHODAN]}/${FILES[IPS_FROM_ORG]}"
    local ips_src="${DIRS[SCANS]}/${FILES[IPS_FROM_SOURCES]}"
    local ips_smap="${DIRS[SCANS]}/${FILES[IPS_FROM_SMAP]}"

    # --- Core surface arrays (used for diffing) ------------------------------
    local subdomains_json live_json http200_json open_ports_json
    subdomains_json="$(_summary_json_array "$sub_all")"
    live_json="$(_summary_json_array "$sub_live")"
    http200_json="$(_summary_json_array "$sub_200")"

    local open_ports_tmp
    open_ports_tmp="$(mktemp "${TMPDIR:-/tmp}/sf_ports.XXXXXX")"
    _summary_open_ports_from_gnmap "$gnmap" > "$open_ports_tmp"
    open_ports_json="$(_summary_json_array "$open_ports_tmp")"
    rm -f "$open_ports_tmp"

    # --- Finding / surface lists (smaller, also embedded in full) ------------
    local takeover_json graphql_json api_json wordpress_json
    takeover_json="$(_summary_json_array "$takeover")"
    graphql_json="$(_summary_json_array "$graphql")"
    api_json="$(_summary_json_array "$api_docs")"
    wordpress_json="$(_summary_json_array "$wordpress")"

    # --- Module status map from checkpoints ----------------------------------
    local modules_json="{}"
    local warnings_total=0
    local m cp_done cp_skip cp_start cp_warn st at warn_n
    for m in "${MODULES_ORDER[@]}"; do
        cp_done="${DIRS[CHECKPOINTS_DIR]}/${m}.done"
        cp_skip="${DIRS[CHECKPOINTS_DIR]}/${m}.skipped"
        cp_start="${DIRS[CHECKPOINTS_DIR]}/${m}.start"
        cp_warn="${DIRS[CHECKPOINTS_DIR]}/${m}.warnings"
        st="not_started"; at="null"
        if [[ -f "$cp_done" ]]; then
            st="complete"; at="$(cat "$cp_done" 2>/dev/null || echo null)"
        elif [[ -f "$cp_skip" ]]; then
            st="skipped"; at="$(cat "$cp_skip" 2>/dev/null || echo null)"
        elif [[ -f "$cp_start" ]]; then
            st="in_progress"; at="null"
        fi
        # This module is necessarily mid-run while it writes the summary (its
        # .done checkpoint lands only after module_run returns), so it would
        # otherwise always report itself "in_progress". Record it as complete
        # as of this summary's generation time.
        if [[ "$m" == "$MODULE_NAME" ]]; then
            st="complete"; at="$now_epoch"
        fi
        [[ "$at" =~ ^[0-9]+$ ]] || at="null"
        warn_n=0
        [[ -s "$cp_warn" ]] && warn_n="$(_summary_count "$cp_warn")"
        warnings_total=$(( warnings_total + warn_n ))
        modules_json="$(jq --arg name "$m" --arg st "$st" --argjson at "$at" --argjson warn "$warn_n" \
            '. + {($name): {status: $st, at: $at, warnings: $warn}}' <<< "$modules_json")"
    done

    # --- Assemble summary.json ----------------------------------------------
    local summary_file="${DIRS[SUMMARIES]}/summary-${ts}.json"
    local latest_file="${DIRS[WORK_DIR]}/${FILES[RUN_SUMMARY]}"

    jq -n \
        --argjson schema "$SUMMARY_SCHEMA_VERSION" \
        --arg domain "$DOMAIN" \
        --arg generated_at "$now_iso" \
        --argjson generated_at_epoch "$now_epoch" \
        --argjson modules "$modules_json" \
        --argjson warnings_total "$warnings_total" \
        --argjson subdomains "$subdomains_json" \
        --argjson live "$live_json" \
        --argjson http200 "$http200_json" \
        --argjson wildcard_n "$(_summary_count "$sub_wild")" \
        --argjson redirected_n "$(_summary_count "$sub_redir")" \
        --argjson open_ports "$open_ports_json" \
        --argjson web_servers_n "$(_summary_count "$web_servers")" \
        --argjson asn_n "$(_summary_count "$asn_ranges")" \
        --argjson ips_ssl "$(_summary_count "$ips_ssl")" \
        --argjson ips_org "$(_summary_count "$ips_org")" \
        --argjson ips_src "$(_summary_count "$ips_src")" \
        --argjson ips_smap "$(_summary_count "$ips_smap")" \
        --argjson urls_wp "$(_summary_count "$urls_wp")" \
        --argjson urls_wop "$(_summary_count "$urls_wop")" \
        --argjson urls_live_wp "$(_summary_count "$urls_live_wp")" \
        --argjson urls_live_wop "$(_summary_count "$urls_live_wop")" \
        --argjson js_endpoints_n "$(_summary_count "$js_endpoints")" \
        --argjson params_n "$(_summary_count "$params")" \
        --argjson takeover "$takeover_json" \
        --argjson graphql "$graphql_json" \
        --argjson api_docs "$api_json" \
        --argjson wordpress "$wordpress_json" \
        --argjson secrets_js "$(_summary_count "$secrets_js")" \
        --argjson secrets_th "$(_summary_count_matching "$secrets_th" '^Found (un)?verified result')" \
        --argjson secrets_jl "$(_summary_count "$secrets_jl")" \
        --argjson emails_n "$(_summary_count "$emails")" \
        --argjson leak_ep "$(_summary_count "$leak_ep")" \
        --argjson leak_up "$(_summary_count "$leak_up")" \
        '{
            schema_version: $schema,
            tool: "ScopeFinder",
            domain: $domain,
            generated_at: $generated_at,
            generated_at_epoch: $generated_at_epoch,
            warnings_total: $warnings_total,
            modules: $modules,
            surface: {
                subdomains:          { count: ($subdomains | length), items: $subdomains },
                live_subdomains:     { count: ($live | length),       items: $live },
                http_200_subdomains: { count: ($http200 | length),    items: $http200 },
                wildcard_subdomains: { count: $wildcard_n },
                redirected_subdomains: { count: $redirected_n },
                open_ports:          { count: ($open_ports | length), items: $open_ports },
                web_servers:         { count: $web_servers_n },
                asn_ranges:          { count: $asn_n },
                ips: {
                    from_ssl: $ips_ssl, from_org: $ips_org,
                    from_sources: $ips_src, from_smap: $ips_smap
                },
                urls: {
                    with_params: $urls_wp, without_params: $urls_wop,
                    live_with_params: $urls_live_wp, live_without_params: $urls_live_wop,
                    js_endpoints: $js_endpoints_n, parameters: $params_n
                }
            },
            findings: {
                subdomain_takeover: { count: ($takeover | length), items: $takeover },
                graphql_endpoints:  { count: ($graphql | length),  items: $graphql },
                api_docs_endpoints: { count: ($api_docs | length), items: $api_docs },
                wordpress_sites:    { count: ($wordpress | length), items: $wordpress },
                secrets: { jshunter: $secrets_js, trufflehog: $secrets_th, jsluice: $secrets_jl },
                credentials: { emails: $emails_n, leaked_email_passwd: $leak_ep, leaked_username_passwd: $leak_up }
            }
        }' > "$summary_file"

    if [[ ! -s "$summary_file" ]]; then
        log_error "Failed to generate summary JSON"
        return 1
    fi

    # --- Diff against the PREVIOUS baseline ----------------------------------
    # The baseline is the newest timestamped summary that is NOT the one we just
    # wrote. Using the summaries/ history (not the root summary.json, which we
    # are about to repoint) keeps the baseline stable across repeated diffs.
    local baseline_file=""
    baseline_file="$(find "${DIRS[SUMMARIES]}" -maxdepth 1 -name 'summary-*.json' \
        ! -name "$(basename "$summary_file")" -type f 2>/dev/null \
        | sort | tail -n1)"

    local diff_ts_file="${DIRS[SUMMARIES]}/diff-${ts}.json"
    local diff_latest="${DIRS[WORK_DIR]}/${FILES[RUN_DIFF]}"

    if [[ -n "$baseline_file" && -s "$baseline_file" ]]; then
        log_info "Diffing against baseline: $(basename "$baseline_file")"
        # jq -s slurps [current, baseline]; array subtraction yields new items.
        jq -s \
            --argjson schema "$SUMMARY_SCHEMA_VERSION" \
            --arg current_file "$(basename "$summary_file")" \
            --arg baseline_file "$(basename "$baseline_file")" \
            '
            .[0] as $cur | .[1] as $base |
            {
                schema_version: $schema,
                tool: "ScopeFinder",
                domain: $cur.domain,
                generated_at: $cur.generated_at,
                current:  { file: $current_file,  generated_at: $cur.generated_at },
                baseline: { file: $baseline_file, generated_at: $base.generated_at },
                new: {
                    subdomains:      (($cur.surface.subdomains.items // [])      - ($base.surface.subdomains.items // [])),
                    live_subdomains: (($cur.surface.live_subdomains.items // []) - ($base.surface.live_subdomains.items // [])),
                    open_ports:      (($cur.surface.open_ports.items // [])      - ($base.surface.open_ports.items // []))
                },
                removed: {
                    subdomains:      (($base.surface.subdomains.items // [])      - ($cur.surface.subdomains.items // [])),
                    live_subdomains: (($base.surface.live_subdomains.items // []) - ($cur.surface.live_subdomains.items // [])),
                    open_ports:      (($base.surface.open_ports.items // [])      - ($cur.surface.open_ports.items // []))
                }
            }
            | .counts = {
                new_subdomains:      (.new.subdomains | length),
                new_live_subdomains: (.new.live_subdomains | length),
                new_open_ports:      (.new.open_ports | length),
                removed_subdomains:      (.removed.subdomains | length),
                removed_live_subdomains: (.removed.live_subdomains | length),
                removed_open_ports:      (.removed.open_ports | length)
            }
            ' "$summary_file" "$baseline_file" > "$diff_ts_file" || true

        if [[ -s "$diff_ts_file" ]]; then
            cp -f "$diff_ts_file" "$diff_latest"
            local n_sub n_live n_ports
            n_sub="$(jq -r '.counts.new_subdomains' "$diff_ts_file" 2>/dev/null || echo '?')"
            n_live="$(jq -r '.counts.new_live_subdomains' "$diff_ts_file" 2>/dev/null || echo '?')"
            n_ports="$(jq -r '.counts.new_open_ports' "$diff_ts_file" 2>/dev/null || echo '?')"
            log_info "New since baseline: ${n_sub} subdomains, ${n_live} live hosts, ${n_ports} open ports"
        else
            log_warn "Diff generation produced no output"
            rm -f "$diff_ts_file"
        fi
    else
        log_info "No previous summary found - establishing baseline (no diff produced)"
    fi

    # --- Repoint the stable "latest" summary ---------------------------------
    cp -f "$summary_file" "$latest_file"

    # --- Export manifest (where the full data lives) -------------------------
    local export_file="${DIRS[WORK_DIR]}/${FILES[RUN_EXPORT]}"
    if _summary_write_export "$export_file" "$now_iso" "$now_epoch" && [[ -s "$export_file" ]]; then
        log_info "Export manifest:    $export_file"
    else
        log_warn "Failed to write export manifest"
        rm -f "$export_file"
    fi

    log_info "Summary written to: $latest_file"
    log_info "Timestamped copy:   $summary_file"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up run_summary artifacts"
    rm -f "${TMPDIR:-/tmp}"/sf_ports.* 2>/dev/null || true
}
