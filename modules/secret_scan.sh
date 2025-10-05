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

    # Run jshunter on each directory
    if command -v jshunter &> /dev/null; then
        log_info "Running jshunter..."
        for name in "${!SCAN_TARGETS[@]}"; do
            local dir="${SCAN_TARGETS[$name]}"
            if [[ -d "$dir" ]]; then
                jshunter -d "$dir" --recursive -quiet -o "${DIRS[SECRETS_ARTIFACTS]}/jshunter_${name}.txt" 2>/dev/null || true
            fi
        done

        # Combine all jshunter results
        cat "${DIRS[SECRETS_ARTIFACTS]}"/jshunter_*.txt > "${DIRS[SECRETS]}/${FILES[JSHUNTER_ALL]}" 2>/dev/null || true
        dedupe_file "${DIRS[SECRETS]}/${FILES[JSHUNTER_ALL]}"
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