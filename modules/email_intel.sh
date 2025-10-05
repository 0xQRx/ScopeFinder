#!/bin/bash
# Email and credential intelligence gathering

MODULE_NAME="email_intel"
MODULE_DESC="Gather emails and leaked credentials using Hunter.io and DeHashed APIs"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[EMAILS]}"
    mkdir -p "${DIRS[EMAILS]}/artifacts"

    # Set up output files
    EMAILS_FILE="${DIRS[EMAILS]}/${FILES[EMAILS]}"
    CREDS_FILE="${DIRS[EMAILS]}/${FILES[LEAKED_CREDS]}"
}

module_run() {
    log_info "Gathering email intelligence for: $DOMAIN"

    # Hunter.io search
    if [[ -n "${HUNTERIO_API_KEY:-}" ]]; then
        log_info "Searching Hunter.io..."
        curl -s "https://api.hunter.io/v2/domain-search?domain=${DOMAIN}&api_key=${HUNTERIO_API_KEY}" | \
            jq -r '.data.emails[].value' >> "$EMAILS_FILE" 2>/dev/null || true
    else
        log_warn "Skipping Hunter.io - HUNTERIO_API_KEY not set"
    fi

    # DeHashed search
    if [[ -n "${DEHASHED_API_KEY:-}" ]]; then
        log_info "Searching DeHashed..."

        local dehashed_response="${DIRS[EMAILS]}/artifacts/dehashed_raw.json"
        curl -s -X POST 'https://api.dehashed.com/v2/search' \
            --header "Dehashed-Api-Key: $DEHASHED_API_KEY" \
            --header "Content-Type: application/json" \
            --data-raw "{\"query\": \"$DOMAIN\", \"size\": 10000}" > "$dehashed_response" 2>/dev/null || true

        # Extract emails
        jq -r '.entries[] | .email[]? | select(. != null and . != "")' "$dehashed_response" >> "$EMAILS_FILE" 2>/dev/null || true

        # Extract credential pairs
        jq -r '
            reduce .entries[] as $item ({};
                if ($item.email and $item.password and ($item.email | length > 0) and ($item.password | length > 0))
                then
                    reduce $item.email[] as $e (.; .[$e] = ((.[$e] // []) + $item.password))
                else . end
            )
            | to_entries
            | map(.value |= unique)
            | .[]
            | "\(.key): \(.value[])"
        ' "$dehashed_response" >> "$CREDS_FILE" 2>/dev/null || true
    else
        log_warn "Skipping DeHashed - DEHASHED_API_KEY not set"
    fi

    # Deduplicate results
    dedupe_file "$EMAILS_FILE"
    dedupe_file "$CREDS_FILE"

    # Count results
    local email_count=0
    local creds_count=0
    [[ -f "$EMAILS_FILE" ]] && email_count=$(wc -l < "$EMAILS_FILE")
    [[ -f "$CREDS_FILE" ]] && creds_count=$(wc -l < "$CREDS_FILE")

    log_info "Found $email_count unique emails and $creds_count credential pairs"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up email intelligence artifacts"
}