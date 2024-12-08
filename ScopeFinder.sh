#!/bin/bash

# Help function to display usage
usage() {
    echo "Usage: sudo $0 [domain]"
    echo
    echo "This script automates the enumeration and analysis of a domain."
    echo "It performs tasks like subdomain enumeration, email and credential searches,"
    echo "URL finding, port scanning, and active enumeration with banner grabbing and screenshots."
    echo
    echo "Prerequisites:"
    echo "  Ensure the following environment variables are set before running:"
    echo "    - SHODAN_API_KEY      : Your Shodan API key. (paid)"
    echo "    - DEHASHED_EMAIL      : Your DeHashed account email. (paid)"
    echo "    - DEHASHED_API_KEY    : Your DeHashed API key. (paid)"
    echo "    - HUNTERIO_API_KEY    : Your Hunter.io API key. (free)"
    echo "    - PDCP_API_KEY        : Your ProjectDiscovery API key. (free)"
    echo
    echo "Options:"
    echo "  -h, --help             Display this help menu and exit."
    echo
    echo "Example:"
    echo "  sudo $0 example.com"
    echo
    echo "Features:"
    echo "  - Checks for required tools and installs them if missing."
    echo "  - Enumerates subdomains using multiple tools and sources."
    echo "  - Searches for associated emails using Hunter.io."
    echo "  - Finds leaked credentials for the domain using DeHashed."
    echo "  - Extracts unique emails and credential pairs."
    echo "  - Finds URLs passively using Waymore."
    echo "  - Performs port scanning with Smap."
    echo "  - Conducts active enumeration with Httpx."
    echo "  - Analyzes ASN ranges and IPs in STAGE 2."
    echo
    echo "Output:"
    echo "  Results are saved in a folder named after the domain:"
    echo "    - subdomains.txt            : Enumerated subdomains."
    echo "    - wildcard_subdomains.txt   : Wildcard subdomains."
    echo "    - emails.txt                : Extracted emails."
    echo "    - leaked_credential_pairs.txt : Emails with their associated leaked credentials."
    echo "    - waymore_URLS.txt          : URLs discovered by Waymore."
    echo "    - open_ports.txt            : Ports discovered by Smap."
    echo "    - httpx_output.txt          : Httpx execution log."
    echo "    - output(folder with httpx results) : Banner grabbing and screenshot details."
    echo "    - top_level_domains.txt     : Extracted TLDs from SSL certificates."
    echo "    - asn_ip_ranges.txt         : ASN-derived IP ranges."
    echo
    echo "Dependencies:"
    echo "  This script requires the following tools to be installed:"
    echo "    - jq, subfinder, waymore, httpx, smap, crtsh-tool, shosubgo, subbrute, CloudRecon, asnmap."
    echo "  The script will attempt to install missing dependencies automatically."
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
check_env_var "DEHASHED_EMAIL"
check_env_var "DEHASHED_API_KEY"
check_env_var "HUNTERIO_API_KEY"
check_env_var "PDCP_API_KEY"

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
    install_tool "waymore" "pipx install git+https://github.com/xnl-h4ck3r/waymore.git > /dev/null"
    install_tool "httpx" "go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest > /dev/null"
    install_tool "smap" "go install -v github.com/s0md3v/smap/cmd/smap@latest > /dev/null"
    install_tool "crtsh-tool" "GOPRIVATE=github.com/0xQRx/crtsh-tool go install github.com/0xQRx/crtsh-tool/cmd/crtsh-tool@latest > /dev/null"
    install_tool "shosubgo" "go install github.com/incogbyte/shosubgo@latest > /dev/null"
    install_tool "subbrute" "go install github.com/0xQRx/subbrute/cmd/subbrute@latest > /dev/null"
    install_tool "CloudRecon" "go install github.com/g0ldencybersec/CloudRecon@latest > /dev/null"
    install_tool "asnmap" "go install github.com/projectdiscovery/asnmap/cmd/asnmap@latest > /dev/null"
    install_tool "katana" "CGO_ENABLED=1 go install github.com/projectdiscovery/katana/cmd/katana@latest > /dev/null"
    install_tool "jshunter" "go install -v github.com/cc1a2b/jshunter@latest > /dev/null"

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

check_config_warnings

# Handle input (single domain)
DOMAIN="$1"

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

# Passive: Subdomain enumeration
echo "Running Subdomain enumeration with subfinder..."
subfinder -d "$DOMAIN" -all -silent >> "subdomains.txt"

echo "Running Subdomain enumeration with crtsh-tool..."
crtsh-tool --domain "$DOMAIN" | grep -v '\*.' >> "subdomains.txt"
crtsh-tool --domain "$DOMAIN" | grep '\*.' >> "wildcard_subdomains.txt"

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

echo "Searching for emails on hunter.io"
curl -s "https://api.hunter.io/v2/domain-search?domain=${DOMAIN}&api_key=${HUNTERIO_API_KEY}" | jq -r '.data.emails[].value' >> "emails.txt"

echo "Searching for leaked credentials on DeHashed"
curl -s "https://api.dehashed.com/search?query=${DOMAIN}" -u $DEHASHED_EMAIL:$DEHASHED_API_KEY -H 'Accept: application/json' >> dehashed_raw.json

# Extract Emails
jq -r '.entries[] | select(.email != null and .email != "") | .email' dehashed_raw.json >> "emails.txt" 2>/dev/null

# Extract credential pairs
jq -r 'reduce .entries[] as $item ({}; if $item.email != null and $item.email != "" and $item.password != null and $item.password != "" then .[$item.email] += [$item.password] else . end) | to_entries | map(.value |= unique) | .[] | "\(.key): \(.value[])"' dehashed_raw.json >> leaked_credential_pairs.txt 2>/dev/null

# Sorting and deduplicating emails
echo "Sorting and deduplicating emails..."
sort -u "emails.txt" -o "emails.txt"
sort -u "leaked_credential_pairs.txt" -o "leaked_credential_pairs.txt"

echo "Finished email and credential search..."

# Passive: URL finder
echo "Running URL finder with waymore - might take a while..."
waymore -i "$DOMAIN" -mode U -oU "waymore_URLS.txt" > /dev/null 2>&1
sort -u "waymore_URLS.txt" -o "waymore_URLS.txt"

####### START TODO ########

# Active: Crawling using katana

# katana -list subdomain.txt -headless -no-sandbox -jc -d 3 -c 3 -p 3 -rd 1 -rl 5 -rlm 60 -headless -no-sandbox -o katana_crawled_URLS.txt -silent

# Sort URLs, separate with and without parameters

# Extract all URLs with parameters
# grep -oP 'https?://[^\s"]+\?[^\s"]*' file.txt

# Extract all URLs without parameters
# grep -oP 'https?://[^\s"]+' waymore_URLS.txt | grep -v '\?'

#Extract all JS files
# grep '.js' waymore_URLS.txt >> JS_URL_endpoints.txt

# Active: searching for sensitive information in JS files with jshunter 
# jshunter -l JS_URL_endpoints.txt -quiet | grep -v 'MISSING' > jshunter_out.txt

####### END TODO ########

# Passive: Port scanning with smap
echo "Running Port scanning with smap..."
mkdir smap_results
smap -iL subdomains.txt -oA smap_results/open_ports
grep -E "443|80" smap_results/open_ports.gnmap | awk '/Host:/ {if ($3 ~ /\(/) {print $2, $3} else {print $2, "(No domain)"}}' | sed 's/[()]//g' >> webservers_ip_domain.txt

# Active: Banner Grabbing / Screenshots
echo "Running banner grabbing and taking screenshots for subdomains with httpx..."
httpx -status-code -title -tech-detect -list "subdomains.txt" -sid 5 -ss -o "httpx_output.txt" -no-color > /dev/null 2>&1

echo "STAGE 1 is finished. You can start working with the results in ${STAGE1} directory."

cd .. || exit
#Create a directory for a STAGE 2
mkdir -p "$STAGE2"
cd "$STAGE2" || exit

echo "Running STAGE 2. Searching and scanning ASN ranges... Once it's done, you can start working with the results in ${STAGE2} directory."

BASE_NAME=$(echo "$DOMAIN" | awk -F'.' '{print $(NF-1)}')

# Run asnmap to obtain ASN ranges if there is any.
echo "Running ASN search with asnmap..."
asnmap -d $BASE_NAME -silent >> asn_ip_ranges.txt

if [ ! -s asn_ip_ranges.txt ]; then
  echo "No ASN ranges found. STAGE 2 abort."
  cd - || exit
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

echo "Review the extracted subdomains and use the following command to perform DNS brute-forcing with subbrute:
subbrute -d example.com -w dns-names.txt -t 20 -ns 8.8.8.8,1.1.1.1 --depth 3

- Create a custom list of subdomains for your target.
- Keep the number of subdomains below 100 for manageable complexity.
- Increasing depth can significantly increase the workload and time required."

