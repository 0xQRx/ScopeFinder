
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
  - API Keys:
   - Set the required API keys as environment variables in your shell configuration file and **RELOAD** your shell `source ~/.zshrc` (e.g., `~/.zshrc`, `~/.bashrc`):
     ```bash
     export SHODAN_API_KEY=your_shodan_api_key
     export DEHASHED_EMAIL=your_dehashed_email
     export DEHASHED_API_KEY=your_dehashed_api_key
     export HUNTERIO_API_KEY=your_hunterio_api_key
     export PDCP_API_KEY=your_projectdiscovery_api_key
     ```
- **Ensure that golang in Dockerfile matches your arch. Default `amd64`.**

## Config Files
**Some tools require specific configuration files for additional API keys, remove `.example` extention from ALL config files**:
- **Waymore**: `.config/waymore/config.yml`
  ```yaml
  URLSCAN_API_KEY: your_urlscan_api_key
  VIRUSTOTAL_API_KEY: your_virustotal_api_key
  ```
- **Subfinder**: `.config/subfinder/provider-config.yaml`
  ```yaml
  shodan:
      - your_shodan_api_key
  ```

## Build the Docker Image
Run the following command to build the Docker image:
```bash
docker build -t scopefinder .
```

## Create an Alias, add ScopeFinder to your PATH

- Add `export SCOPEFINDER_PATH=/path/to/scopefinder/folder` to your shell configuration file and reload `source ~/.zshrc` (e.g., `~/.bashrc` or `~/.zshrc`).

Add the following alias to your shell configuration file (e.g., `~/.bashrc` or `~/.zshrc`):
```bash
alias ScopeFinder='docker run --rm -it \
  -e SHODAN_API_KEY="${SHODAN_API_KEY}" \
  -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \
  -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \
  -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \
  -e PDCP_API_KEY="${PDCP_API_KEY}" \
  -e PATH="/usr/local/go/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/go/bin:/go/bin" \
  -v "${SCOPEFINDER_PATH}/.config/:/root/.config" \
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

All results will be saved in the current working directory from where tool was run.

## Output example

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
│   │   └── webservers_ip_domain.txt
│   ├── subdomains
│   │   ├── subdomains.txt
│   │   ├── subdomains_to_crawl.txt
│   │   └── wildcard_subdomains.txt
│   └── urls
│       ├── URLs_with_params.txt
│       ├── URLs_without_params.txt
│       ├── artifacts
│       │   ├── JS_URL_endpoints.txt
│       │   ├── katana_crawled_URLS.txt
│       │   └── waymore_URLS.txt
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

