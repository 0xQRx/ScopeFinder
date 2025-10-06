#!/bin/bash
# Secret scanning with jshunter and trufflehog

MODULE_NAME="secret_scan"
MODULE_DESC="Scan for secrets in downloaded content using jshunter and trufflehog"

module_init() {
    # Create output directories
    mkdir -p "${DIRS[SECRETS]}"
    mkdir -p "${DIRS[SECRETS_ARTIFACTS]}"

    # Identify directories to scan with their names
    declare -gA SCAN_TARGETS
    [[ -d "${DIRS[JS_DOWNLOADED]}" ]] && SCAN_TARGETS["downloaded_js"]="${DIRS[JS_DOWNLOADED]}"
    [[ -d "${DIRS[WAYMORE_DATA]}" ]] && SCAN_TARGETS["waymore"]="${DIRS[WAYMORE_DATA]}"
    [[ -d "${DIRS[KATANA_DATA]}" ]] && SCAN_TARGETS["katana"]="${DIRS[KATANA_DATA]}"
}

module_run() {
    log_info "Scanning for secrets in downloaded content"

    if [[ ${#SCAN_TARGETS[@]} -eq 0 ]]; then
        log_warn "No directories to scan for secrets"
        return 0
    fi

    # Run jshunter on each directory with JSON output
    if command -v jshunter &> /dev/null; then
        log_info "Running jshunter..."

        # Temporary file for collecting unique secrets
        local temp_secrets="${DIRS[SECRETS_ARTIFACTS]}/temp_all_secrets.txt"
        > "$temp_secrets"

        for name in "${!SCAN_TARGETS[@]}"; do
            local dir="${SCAN_TARGETS[$name]}"
            if [[ -d "$dir" ]]; then
                # Run jshunter with JSON output
                jshunter -d "$dir" --recursive --quiet --json -o "${DIRS[SECRETS_ARTIFACTS]}/jshunter_${name}.json" 2>/dev/null || true

                # Extract secrets from JSON and add to temp file
                if [[ -f "${DIRS[SECRETS_ARTIFACTS]}/jshunter_${name}.json" ]]; then
                    # Parse JSON to extract unique secret values
                    # Format: [SecretType] Value (Source: filename)
                    # Replace newlines with spaces to keep entries on single lines
                    jq -r '.findings[]? | .source as $src | .categories[]? | .category as $cat | .matches[]? | "[\($cat)] \(.value | gsub("\n"; " ")) (Source: \($src))"' \
                        "${DIRS[SECRETS_ARTIFACTS]}/jshunter_${name}.json" 2>/dev/null >> "$temp_secrets" || true
                fi
            fi
        done

        # Deduplicate secrets based on type and value (ignoring source)
        # This ensures each unique secret appears only once
        if [[ -f "$temp_secrets" ]] && [[ -s "$temp_secrets" ]]; then
            # Extract unique combinations of [Type] and Value, keeping first occurrence with source
            awk -F' \\(Source: ' '
            {
                # Extract the secret part (type and value)
                secret = $1
                # Store full line for first occurrence
                if (!seen[secret]++) {
                    print $0
                }
            }' "$temp_secrets" | sort | sed 's/$/\n/' > "${DIRS[SECRETS]}/${FILES[JSHUNTER_ALL]}"
        else
            > "${DIRS[SECRETS]}/${FILES[JSHUNTER_ALL]}"
        fi

        # Clean up temp file
        rm -f "$temp_secrets"
    else
        log_warn "jshunter not found - skipping"
    fi

    # Run trufflehog on each directory
    if command -v trufflehog &> /dev/null; then
        log_info "Running trufflehog..."
        for name in "${!SCAN_TARGETS[@]}"; do
            local dir="${SCAN_TARGETS[$name]}"
            if [[ -d "$dir" ]]; then
                trufflehog filesystem --log-level='-1' "$dir" > "${DIRS[SECRETS_ARTIFACTS]}/trufflehog_${name}.txt" 2>&1 || true
            fi
        done

        # Combine all trufflehog results
        cat "${DIRS[SECRETS_ARTIFACTS]}"/trufflehog_*.txt > "${DIRS[SECRETS]}/${FILES[TRUFFLEHOG_ALL]}" 2>/dev/null || true
    else
        log_warn "trufflehog not found - skipping"
    fi

    # Log completion
    log_info "Secret scanning completed. Results saved in: ${DIRS[SECRETS]}/"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up secret scan artifacts"
}