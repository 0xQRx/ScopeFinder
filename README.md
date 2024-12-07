
# ScopeFinder

**ScopeFinder** is a comprehensive tool for automated domain enumeration and analysis. It installs necessary tools, performs passive and active scans, and organizes results into structured output files.

## Features

- **Automated Installation**:
  - Installs all required tools if not already present: `subfinder`, `waymore`, `httpx`, `smap`, `crtsh-tool`, `shosubgo`, `subbrute`, `CloudRecon`, and `asnmap`.
  - Ensures required dependencies like `jq`, `pipx`, and `gcc` are installed.
- **Passive Analysis**:
  - Subdomain enumeration using multiple sources and tools.
  - URL discovery with `waymore`.
  - Email and leaked credential searches using Hunter.io and DeHashed APIs.
- **Active Analysis**:
  - HTTP probing, banner grabbing, technology detection, and screenshots.
  - Port scanning with `smap`.
  - ASN range analysis and IP scanning.
  - SSL certificate data extraction and subdomain classification.
- **Output Management**:
  - Organized and deduplicated results stored in domain-specific directories.
  - Stage-based analysis with `STAGE_1` for domain-focused tasks and `STAGE_2` for ASN and IP-centric scans.

## Requirements

1. **Golang**:
   - Install from [https://go.dev/](https://go.dev/).
   - Ensure `GOBIN` is in your `PATH`:
     ```bash
     export PATH=$PATH:$HOME/go/bin
     ```
2. **Pipx**:
   - Install from [pipx documentation](https://pypa.github.io/pipx/):
     ```bash
     python3 -m pip install --user pipx
     python3 -m pipx ensurepath
     ```
3. **API Keys**:
   - Set the required API keys as environment variables in your shell configuration file (e.g., `~/.zshrc`, `~/.bashrc`):
     ```bash
     export SHODAN_API_KEY=your_shodan_api_key
     export DEHASHED_EMAIL=your_dehashed_email
     export DEHASHED_API_KEY=your_dehashed_api_key
     export HUNTERIO_API_KEY=your_hunterio_api_key
     export PDCP_API_KEY=your_projectdiscovery_api_key
     ```
4. **Dependencies**:
   - Ensure all tools (`jq`, `subfinder`, `waymore`, etc.) are installed. The script attempts automatic installation if they are missing.

## Usage

1. Clone or download ScopeFinder.
2. Set your API keys as described above.
3. Run the script with:
   ```bash
   sudo ./ScopeFinder.sh domain
   ```
4. Review output in the generated domain directory (`STAGE_1` for passive and domain-based analysis, `STAGE_2` for ASN/IP-focused scans).

### Options

- **Help Menu**: Run with `-h` or `--help` to display usage and feature details:

  ```
  Usage: sudo ./ScopeFinder.sh [domain]

  This script automates the enumeration and analysis of a domain. It performs tasks like subdomain enumeration, email and credential searches, URL finding, port scanning, and active enumeration with banner grabbing and screenshots.

  Prerequisites:
    Ensure the following environment variables are set before running:
      - SHODAN_API_KEY      : Your Shodan API key. (paid)
      - DEHASHED_EMAIL      : Your DeHashed account email. (paid)
      - DEHASHED_API_KEY    : Your DeHashed API key. (paid)
      - HUNTERIO_API_KEY    : Your Hunter.io API key. (free)
      - PDCP_API_KEY        : Your ProjectDiscovery API key. (free)

  Options:
    -h, --help             Display this help menu and exit.

  Example:
    sudo ./ScopeFinder.sh example.com
  ```

## Output

Results are saved in domain-specific folders:

- **`STAGE_1`**: Domain-focused passive and active analysis:
  - `subdomains.txt`: Enumerated subdomains.
  - `wildcard_subdomains.txt`: Wildcard subdomains.
  - `emails.txt`: Extracted emails.
  - `leaked_credential_pairs.txt`: Emails with leaked credentials.
  - `waymore_URLS.txt`: URLs discovered by Waymore.
  - `open_ports.txt`: Ports discovered by Smap.
  - `httpx_output.txt`: HTTPX execution log.
  - `output/`: Folder containing HTTPX results (banner grabbing and screenshots).

- **`STAGE_2`**: ASN and IP-focused analysis:
  - `asn_ip_ranges.txt`: ASN-derived IP ranges.
  - `webservers_ip_domain.txt`: Identified webservers (IP and domain pairs).
  - `CloudRecon_raw.json`: SSL certificate data.
  - `top_level_domains.txt`: Extracted top-level domains.
  - Subdomain classifications by TLD with wildcard and non-wildcard entries.

## IMPORTANT

- **HTTPX Issue**:
  - Kali Linux ships with a default `httpx` version. This script requires the GO version, which may require removal of the preinstalled version.
  - The first run of `httpx` will download Chromium; a reboot may be necessary for full functionality.

---

# Docker Setup Instructions

## Prerequisites
- Install Docker on your system.
  ```
  sudo apt update && sudo apt install -y docker.io && sudo systemctl enable docker --now && sudo usermod -aG docker $USER
  ```
- Ensure the following environment variables are set:
  - `SHODAN_API_KEY`: Your Shodan API key (paid).
  - `DEHASHED_EMAIL`: Your DeHashed account email (paid).
  - `DEHASHED_API_KEY`: Your DeHashed API key (paid).
  - `HUNTERIO_API_KEY`: Your Hunter.io API key (free).
  - `PDCP_API_KEY`: Your ProjectDiscovery API key (free).
- Ensure that golang in Dockerfile matches your arch. Default `amd64`.

## Config Files on Host Machine
Some tools require specific configuration files for additional API keys:
- **Waymore**: `~/.config/waymore/config.yml`
  ```yaml
  URLSCAN_API_KEY: your_urlscan_api_key
  VIRUSTOTAL_API_KEY: your_virustotal_api_key
  ```
- **Subfinder**: `~/.config/subfinder/provider-config.yaml`
  ```yaml
  resolvers:
    - 8.8.8.8
    - 1.1.1.1
  providers:
    shodan:
      - your_shodan_api_key
  ```

## Build the Docker Image
Run the following command to build the Docker image:
```bash
docker build -t scopefinder .
```

## Create an Alias
Add the following alias to your shell configuration file (e.g., `~/.bashrc` or `~/.zshrc`):
```bash
alias ScopeFinder='docker run --rm -it \
  -e SHODAN_API_KEY="${SHODAN_API_KEY}" \
  -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \
  -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \
  -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \
  -e PDCP_API_KEY="${PDCP_API_KEY}" \
  -e PATH="/usr/local/go/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/go/bin:/go/bin" \
  -v "$HOME/.config/waymore:/root/.config/waymore" \
  -v "$HOME/.config/subfinder:/root/.config/subfinder" \
  -v "$(pwd):/output" \
  scopefinder'
```

## Usage
Reload your shell configuration:
```bash
source ~/.bashrc
```
Run the tool with the alias:
```bash
ScopeFinder example.com
```
All results will be saved in the current working directory.

