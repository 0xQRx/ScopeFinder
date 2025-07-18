#!/bin/bash

# Help function to display usage
usage() {
    echo "Usage: ScopeFinder [domain]"
    echo
    echo "This script automates reconnaissance tasks on a given domain. It:"
    echo " - Checks and installs required tools"
    echo " - Enumerates subdomains from multiple sources"
    echo " - Finds emails and leaked credentials"
    echo " - Discovers URLs and crawls them for more data"
    echo " - Performs port scans to find open services"
    echo " - Uses Httpx for banner grabbing, screenshots, and tech detection"
    echo " - Searches for secrets in JavaScript endpoints"
    echo " - Analyzes ASN ranges and extracts SSL certificate details"
    echo " - Organizes outputs into well-structured directories"
    echo
    echo "Environment variables required:"
    echo " - SHODAN_API_KEY"
    echo " - DEHASHED_API_KEY"
    echo " - HUNTERIO_API_KEY"
    echo " - PDCP_API_KEY"
    echo " - URLSCAN_API_KEY"
    echo " - VIRUSTOTAL_API_KEY"
    echo " - WPSCAN_API_KEY"
    echo
    echo "Options:"
    echo " -h, --help       Show this help and exit"
    echo
    echo "Example:"
    echo " ScopeFinder example.com"
    echo
    exit 0
}


# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# Ensure the script is run with at least one domain
if [ "$#" -eq 0 ]; then
    echo "Error: No domain provided."
    usage
fi

# Function to check if a variable is set and not empty
check_env_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    if [ -z "$var_value" ]; then
        echo "Error: $var_name is not set or is empty."
        exit 1
    fi
}

# Check each environment variable
check_env_var "SHODAN_API_KEY"
check_env_var "DEHASHED_API_KEY"
check_env_var "HUNTERIO_API_KEY"
check_env_var "PDCP_API_KEY"
check_env_var "URLSCAN_API_KEY"
check_env_var "VIRUSTOTAL_API_KEY"
check_env_var "WPSCAN_API_KEY"

echo "All required environment variables are set."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure prerequisites
ensure_prerequisites() {
    if ! command_exists go; then
        echo "Golang is not installed. Please install it first from https://go.dev/"
        exit 1
    fi

    if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
        echo "Add GOBIN to your PATH: export PATH=\$PATH:\$HOME/go/bin"
        echo "Update your shell configuration file (e.g., ~/.zshrc or ~/.bashrc)."
        exit 1
    fi

    if ! command_exists jq; then
        echo "Installing required libraries..."
        apt update && apt install -y \
            libnss3 libxss1 libatk1.0-0 libatk-bridge2.0-0 libdrm2 libx11-xcb1 \
            libxcomposite1 libxcursor1 libxdamage1 libxi6 libxtst6 libasound2 \
            libpangocairo-1.0-0 libcups2 libxkbcommon0 fonts-liberation libgbm-dev \
            libpango1.0-0 libjpeg-dev libxrandr2 xdg-utils wget gcc jq pipx > /dev/null
        pipx ensurepath > /dev/null
    fi

    if [ -f /usr/bin/httpx ]; then
        echo "Removing existing /usr/bin/httpx."
        sudo rm /usr/bin/httpx
    fi
}

# Install tools if missing and verify installation
install_tool() {
    local tool_name=$1
    local install_command=$2

    if ! command_exists "$tool_name"; then
        echo "Installing $tool_name..."
        if eval "$install_command"; then
            if command_exists "$tool_name"; then
                echo "$tool_name installed successfully."
            else
                echo "ERROR: $tool_name failed to install. Please install it manually."
            fi
        else
            echo "ERROR: $tool_name installation command failed. Please install it manually."
        fi
    fi
}

check_and_install_tools() {
    echo "Checking and installing tools..."

    install_tool "subfinder" "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest > /dev/null"
    #install_tool "jsluice" "go install github.com/BishopFox/jsluice/cmd/jsluice@latest > /dev/null"
    install_tool "waymore" "pipx install git+https://github.com/xnl-h4ck3r/waymore.git > /dev/null"
    install_tool "msftrecon" "pipx install git+https://github.com/0xQRx/msftrecon.git > /dev/null"
    install_tool "linkfinder" "pipx install git+https://github.com/0xQRx/LinkFinder.git --include-deps > /dev/null"
    install_tool "xnLinkFinder" "pipx install git+https://github.com/xnl-h4ck3r/xnLinkFinder.git > /dev/null"
    install_tool "httpx" "go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest > /dev/null"
    install_tool "katana" "CGO_ENABLED=1 go install github.com/projectdiscovery/katana/cmd/katana@latest > /dev/null"
    install_tool "smap" "go install -v github.com/s0md3v/smap/cmd/smap@latest > /dev/null"
    install_tool "crtsh-tool" "GOPRIVATE=github.com/0xQRx/crtsh-tool go install github.com/0xQRx/crtsh-tool/cmd/crtsh-tool@main > /dev/null"
    install_tool "shosubgo" "go install github.com/incogbyte/shosubgo@latest > /dev/null"
    install_tool "CloudRecon" "go install github.com/g0ldencybersec/CloudRecon@latest > /dev/null"
    install_tool "asnmap" "go install github.com/projectdiscovery/asnmap/cmd/asnmap@latest > /dev/null"
    install_tool "jshunter" "GOPRIVATE=github.com/0xQRx/jshunter go install -v github.com/0xQRx/jshunter@main > /dev/null"
    install_tool "godigger" "GOPRIVATE=github.com/0xQRx/godigger go install -v github.com/0xQRx/godigger@main > /dev/null"
    install_tool "urldedup" "GOPRIVATE=github.com/0xQRx/URLDedup go install -v github.com/0xQRx/URLDedup/cmd/urldedup@main > /dev/null"
    install_tool "uro" "pipx install uro > /dev/null"
    install_tool "x8" "cargo install x8 > /dev/null"
    install_tool "wpscan" "gem install wpscan > /dev/null"
    install_tool "trufflehog" "git clone https://github.com/trufflesecurity/trufflehog.git > /dev/null && cd trufflehog && go install > /dev/null && cd .. && rm -rf trufflehog"
    echo "All tools checked."
}

# Ensure prerequisites and run tool installation
ensure_prerequisites
check_and_install_tools

check_config_warnings() {
    echo "WARNING: For optimal performance, ensure the following configuration files are created and properly populated:"
    echo "  1. ~/.config/waymore/config.yml"
    echo "     - Keys to include:"
    echo "       - URLSCAN_API_KEY: your_urlscan_api_key"
    echo "       - VIRUSTOTAL_API_KEY: your_virustotal_api_key"
    echo "  2. ~/.config/subfinder/provider-config.yaml"
    echo "     - Populate with the necessary API keys for supported providers."
    echo "Refer to the respective tool documentation for configuration details."
    echo 
    echo "============================================================"
    echo "           The tool will start in 10 seconds.               "
    echo "       If you wish to exit, press Ctrl + C now.            "
    echo "============================================================"
    sleep 10
}

#check_config_warnings

# Handle input (single domain)
DOMAIN="$1"
DOMAIN_BASE_NAME=$(echo "$DOMAIN" | awk -F'.' '{print $(NF-1)}')

STAGE1="STAGE_1"
STAGE2="STAGE_2"
echo "Processing domain: $DOMAIN"

# Create a directory for the domain
mkdir -p "$DOMAIN"
cd "$DOMAIN" || exit

#Create a directory for a STAGE 1
mkdir -p "$STAGE1"
cd "$STAGE1" || exit

echo "Running STAGE 1. Once it's done, you can start working with the results in ${STAGE1} directory."

# Passive: Shodan IP search
echo "Running Shodan IP search..."

# 1. URL Encode Domain
ENCODED_DOMAIN=$(jq -rn --arg d "$DOMAIN" '$d|@uri')

# 2. Shodan Search by Cert Subject CN
curl -s "https://api.shodan.io/shodan/host/search?key=${SHODAN_API_KEY}&query=ssl.cert.subject.cn:${ENCODED_DOMAIN}" > shodan_ssl_subject_raw_output.json

# 3. Extract IP:Port/Transport (no ORG)
jq -r '.matches[] | "\(.ip_str):\(.port)/\(.transport)"' shodan_ssl_subject_raw_output.json > IPs_from_ssl_certs.txt

# 4. Extract ORGs into separate file
jq -r '.matches[] | .org // "UNKNOWN"' shodan_ssl_subject_raw_output.json | sort -u > orgs_list.txt

# 5. Prompt for ORG Selection
echo -e "\nDiscovered ORGs (Pick one that belongs to a client to scan):"
mapfile -t ORG_LIST < orgs_list.txt

echo "0) Skip org scan"
for i in "${!ORG_LIST[@]}"; do
  printf "%d) %s\n" "$((i+1))" "${ORG_LIST[$i]}"
done

read -p "Select an ORG to scan by number (0 to skip): " CHOICE
if [[ "$CHOICE" == "0" ]]; then
  echo "Skipping org-based scan."
else
  ORG="${ORG_LIST[$((CHOICE - 1))]}"

  # 6. Encode Selected ORG
  ENCODED_ORG=$(jq -rn --arg org "$ORG" '$org|@uri')

  # 7. Shodan Search by ORG
  curl -s "https://api.shodan.io/shodan/host/search?key=${SHODAN_API_KEY}&query=org:\"${ENCODED_ORG}\"" > shodan_org_raw_output.json

  # 8. Extract IP:Port/Transport
  jq -r '.matches[] | "\(.ip_str):\(.port)/\(.transport)"' shodan_org_raw_output.json > IPs_belong_to_org.txt
fi

# Passive: Subdomain enumeration
echo "Running Subdomain enumeration with subfinder..."
subfinder -d "$DOMAIN" -all -recursive -silent >> "subdomains.txt"

echo "Running Subdomain enumeration with godigger..."
godigger -domain "$DOMAIN" -search subdomains -t 20 >> "subdomains.txt"

echo "Running Subdomain enumeration with crtsh-tool..."
crtsh-tool --domain "$DOMAIN" | grep -v '[DEBUG]' | grep -v '\*.' >> "subdomains.txt"
crtsh-tool --domain "$DOMAIN" | grep -v '[DEBUG]' | grep '\*.' >> "wildcard_subdomains.txt"

echo "Running Subdomain enumeration with shosubgo..."
shosubgo -d "$DOMAIN" -s "$SHODAN_API_KEY" | grep -v 'No subdomains found' | grep -v 'apishodan.JsonSubDomain' | {
   grep -v '\*.' >> "subdomains.txt"
   grep '\*.' >> "wildcard_subdomains.txt"
}

# Sorting and deduplicating subdomains
echo "Sorting and deduplicating subdomains..."
sort -u "subdomains.txt" -o "subdomains.txt"
sort -u "wildcard_subdomains.txt" -o "wildcard_subdomains.txt"

echo "Subdomain enumeration completed for $DOMAIN."

echo "Searching for IPs"
godigger -domain "$DOMAIN" -search ips -t 20 > IPs_from_open_sources.txt
sort -u "IPs_from_open_sources.txt" -o "IPs_from_open_sources.txt"

echo "Searching for emails on hunter.io"
curl -s "https://api.hunter.io/v2/domain-search?domain=${DOMAIN}&api_key=${HUNTERIO_API_KEY}" | jq -r '.data.emails[].value' >> "emails.txt"

# echo "Searching for leaked credentials on DeHashed"

echo "Searching for leaked credentials on DeHashed"
curl -s -X POST 'https://api.dehashed.com/v2/search' \
  --header "Dehashed-Api-Key: $DEHASHED_API_KEY" \
  --header "Content-Type: application/json" \
  --data-raw "{\"query\": \"$DOMAIN\", \"size\": 10000}" >> dehashed_raw.json

# Extract Emails (iterate over each email in the email array)
jq -r '.entries[] | .email[]? | select(. != null and . != "")' dehashed_raw.json >> "emails.txt" 2>/dev/null

# Extract credential pairs by reducing over entries:
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
' dehashed_raw.json >> leaked_credential_pairs.txt 2>/dev/null

# Sorting and deduplicating emails
echo "Sorting and deduplicating emails..."
sort -u "emails.txt" -o "emails.txt"
sort -u "leaked_credential_pairs.txt" -o "leaked_credential_pairs.txt"

echo "Finished email and credential search..."

# Passive: URL finder
echo "Running URL finder and downloading archived URLs with waymore - it might take several hours..."
mkdir waymore_downloaded_data
waymore -i "$DOMAIN" -mode B -f -oU "collected_URLs.txt" -url-filename -oR waymore_downloaded_data > /dev/null 2>&1
sort -u "collected_URLs.txt" -o "collected_URLs.txt"

# Passive: Port scanning with smap
echo "Running Port scanning with smap..."
mkdir smap_results
smap -iL subdomains.txt -oA smap_results/open_ports
grep -E "443|80" smap_results/open_ports.gnmap | awk '/Host:/ {if ($3 ~ /\(/) {print $2, $3} else {print $2, "(No domain)"}}' | sed 's/[()]//g' >> webservers_ip_domain.txt

# Active: Banner Grabbing / Screenshots
echo "Running banner grabbing and taking screenshots for subdomains with httpx..."
httpx -status-code -title -tech-detect -list "subdomains.txt" -sid 5 -ss -fr -o "httpx_output.txt" -no-color > /dev/null 2>&1 

# Extract good codes from httpx output file
grep '200]' httpx_output.txt | while read -r line; do
    # Extract original URL and subdomain
    original_url=$(echo "$line" | awk '{print $1}')
    original_subdomain=$(echo "$original_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

    # Extract status codes
    status_codes=$(echo "$line" | grep -oP '\[\K[^\]]+(?=\])' | head -n1)

    if [[ "$status_codes" == "200" ]]; then
        if [[ "$original_subdomain" == "$DOMAIN" || "$original_subdomain" == *.$DOMAIN ]]; then
            echo "$original_subdomain"
        fi
    else
        final_url=$(echo "$line" | grep -oP '\[https?://[^\]]+\]' | tail -n1 | tr -d '[]')
        final_subdomain=$(echo "$final_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

        if [[ ( "$original_subdomain" == "$DOMAIN" || "$original_subdomain" == *.$DOMAIN ) && \
              ( "$final_subdomain" == "$DOMAIN" || "$final_subdomain" == *.$DOMAIN ) ]]; then
            echo "$final_subdomain"
        fi
    fi
done | sort -u >> LIVE_subdomains.txt

# Extract WordPress sites from httpx output
grep -iE '\[.*wordpress.*\]' httpx_output.txt | awk '{print $1}' | sort -u > wordpress_sites.txt

mkdir -p wpscan
# Check if there are any WordPress sites to scan
if [ -s wordpress_sites.txt ]; then
    echo "Scanning WordPress sites with WPScan..."

    while read -r SUBDOMAIN; do
        OUTPUT_FILE="wpscan/wpscan_$(echo "$SUBDOMAIN" | sed 's|https\?://||g; s|/|_|g').txt"
        wpscan -t 1 --api-token="$WPSCAN_API_KEY" --enumerate --throttle 500 -o "$OUTPUT_FILE" -f cli-no-color --rua --disable-tls-checks --update --url "$SUBDOMAIN"
    done < wordpress_sites.txt
else
    rm wordpress_sites.txt
    rm -rf wpscan
    echo "No WordPress sites found. Skipping WPScan."
fi

mv wordpress_sites.txt wpscan/ 2>/dev/null

# Crawling with katana
echo "Crawling subdomains with katana... it will take some time."
mkdir katana_downloaded_data
katana -list LIVE_subdomains.txt -headless -no-sandbox -jc -d 2 -c 10 -p 2 -rl 10 -rlm 120 -timeout 5 -retry 2 -o katana_crawled_URLS.txt -silent -sr -srd katana_downloaded_data -ef png,jpg,jpeg,gif,svg,woff,woff2,ttf,eot,otf,ico,webp,mp4,pdf,css > /dev/null 2>&1
sort -u "katana_crawled_URLS.txt" -o "katana_crawled_URLS.txt"

# Searching links with xnLinkFinder
echo "Searching for urls in archives using xnLinkFinder..."
xnLinkFinder -i ./waymore_downloaded_data -sp "$DOMAIN" -sf "$DOMAIN" -o xnLinkFinder_output.txt -op xnLinkFinder_parameters.txt -oo xnLinkFinder_out_of_scope_URLs.txt > /dev/null 2>&1
xnLinkFinder -i ./katana_downloaded_data -sp "$DOMAIN" -sf "$DOMAIN" -o xnLinkFinder_output.txt -op xnLinkFinder_parameters.txt -oo xnLinkFinder_out_of_scope_URLs.txt > /dev/null 2>&1

# Process xnLinkFinder_output.txt
grep -vE '^https?://' xnLinkFinder_output.txt >> domain_not_known_xnLinkFinder_output.txt
grep -E '^https?://' xnLinkFinder_output.txt >> temp_xnLinkFinder_output.txt && mv temp_xnLinkFinder_output.txt xnLinkFinder_output.txt
sort -u "xnLinkFinder_output.txt" -o "xnLinkFinder_output.txt"


# Sort URLs, separate with and without parameters
# Extract all URLs with parameters
grep -oP 'https?://[^\s"]+\?[^\s"]*' xnLinkFinder_output.txt >> URLs_with_params.txt
grep -oP 'https?://[^\s"]+\?[^\s"]*' katana_crawled_URLS.txt >> URLs_with_params.txt
grep -oP 'https?://[^\s"]+\?[^\s"]*' collected_URLs.txt >> URLs_with_params.txt
sort -u "URLs_with_params.txt" -o "URLs_with_params.txt"

# Extract all URLs without parameters
grep -oP 'https?://[^\s"]+' xnLinkFinder_output.txt | grep -v '\?' >> URLs_without_params.txt
grep -oP 'https?://[^\s"]+' katana_crawled_URLS.txt | grep -v '\?' >> URLs_without_params.txt
grep -oP 'https?://[^\s"]+' collected_URLs.txt | grep -v '\?' >> URLs_without_params.txt
sort -u "URLs_without_params.txt" -o "URLs_without_params.txt"

# Prep unique and live URLs for Burp Scanner
echo "Probing unique URLs... Building LIVE URL list..."
uro -i URLs_without_params.txt >> URLs_without_params_uniq.txt
uro -i URLs_with_params.txt >> URLs_with_params_uniq.txt

# Extract all parameters
echo "Extracting URL parameters used by the company..."
grep -hoP 'https?://[^\s"<>]+?\?[^\s"<>]*' URLs_with_params_uniq.txt | sed -E 's/.*\?//' | tr '&' '\n' | sed -E 's/=.*//' | sort -u > uniq_params.txt

# urldedup -f URLs_with_params_uniq.txt -ignore "css,js,png,jpg,jpeg,gif,svg,woff,woff2,ttf,eot,otf,ico,webp,mp4,pdf" -examples 1 -validate -t 20 -out-burp BURP_URLs_with_params.txt -out-burp-gap BURP_GAP_URLs_with_params.txt

# Function extracts in-scope URLs that belong to the main specified domain, either from the final redirected page or from the general result if no redirection occurred.

filter_in_scope_urls() {
    local input_file="$1"

    # If the file doesn't exist, just return silently
    if [[ ! -f "$input_file" ]]; then
        echo "⚠️  Skipping: File not found - $input_file" >&2
        return 0
    fi

    grep '200]' "$input_file" | while read -r line; do
        # Extract original URL and host
        original_url=$(echo "$line" | awk '{print $1}')
        original_host=$(echo "$original_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

        # Extract status codes
        status_codes=$(echo "$line" | grep -oP '\[\K[^\]]+(?=\])' | head -n1)

        if [[ "$status_codes" == "200" ]]; then
            if [[ "$original_host" == "$DOMAIN" || "$original_host" == *.$DOMAIN ]]; then
                echo "$original_url"
            fi
        else
            # Extract final redirected URL
            final_url=$(echo "$line" | grep -oP '\[https?://[^\]]+\]' | tail -n1 | tr -d '[]')
            final_host=$(echo "$final_url" | sed -E 's#^https?://([^/@]*@)?##' | cut -d/ -f1)

            if [[ "$original_host" == "$DOMAIN" || "$original_host" == *.$DOMAIN ]]; then
                if [[ "$final_host" == "$DOMAIN" || "$final_host" == *.$DOMAIN ]]; then
                    echo "$final_url"
                fi
            fi
        fi
    done | sort -u
}

# Probe URLs with parameters
httpx -status-code -list URLs_with_params_uniq.txt -fr -no-color -o "httpx_live_links_with_params_output.txt" > /dev/null 2>&1

# Probe URLs without parameters
httpx -status-code -list URLs_without_params_uniq.txt -fr -no-color -o "httpx_live_links_without_params_output.txt" > /dev/null 2>&1

# Function extracts in-scope URLs that belong to the main specified domain, either from the final redirected page or from the general result if no redirection occurred.

filter_in_scope_urls "httpx_live_links_with_params_output.txt" | grep -oP 'https?://[^\s"]+\?[^\s"]*' | grep -Ev '\.js(\?.*)?$' >> LIVE_URLs_with_params_uniq_temp.txt

filter_in_scope_urls "httpx_live_links_without_params_output.txt" | grep -oP 'https?://[^\s"]+\?[^\s"]*' | grep -Ev '\.js(\?.*)?$' >> LIVE_URLs_with_params_uniq_temp.txt

uro -i LIVE_URLs_with_params_uniq_temp.txt >> LIVE_URLs_with_params_uniq.txt
sort -u "LIVE_URLs_with_params_uniq.txt" -o "LIVE_URLs_with_params_uniq.txt"

rm LIVE_URLs_with_params_uniq_temp.txt

# Function extracts in-scope URLs that belong to the main specified domain, either from the final redirected page or from the general result if no redirection occurred.

filter_in_scope_urls "httpx_live_links_with_params_output.txt" | grep -v '\?' >> LIVE_URLs_without_params_uniq_temp.txt

filter_in_scope_urls "httpx_live_links_without_params_output.txt" | grep -v '\?' >> LIVE_URLs_without_params_uniq_temp.txt

uro -i LIVE_URLs_without_params_uniq_temp.txt >> LIVE_URLs_without_params_uniq.txt
sort -u "LIVE_URLs_without_params_uniq.txt" -o "LIVE_URLs_without_params_uniq.txt"

rm LIVE_URLs_without_params_uniq_temp.txt

#Extract all JS files
echo "Downloading JS files.."
grep -E '\.js(\?.*)?$' xnLinkFinder_output.txt | grep -iEv "jquery|jquery-ui|jquery\.min|react|react-dom|angular|angularjs|vue|vue\.min|ember|backbone|underscore|lodash|moment|dayjs|d3|three|chartjs|chart\.js|highcharts|gsap|animejs|popper|bootstrap|semantic-ui|materialize|tailwind|axios|fetch|zepto|modernizr|requirejs|next|nuxt|svelte|lit|redux|mobx|handlebars|mustache|express|rxjs|fastify|inertia|meteor|mithril|knockout|ractive|canjs|alpinejs|solid-js|preact|pixi|leaflet|openlayers|fullcalendar|zurb|enyo|fabric|svg\.js|velocity|vivus|particles\.js|zxcvbn|quill|tinymce|ckeditor|codemirror|highlight|mathjax|pdfjs|videojs|plyr|jwplayer|soundjs|howler|createjs|p5|stats\.js|tracking\.js|fancybox|lightbox|swiper|slick-carousel|flickity|lazysizes|barba|scrollmagic|locomotive|skrollr|headroom|turbolinks|stimulus|alpine\.js|instantclick|htmx|wix|avada|fusion|awb|modernizr|thunderbolt|Blazor|gtm\.js|blazor|win\.js|wp-*" >> JS_URL_endpoints_temp.txt
grep -E '\.js(\?.*)?$' collected_URLs.txt | grep -iEv "jquery|jquery-ui|jquery\.min|react|react-dom|angular|angularjs|vue|vue\.min|ember|backbone|underscore|lodash|moment|dayjs|d3|three|chartjs|chart\.js|highcharts|gsap|animejs|popper|bootstrap|semantic-ui|materialize|tailwind|axios|fetch|zepto|modernizr|requirejs|next|nuxt|svelte|lit|redux|mobx|handlebars|mustache|express|rxjs|fastify|inertia|meteor|mithril|knockout|ractive|canjs|alpinejs|solid-js|preact|pixi|leaflet|openlayers|fullcalendar|zurb|enyo|fabric|svg\.js|velocity|vivus|particles\.js|zxcvbn|quill|tinymce|ckeditor|codemirror|highlight|mathjax|pdfjs|videojs|plyr|jwplayer|soundjs|howler|createjs|p5|stats\.js|tracking\.js|fancybox|lightbox|swiper|slick-carousel|flickity|lazysizes|barba|scrollmagic|locomotive|skrollr|headroom|turbolinks|stimulus|alpine\.js|instantclick|htmx|wix|avada|fusion|awb|modernizr|thunderbolt|Blazor|gtm\.js|blazor|win\.js|wp-*" >> JS_URL_endpoints_temp.txt
grep -E '\.js(\?.*)?$' katana_crawled_URLS.txt | grep -iEv "jquery|jquery-ui|jquery\.min|react|react-dom|angular|angularjs|vue|vue\.min|ember|backbone|underscore|lodash|moment|dayjs|d3|three|chartjs|chart\.js|highcharts|gsap|animejs|popper|bootstrap|semantic-ui|materialize|tailwind|axios|fetch|zepto|modernizr|requirejs|next|nuxt|svelte|lit|redux|mobx|handlebars|mustache|express|rxjs|fastify|inertia|meteor|mithril|knockout|ractive|canjs|alpinejs|solid-js|preact|pixi|leaflet|openlayers|fullcalendar|zurb|enyo|fabric|svg\.js|velocity|vivus|particles\.js|zxcvbn|quill|tinymce|ckeditor|codemirror|highlight|mathjax|pdfjs|videojs|plyr|jwplayer|soundjs|howler|createjs|p5|stats\.js|tracking\.js|fancybox|lightbox|swiper|slick-carousel|flickity|lazysizes|barba|scrollmagic|locomotive|skrollr|headroom|turbolinks|stimulus|alpine\.js|instantclick|htmx|wix|avada|fusion|awb|modernizr|thunderbolt|Blazor|gtm\.js|blazor|win\.js|wp-*" >> JS_URL_endpoints_temp.txt
uro -i JS_URL_endpoints_temp.txt > JS_URL_endpoints.txt
sort -u "JS_URL_endpoints.txt" -o "JS_URL_endpoints.txt"
rm JS_URL_endpoints_temp.txt

mkdir -p downloaded_js_files
cat JS_URL_endpoints.txt | xargs -P10 -I{} bash -c 'url="{}"; hash=$(echo -n "$url" | md5sum | cut -d" " -f1); ext="js"; outfile="downloaded_js_files/${hash}.${ext}"; [ -f "$outfile" ] && { echo "Skipping existing file: $outfile"; exit 0; }; content=$(wget -q --no-check-certificate --retry-connrefused --wait=1 --random-wait --timeout=5 --tries=2 -O - "$url"); [ -n "$content" ] && { echo "// Original URL: $url"; echo "$content"; } > "$outfile"'


# Active: searching for sensitive information in JS files with jshunter 
echo "Searching for urls in JS files using linkfinder and xnLinkFinder..."
mkdir linkfinder_output
linkfinder -i ./downloaded_js_files --out-dir linkfinder_output --unknown-domain unknown_domain_URLs.txt > /dev/null 2>&1
xnLinkFinder -i ./downloaded_js_files -sp "$DOMAIN" -sf "$DOMAIN" -o linkfinder_output/xnLinkFinder_output.txt -op linkfinder_output/xnLinkFinder_parameters.txt -oo linkfinder_output/xnLinkFinder_out_of_scope_URLs.txt > /dev/null 2>&1

echo "Searching for secrets with jshunter..."
jshunter -d downloaded_js_files --recursive -quiet -o jshunter_found_secrets_1.txt 
jshunter -d waymore_downloaded_data --recursive -quiet -o jshunter_found_secrets_2.txt 
jshunter -d katana_downloaded_data --recursive -quiet -o jshunter_found_secrets_3.txt 
cat jshunter_found_secrets_1.txt jshunter_found_secrets_2.txt jshunter_found_secrets_3.txt > jshunter_found_secrets.txt

echo "Searching for secrets with trufflehog..."
trufflehog filesystem --log-level='-1' waymore_downloaded_data >> trufflehog_secrets.txt 2>&1
trufflehog filesystem --log-level='-1' katana_downloaded_data >> trufflehog_secrets.txt 2>&1
trufflehog filesystem --log-level='-1' downloaded_js_files >> trufflehog_secrets.txt 2>&1

echo "Extracting scripts that might have dynamic URLs in them..."
output_file="extracted_inline_scripts/scripts.html"
mkdir -p extracted_inline_scripts
: > "$output_file"  # Clear previous output

declare -A seen_hashes  # Deduplication map

# Folders to scan
folders=("waymore_downloaded_data" "katana_downloaded_data")

for folder in "${folders[@]}"; do
  echo "Processing folder: $folder"

  for src in "$folder"/*; do
    [[ -f "$src" ]] || continue  # skip if not a file

    while IFS= read -r -d '' block; do
      [[ -z "$block" ]] && continue

      # Hash for deduplication
      hash=$(printf "%s" "$block" | md5sum | cut -d' ' -f1)
      [[ -n "${seen_hashes[$hash]}" ]] && continue
      seen_hashes[$hash]=1

      # Check for behavioral patterns
      printf "%s" "$block" | grep -Pqzi '<script(?![^>]*\bsrc=)[^>]*>(?=[\s\S]*?(fetch\(|\.open\(|new\s+XMLHttpRequest|\.send\(|\$\.ajax\(|\$\.get\(|\$\.post\(|\$\.patch\(|\.sendBeacon\(|new\s+WebSocket|new\s+EventSource|postMessage\(|axios\.|io\(|\.write\())[\s\S]*?</script>' || continue

      # Append to output file
      printf "%s\n\n" "$block" >> "$output_file"
    done < <(grep -Pzo '<script(?![^>]*\bsrc=)[^>]*>[\s\S]*?</script>' "$src")
  done
done

# echo "Searching for hidden parameters with x8..."
# cat BURP_GAP_URLs_with_params.txt BURP_URLs_with_params.txt > FUZZ_Params_URLs.txt
# x8 -u FUZZ_Params_URLs.txt -w /wordlists/burp-parameter-names.txt --one-worker-per-host -W2 -O url -o BURP_URLs_with_x8_custom_params.txt --remove-empty > /dev/null 2>&1
# rm FUZZ_Params_URLs.txt

echo "Performing cloud recon..."
mkdir cloud
msftrecon -d "$DOMAIN" >> cloud/msftrecon.txt 2>/dev/null

SNI_URLS=(                         
  "https://kaeferjaeger.gay/sni-ip-ranges/amazon/ipv4_merged_sni.txt"
  "https://kaeferjaeger.gay/sni-ip-ranges/digitalocean/ipv4_merged_sni.txt"
  "https://kaeferjaeger.gay/sni-ip-ranges/google/ipv4_merged_sni.txt"
  "https://kaeferjaeger.gay/sni-ip-ranges/microsoft/ipv4_merged_sni.txt"
  "https://kaeferjaeger.gay/sni-ip-ranges/oracle/ipv4_merged_sni.txt"
)

for url in "${SNI_URLS[@]}"; do
  curl -s "$url" | grep -iE "$DOMAIN|$DOMAIN_BASE_NAME" >> cloud/domain_from_cloud_sni.txt
done


# Cleanup
# Create sub-directories for organization
mkdir -p subdomains emails urls/artifacts shodan/artifacts httpx secrets
# Move subdomain-related files
mv subdomains.txt wildcard_subdomains.txt LIVE_subdomains.txt subdomains/ 2>/dev/null

# Move email and credential-related files
mv emails.txt leaked_credential_pairs.txt dehashed_raw.json emails/ 2>/dev/null

# Move URL-related files
mv domain_not_known_xnLinkFinder_output.txt linkfinder_output/ 2>/dev/null
mv linkfinder_output extracted_inline_scripts LIVE_URLs_with_params_uniq.txt LIVE_URLs_without_params_uniq.txt uniq_params.txt urls/ 2>/dev/null
mv jshunter_found_secrets.txt trufflehog_secrets.txt secrets/ 2>/dev/null
mv downloaded_js_files waymore_downloaded_data katana_downloaded_data xnLinkFinder_output.txt xnLinkFinder_parameters.txt xnLinkFinder_out_of_scope_URLs.txt katana_crawled_URLS.txt collected_URLs.txt JS_URL_endpoints.txt jshunter_found_secrets_1.txt jshunter_found_secrets_2.txt jshunter_found_secrets_3.txt  URLs_with_params.txt URLs_without_params.txt httpx_live_links_with_params_output.txt httpx_live_links_without_params_output.txt URLs_with_params_uniq.txt URLs_without_params_uniq.txt urls/artifacts/ 2>/dev/null

# Move scanning results
mv orgs_list.txt shodan_org_raw_output.json shodan_ssl_subject_raw_output.json shodan/artifacts 2>/dev/null
mv smap_results IPs_from_ssl_certs.txt IPs_belong_to_org.txt shodan/ 2>/dev/null
mv IPs_from_open_sources.txt webservers_ip_domain.txt shodan/ 2>/dev/null

# Move active enumeration results
mv httpx_output.txt httpx/ 2>/dev/null
mv output httpx/ 2>/dev/null

echo "STAGE 1 is finished. You can start working with the results in ${STAGE1} directory."

cd .. || exit
#Create a directory for a STAGE 2
mkdir -p "$STAGE2"
cd "$STAGE2" || exit

echo "Running STAGE 2. Searching and scanning ASN ranges... Once it's done, you can start working with the results in ${STAGE2} directory."

# Run asnmap to obtain ASN ranges if there is any.
echo "Running ASN search with asnmap..."
asnmap -d $DOMAIN_BASE_NAME -silent >> asn_ip_ranges.txt

if [ ! -s asn_ip_ranges.txt ]; then
  echo "No ASN ranges found. STAGE 2 abort."
  cd -
  exit 1
fi

# Port scanning with smap
echo "Running Port scanning with smap..."
mkdir smap_results
smap -iL asn_ip_ranges.txt -oA smap_results/open_ports
grep -E "443|80" smap_results/open_ports.gnmap | awk '/Host:/ {if ($3 ~ /\(/) {print $2, $3} else {print $2, "(No domain)"}}' | sed 's/[()]//g' >> webservers_ip_domain.txt

# Running CloudRecon to obtain SSL Ceritficate information.
echo "Scraping SSL Certificate Data using CloudRecon..."
CloudRecon scrape -i asn_ip_ranges.txt -j >> CloudRecon_raw.json

############# START OF DATA PROCESSING FOR CLOUDRECON #############

# Ensure the output file for TLDs is clean
> top_level_domains.txt

# Extract commonName and categorize by TLD
cat CloudRecon_raw.json | jq -r '.commonName' | while read -r common_name; do
    # Extract top-level domain from commonName
    top_level_domain=$(echo "$common_name" | awk -F'.' '{print $(NF-1)"."$NF}')

    # Add the TLD to the unique TLD file
    echo "$top_level_domain" >> top_level_domains.txt

    # Create the directory for the TLD if it doesn't already exist
    if [[ ! -d "$top_level_domain" ]]; then
        mkdir "$top_level_domain"
    fi

    # Check if it has a wildcard and output accordingly
    if [[ "$common_name" == \** ]]; then
        echo "$common_name" >> "${top_level_domain}/wildcard_subdomains.txt"
    else
        echo "$common_name" | sed 's/\*\.//' >> "${top_level_domain}/subdomains.txt"
    fi

    # Extract SAN entries and append to the appropriate file
    jq -r '.san | split(",")[]' CloudRecon_raw.json | sed 's/^\s*//;s/\s*$//' | grep -v '\*.' | grep "$top_level_domain" >> "${top_level_domain}/subdomains.txt"
done

# Ensure each subdomain file has unique and sorted entries
for dir in */; do
    # Check for and process subdomain files
    if [[ -f "${dir}subdomains.txt" ]]; then
        sort -u "${dir}subdomains.txt" -o "${dir}subdomains.txt"
    fi
    if [[ -f "${dir}wildcard_subdomains.txt" ]]; then
        sort -u "${dir}wildcard_subdomains.txt" -o "${dir}wildcard_subdomains.txt"
    fi
done

# Ensure top-level domains are unique and sorted
sort -u top_level_domains.txt -o top_level_domains.txt

echo "Processing of CloudRecon data complete. Outputs generated for each top-level domain."

############# END OF DATA PROCESSING FOR CLOUDRECON #############

echo "Running banner grabbing and taking screenshots for subdomains with httpx..."
# Loop through each directory in STAGE 2 folder
for dir in */; do
    # Check if subdomains.txt exists in the directory
    if [[ -f "${dir}subdomains.txt" ]]; then
        # Move into the directory
        cd "$dir" || continue

        # Run httpx against subdomains.txt
        echo "Running httpx in directory: $dir"
        httpx -status-code -title -tech-detect -list "subdomains.txt" -sid 5 -ss -o "httpx_output.txt" -no-color > /dev/null 2>&1

        # Return to the parent directory
        cd ..
    fi
done

echo "HTTPX scanning completed for all subdomains."

# Return to the parent directory
cd - || exit

echo "All tasks completed."

