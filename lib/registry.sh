#!/bin/bash
# Module registry and management

# Ordered list of modules - this determines execution order
declare -a MODULES_ORDER=(
    "google_dorks_generator" # Generates google dorks
    "shodan_search"        # Shodan IP search (with org selection)
    "subdomain_enum"       # Subdomain enumeration (multiple sources)
    "ip_discovery"         # IP discovery from open sources
    "email_intel"          # Email and leaked credential search
    "waymore_archive_recon" # URL collection from web archives (waymore)
    "smap_port_scan"            # Port scanning on subdomains
    "httpx_subdomain_probe"        # Service probing with httpx
    "wordpress_scan"       # WordPress detection and scanning
    "katana_web_crawl"            # Web crawling with katana
    "xnLinkFinder_url_extract"          # URL extraction from downloaded content
    "extract_params"       # URL sorting and parameter extraction
    "httpx_url_probe"            # URL deduplication and live probing
    "js_download"          # JavaScript file download
    "linkfinder_analysis"  # Find links (linkfinder)
    "secret_scan"          # Secret scanning (jshunter, trufflehog)
    "cloud_recon"          # Cloud reconnaissance (msftrecon, SNI)
    # "burp_prep"          # Burp Suite prep and x8 fuzzing - commented to match original
    "asn_discovery"        # ASN range discovery
    "asn_port_scan"           # Port scanning on ASN ranges
    "asn_recon"            # SSL certificate analysis with CloudRecon
)

# Module metadata
declare -A MODULE_DESC
declare -A MODULE_LOADED

# Register a module
register_module() {
    local name=$1
    local desc=$2
    MODULE_DESC[$name]="$desc"
    MODULE_LOADED[$name]=true
}

# Load all module files
load_all_modules() {
    for module in "${MODULES_ORDER[@]}"; do
        local module_file="${SCRIPT_DIR}/modules/${module}.sh"
        if [[ -f "$module_file" ]]; then
            # Extract metadata without running the module
            local name=$(grep "^MODULE_NAME=" "$module_file" | cut -d'=' -f2 | tr -d '"')
            local desc=$(grep "^MODULE_DESC=" "$module_file" | cut -d'=' -f2- | tr -d '"')
            if [[ -n "$name" ]]; then
                register_module "$name" "${desc:-No description}"
            fi
        else
            log_warn "Module file not found: $module_file"
        fi
    done
}

# List all available modules
list_all_modules() {
    # Load module descriptions first
    load_all_modules

    echo "Available modules (in execution order):"
    echo ""
    local index=1
    for module in "${MODULES_ORDER[@]}"; do
        if [[ -f "${SCRIPT_DIR}/modules/${module}.sh" ]]; then
            printf "%2d. %-20s - %s\n" "$index" "$module" "${MODULE_DESC[$module]:-No description}"
        else
            printf "%2d. %-20s - %s\n" "$index" "$module" "(not found)"
        fi
        ((index++))
    done
}

# Show module completion status
show_module_status() {
    echo "Module completion status for domain: $DOMAIN"
    echo ""
    printf "%-20s %-15s %-20s\n" "Module" "Status" "Completed At"
    printf "%-20s %-15s %-20s\n" "------" "------" "------------"

    for module in "${MODULES_ORDER[@]}"; do
        local status="❌ Not started"
        local completed_at="-"

        if [[ -f "${DIRS[CHECKPOINTS_DIR]}/${module}.done" ]]; then
            status="✅ Complete"
            local timestamp=$(cat "${DIRS[CHECKPOINTS_DIR]}/${module}.done")
            completed_at=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$timestamp" '+%Y-%m-%d %H:%M:%S')
        elif [[ -f "${DIRS[CHECKPOINTS_DIR]}/${module}.start" ]]; then
            status="⏳ In progress"
        fi

        printf "%-20s %-15s %-20s\n" "$module" "$status" "$completed_at"
    done
}

# Determine which modules to run based on options
determine_modules_to_run() {
    local -n result=$1
    result=()

    for module in "${MODULES_ORDER[@]}"; do
        result+=("$module")
    done
}