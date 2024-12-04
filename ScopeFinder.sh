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
    echo "    - SHODAN_API_KEY      : Your Shodan API key."
    echo "    - DEHASHED_EMAIL      : Your DeHashed account email."
    echo "    - DEHASHED_API_KEY    : Your DeHashed API key."
    echo "    - HUNTERIO_API_KEY    : Your Hunter.io API key."
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
    echo
    echo "Output:"
    echo "  Results are saved in a folder named after the domain:"
    echo "    - subdomains.txt            : Enumerated subdomains."
    echo "    - wildcard_subdomains.txt   : Wildcard subdomains."
    echo "    - emails.txt                : Extracted emails."
    echo "    - leaked_credential_pairs.txt : Emails with their associated leaked credentials."
    echo "    - waymore_URLS.txt          : URLs discovered by Waymore."
    echo "    - open_ports.txt                : Ports discovered by Smap."
    echo "    - httpx_output.txt          : httpx execution log."
    echo "    - output(folder with httpx results)          : Banner grabbing and screenshot details."
    echo
    echo "Dependencies:"
    echo "  This script requires the following tools to be installed:"
    echo "    - jq, subfinder, waymore, httpx, smap, crtsh-tool, shosubgo."
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

echo "All required environment variables are set."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure Golang is installed
if ! command_exists go; then
    echo "Golang is not installed. Please install it first."
    echo "Download and install from https://go.dev/"
    exit 1
fi

# Ensure GOBIN is in PATH
if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
    echo "Please add GOBIN to your PATH: export PATH=\$PATH:\$HOME/go/bin"
    echo "Add it to your shell configuration file (e.g., ~/.zshrc or ~/.bashrc)."
    exit 1
fi

# Ensure pipx is installed
if ! command_exists pipx; then
    echo "Pipx is not installed. Installing pipx..."
    python3 -m pip install --user pipx
    python3 -m pipx ensurepath
fi

# Ensure jq is installed
if ! command_exists jq; then
    echo "jq is not installed. Installing jq..."
    apt update && apt install jq -y
fi

# Function to check and install tools
check_and_install_tools() {
    echo "Checking and installing tools..."

    # Subfinder
    if ! command_exists subfinder; then
        echo "Installing subfinder..."
        go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
    fi

    # waymore
    if ! command_exists waymore; then
        echo "Installing waymore..."
        pipx install git+https://github.com/xnl-h4ck3r/waymore.git -v
    fi

    # httpx
    if ! command_exists httpx; then
        echo "Installing httpx..."
        go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
    fi

    # smap
    if ! command_exists smap; then
        echo "Installing smap..."
        go install -v github.com/s0md3v/smap/cmd/smap@latest
    fi

    # crtsh-tool
    if ! command_exists crtsh-tool; then
        echo "Installing crtsh-tool..."
        GOPRIVATE=github.com/0xQRx/crtsh-tool go install github.com/0xQRx/crtsh-tool/cmd/crtsh-tool@latest
    fi

    # shosubgo
    if ! command_exists shosubgo; then
        echo "Installing shosubgo..."
        go install github.com/incogbyte/shosubgo@latest
    fi

    echo "All required tools are installed."
}

# Run the tool installation check
check_and_install_tools

# Handle input (single domain)
DOMAIN="$1"

echo "Processing domain: $DOMAIN"

# Create a directory for the domain
mkdir -p "$DOMAIN"
cd "$DOMAIN" || exit

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

# Port scanning with smap
echo "Running Port scanning with smap..."
smap -iL subdomains.txt -oS open_ports.txt

# Active: Banner Grabbing / Screenshots
echo "Running banner grabbing and taking screenshots with httpx..."
httpx -status-code -title -tech-detect -list "subdomains.txt" -ss -o "httpx_output.txt" -no-color > /dev/null 2>&1

# Return to the parent directory
cd - || exit

echo "All tasks completed."
