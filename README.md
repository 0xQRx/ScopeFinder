
# ScopeFinder

**ScopeFinder** is a comprehensive tool for automated domain enumeration.

# Docker Setup Instructions

## Prerequisites
- Install Docker on your system.

  **MacOS:**
  https://www.docker.com/products/docker-desktop/#

  **Linux:**
  ```
  sudo apt update && sudo apt install -y docker.io && sudo systemctl enable docker --now && sudo usermod -aG docker $USER
  ```

## Build the Docker Image
Run the following command to build the Docker image:
```bash
docker build -t scopefinder .
```

## Config Files

Some integrated tools (e.g., Waymore, Subfinder) require specific configuration files containing API keys. Make sure to:

1. Locate the configuration files in the `.config` directory.
2. Remove the `.example` extension (i.e., rename `config.yml.example` to `config.yml`, etc.).
3. Insert your API keys in the corresponding fields.

- **Waymore**: 
  `.config/waymore/config.yml`
  ```yaml
  URLSCAN_API_KEY: your_urlscan_api_key
  VIRUSTOTAL_API_KEY: your_virustotal_api_key
  ```
- **Subfinder**: 
  `.config/subfinder/provider-config.yaml`
  ```yaml
  shodan:
      - your_shodan_api_key
  ```

## Setting Up Environment Variables

ScopeFinder uses environment variables for various API keys. Add the following to your shell configuration file (e.g., `~/.bashrc`, `~/.zshrc`):

```bash
export SHODAN_API_KEY=your_shodan_api_key
export DEHASHED_EMAIL=your_dehashed_email
export DEHASHED_API_KEY=your_dehashed_api_key
export HUNTERIO_API_KEY=your_hunterio_api_key
export PDCP_API_KEY=your_projectdiscovery_api_key
export URLSCAN_API_KEY=your_urlscan_api_key
export VIRUSTOTAL_API_KEY=your_virustotal_api_key

export SCOPEFINDER_PATH=/path/to/scopefinder/folder

alias ScopeFinder='docker run --rm -it \
  -e URLSCAN_API_KEY="${URLSCAN_API_KEY}" \
  -e VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY}" \
  -e SHODAN_API_KEY="${SHODAN_API_KEY}" \
  -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \
  -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \
  -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \
  -e PDCP_API_KEY="${PDCP_API_KEY}" \
  -e PATH="/root/.cargo/bin:/usr/local/go/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/go/bin:/go/bin" \
  -v "${SCOPEFINDER_PATH}/.config/:/root/.config" \
  -v "${SCOPEFINDER_PATH}/ScopeFinder.sh:/opt/ScopeFinder.sh" \
  -v "$(pwd):/output" \
  scopefinder'
```

Reload your shell configuration:

```bash
source ~/.zshrc
# or
source ~/.bashrc
```

### Usage

Run the tool with the alias:
```bash
ScopeFinder example.com
```

## Running Individual Tools from the Container

To run an individual tool from the container, define the following function in your shell (e.g., in your .bashrc or .zshrc):

```
sf-run() {
  docker run --rm -it \
    --entrypoint "" \
    -e URLSCAN_API_KEY="${URLSCAN_API_KEY}" \
    -e VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY}" \
    -e SHODAN_API_KEY="${SHODAN_API_KEY}" \
    -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \
    -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \
    -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \
    -e PDCP_API_KEY="${PDCP_API_KEY}" \
    -e PATH="/root/.cargo/bin:/usr/local/go/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/go/bin:/go/bin" \
    -v "${SCOPEFINDER_PATH}/.config/:/root/.config" \
    -v "${SCOPEFINDER_PATH}/ScopeFinder.sh:/opt/ScopeFinder.sh" \
    -v "$(pwd):/output" \
    scopefinder "$@"
}
```

You can then run tools from the container like this:

```
sf-run subfinder -d example.com
sf-run trufflehog filesystem /output/target
sf-run katana -u https://example.com
sf-run bash          # Drop into an interactive shell
```

## Output example

All results will be saved in the current working directory from where tool was run.

Use the [ActiveScan Kicker](https://github.com/0xQRx/BurpPlugins/tree/master/ActiveScanKicker) Burp Suite extension to perform an audit on a URL prepared for Burp's active scanner.

```
├── STAGE_1
│   ├── emails
│   │   ├── dehashed_raw.json
│   │   ├── emails.txt
│   │   └── leaked_credential_pairs.txt
│   ├── httpx
│   │   ├── httpx_output.txt
│   │   └── output
│   │       ├── response
│   │       └── screenshot
│   ├── scans
│   │   ├── smap_results
│   │   │   ├── open_ports.gnmap
│   │   │   ├── open_ports.nmap
│   │   │   └── open_ports.xml
│   │   ├── ips.txt
│   │   └── webservers_ip_domain.txt
│   ├── subdomains
│   │   ├── subdomains.txt
│   │   ├── subdomains_to_crawl.txt
│   │   └── wildcard_subdomains.txt
│   └── urls
│       ├── URLs_with_params.txt
│       ├── URLs_without_params.txt
│       ├── URLs_with_params_uniq.txt
│       ├── URLs_without_params_uniq.txt
│       ├── artifacts
│       │   ├── JS_URL_endpoints.txt
│       │   ├── katana_crawled_URLS.txt
│       ├── linkfinder_output
│       │   ├── example_com.txt
│       │   └── dev_example_com.txt
│       ├── burp_scanner
│       │   ├── BURP_GAP_URLs_with_params.txt
│       │   ├── BURP_URLs_with_x8_custom_params.txt
│       │   └── BURP_URLs_with_params.txt
│       └── jshunter_found_secrets.txt
└── STAGE_2
    ├── CloudRecon_raw.json
    ├── asn_ip_ranges.txt
    ├── example-new.co
    │   ├── httpx_output.txt
    │   ├── output
    │   │   ├── response
    │   │   └── screenshot
    │   └── subdomains.txt
    ├── example.com
    │   ├── httpx_output.txt
    │   ├── output
    │   │   ├── response
    │   │   └── screenshot
    │   └── subdomains.txt
    ├── smap_results
    │   ├── open_ports.gnmap
    │   ├── open_ports.nmap
    │   └── open_ports.xml
    ├── top_level_domains.txt
    └── webservers_ip_domain.txt
```

