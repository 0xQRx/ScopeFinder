#!/bin/bash
# Environment configuration and directory structure

# Initialize directory paths for a domain
init_dirs() {
    local domain="${1:-$DOMAIN}"

    # Core directories
    DIRS[WORK_DIR]="${domain}"
    DIRS[CHECKPOINTS_DIR]="${domain}/.checkpoints"

    # Main result categories (like original STAGE_1 structure)
    DIRS[SUBDOMAINS]="${domain}/subdomains"
    DIRS[EMAILS]="${domain}/emails"
    DIRS[URLS]="${domain}/urls"
    DIRS[URLS_ARTIFACTS]="${domain}/urls/artifacts"
    DIRS[URLS_BURP]="${domain}/urls/burp_scanner"
    DIRS[URLS_LINKFINDER]="${domain}/urls/linkfinder_output"
    DIRS[SCANS]="${domain}/scans"
    DIRS[SCANS_SMAP]="${domain}/scans/smap_results"
    DIRS[HTTPX]="${domain}/httpx"
    DIRS[HTTPX_OUTPUT]="${domain}/httpx/output"
    DIRS[HTTPX_RESPONSE]="${domain}/httpx/output/response"
    DIRS[HTTPX_SCREENSHOT]="${domain}/httpx/output/screenshot"
    DIRS[WORDPRESS]="${domain}/wordpress"
    DIRS[WORDPRESS_SCANS]="${domain}/wordpress/wpscan"
    DIRS[SECRETS]="${domain}/secrets"
    DIRS[SECRETS_ARTIFACTS]="${domain}/secrets/artifacts"
    DIRS[CLOUD]="${domain}/cloud"
    DIRS[SHODAN]="${domain}/shodan"
    DIRS[SHODAN_ARTIFACTS]="${domain}/shodan/artifacts"
    DIRS[JS_DOWNLOADED]="${domain}/urls/artifacts/downloaded_js_files"
    DIRS[JS_ENDPOINTS]="${domain}/urls/artifacts"
    DIRS[PARAMETERS]="${domain}/urls/parameters"
    DIRS[PARAMETERS_ARTIFACTS]="${domain}/urls/parameters/artifacts"
    DIRS[ASN]="${domain}/asn"
    DIRS[ASN_SMAP]="${domain}/asn/smap_results"
    DIRS[DORKS]="${domain}/dorks"

    # Downloaded/raw data directories (in urls/artifacts to match original)
    DIRS[DOWNLOADED_DATA]="${domain}/urls/artifacts/downloaded_data"
    DIRS[WAYMORE_DATA]="${domain}/urls/artifacts/waymore_downloaded_data"
    DIRS[KATANA_DATA]="${domain}/urls/artifacts/katana_downloaded_data"

    # SSL cert analysis creates TLD-specific folders dynamically
    DIRS[SSL_CERTS_BASE]="${domain}"
}

# Global directory mappings
declare -A DIRS

# Standard file names used across steps
declare -A FILES=(
    [SUBDOMAINS]="subdomains.txt"
    [LIVE_SUBDOMAINS]="live_subdomains.txt"
    [WILDCARD_SUBDOMAINS]="wildcard_subdomains.txt"
    [EMAILS]="emails.txt"
    [LEAKED_CREDS]="leaked_credentials.txt"
    [URLS_WITH_PARAMS]="urls_with_params.txt"
    [URLS_WITHOUT_PARAMS]="urls_without_params.txt"
    [URLS_WITH_PARAMS_UNIQ]="urls_with_params_uniq.txt"
    [URLS_WITHOUT_PARAMS_UNIQ]="urls_without_params_uniq.txt"
    [LIVE_URLS_WITH_PARAMS]="live_urls_with_params_uniq.txt"
    [LIVE_URLS_WITHOUT_PARAMS]="live_urls_without_params_uniq.txt"
    [JS_ENDPOINTS]="js_endpoints.txt"
    [OPEN_PORTS]="open_ports.txt"
    [WEB_SERVERS]="webservers.txt"
    [ASN_RANGES]="asn_ip_ranges.txt"
    [HTTPX_OUTPUT]="httpx_output.txt"
    [PARAMETERS]="uniq_params.txt"
    [WORDPRESS_SITES]="wordpress_sites.txt"
    [JSHUNTER_ALL]="jshunter_all.txt"
    [TRUFFLEHOG_ALL]="trufflehog_all.txt"
    [IPS_FROM_SSL]="ips_from_ssl_certs.txt"
    [IPS_FROM_ORG]="ips_belong_to_org.txt"
    [IPS_FROM_SOURCES]="ips_from_open_sources.txt"
    [ORGS_LIST]="orgs_list.txt"
    [SELECTED_ORG]="selected_org.txt"
    [CLOUDRECON_RAW]="cloudrecon_raw.json"
    [TOP_LEVEL_DOMAINS]="top_level_domains.txt"
    [CLOUD_SNI_DOMAINS]="domain_from_cloud_sni.txt"
    [BURP_URLS]="burp_urls_with_params.txt"
    [BURP_GAP_URLS]="burp_gap_urls_with_params.txt"
    [BURP_X8_URLS]="burp_urls_with_x8_custom_params.txt"
    [COLLECTED_URLS]="collected_urls.txt"
    [CRAWLED_URLS]="katana_crawled_urls.txt"
)

# Tool-specific proxy configurations
declare -A PROXY_FLAGS=(
    [httpx]="-http-proxy"
    [katana]="-proxy"
    # Tools without proxy support:
    # smap, subfinder, waymore
)

# Export environment for child processes
export_env() {
    export DOMAIN
    export HTTP_PROXY_URL
    export -A DIRS
    export -A FILES
    export -A PROXY_FLAGS
}