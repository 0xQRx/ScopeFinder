#!/bin/bash

# Ensure the script is run with at least one domain or file containing domains
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 domain"
    exit 1
fi

# Function to extract SHODAN_API_KEY from ~/.zshrc or ~/.bashrc
extract_shodan_key() {
    if [ -f ~/.zshrc ]; then
        grep 'export SHODAN_API_KEY=' ~/.zshrc | sed 's/export SHODAN_API_KEY=//'
    elif [ -f ~/.bashrc ]; then
        grep 'export SHODAN_API_KEY=' ~/.bashrc | sed 's/export SHODAN_API_KEY=//'
    else
        echo ""
    fi
}

# Retrieve SHODAN_API_KEY
SHODAN_API_KEY=$(extract_shodan_key)
if [ -z "$SHODAN_API_KEY" ]; then
    echo "SHODAN_API_KEY is not set in ~/.zshrc or ~/.bashrc. Please add it."
    echo "Example: export SHODAN_API_KEY=your_api_key"
    exit 1
fi

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
subfinder -d "$DOMAIN" -all -silent >> "${DOMAIN}_subdomains.txt"

echo "Running Subdomain enumeration with crtsh-tool..."
crtsh-tool --domain "$DOMAIN" | grep -v '\*.' >> "${DOMAIN}_subdomains.txt"
crtsh-tool --domain "$DOMAIN" | grep '\*.' >> "wildcard_${DOMAIN}_subdomains.txt"

echo "Running Subdomain enumeration with shosubgo..."
shosubgo -d "$DOMAIN" -s "$SHODAN_API_KEY" | grep -v 'No subdomains found' | grep -v 'apishodan.JsonSubDomain' | grep -v '\*.' >> "${DOMAIN}_subdomains.txt"
shosubgo -d "$DOMAIN" -s "$SHODAN_API_KEY" | grep -v 'No subdomains found' | grep -v 'apishodan.JsonSubDomain' | grep '\*.' >> "wildcard_${DOMAIN}_subdomains.txt"

# Sorting and deduplicating subdomains
echo "Sorting and deduplicating subdomains..."
sort -u "${DOMAIN}_subdomains.txt" -o "${DOMAIN}_subdomains.txt"
sort -u "wildcard_${DOMAIN}_subdomains.txt" -o "wildcard_${DOMAIN}_subdomains.txt"

echo "Subdomain enumeration completed for $DOMAIN."

# Passive: URL finder
echo "Running URL finder with waymore..."
waymore -i "$DOMAIN" -mode U -oU "${DOMAIN}_waymore_subs_URLS.txt" > /dev/null 2>&1

# Active: Banner Grabbing / Screenshots
echo "Running banner grabbing and taking screenshots with httpx..."
httpx -status-code -title -tech-detect -list "${DOMAIN}_subdomains.txt" -ss -o "${DOMAIN}_httpx_output.txt" -no-color > /dev/null 2>&1

# Return to the parent directory
cd - || exit

echo "All tasks completed."
