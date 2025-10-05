# ScopeFinder

**ScopeFinder** is a comprehensive tool for automated domain enumeration with a modular architecture for flexibility and extensibility.

## 📋 Prerequisites

### Install Docker

**MacOS:**
https://www.docker.com/products/docker-desktop/

**Linux:**
```bash
sudo apt update && sudo apt install -y docker.io && sudo systemctl enable docker --now && sudo usermod -aG docker $USER
```

## 🔨 Build Instructions

1. Clone the repository:
```bash
git clone https://github.com/0xQRx/ScopeFinder.git
cd ScopeFinder/
```

2. Build the Docker image:
```bash
./build.sh
```

The build script will automatically detect your architecture and provide setup instructions upon completion.

## ⚙️ Configuration

### API Keys Setup

Add these environment variables to your shell configuration (`~/.bashrc` or `~/.zshrc`):

```bash
# SCOPEFINDER Configuration
export URLSCAN_API_KEY="your_urlscan_api_key"
export VIRUSTOTAL_API_KEY="your_virustotal_api_key"
export SHODAN_API_KEY="your_shodan_api_key"
export DEHASHED_API_KEY="your_dehashed_api_key"
export DEHASHED_EMAIL="your_dehashed_email"
export HUNTERIO_API_KEY="your_hunterio_api_key"
export PDCP_API_KEY="your_projectdiscovery_api_key"
export WPSCAN_API_KEY="your_wpscan_api_key"
export SCOPEFINDER_PATH="/path/to/scopefinder"
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

### Shell Functions

Add these convenience functions to your shell configuration:

```bash
# Run ScopeFinder
ScopeFinder() {
  # Check if scripts exist
  if [[ ! -f "${SCOPEFINDER_PATH}/ScopeFinder.sh" ]]; then
    echo "Error: ScopeFinder.sh not found at ${SCOPEFINDER_PATH}/ScopeFinder.sh"
    echo "Please set SCOPEFINDER_PATH to the correct directory"
    return 1
  fi

  docker run --rm -it \
    --entrypoint "/bin/bash" \
    -e SHODAN_API_KEY="${SHODAN_API_KEY}" \
    -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \
    -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \
    -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \
    -e WPSCAN_API_KEY="${WPSCAN_API_KEY}" \
    -e URLSCAN_API_KEY="${URLSCAN_API_KEY}" \
    -e VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY}" \
    -e PDCP_API_KEY="${PDCP_API_KEY}" \
    -v "${SCOPEFINDER_PATH}/ScopeFinder.sh:/opt/ScopeFinder.sh" \
    -v "${SCOPEFINDER_PATH}/lib:/opt/lib" \
    -v "${SCOPEFINDER_PATH}/modules:/opt/modules" \
    -v "${SCOPEFINDER_PATH}/.config:/root/.config" \
    -v "$(pwd):/output" \
    -w /output \
    scopefinder \
    -c "chmod +x /opt/ScopeFinder.sh && /opt/ScopeFinder.sh $*"
}

# Access container shell for running individual tools
sf-run() {
  docker run --rm -it \
    --entrypoint "/bin/bash" \
    -e SHODAN_API_KEY="${SHODAN_API_KEY}" \
    -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \
    -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \
    -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \
    -e WPSCAN_API_KEY="${WPSCAN_API_KEY}" \
    -e URLSCAN_API_KEY="${URLSCAN_API_KEY}" \
    -e VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY}" \
    -e PDCP_API_KEY="${PDCP_API_KEY}" \
    -v "${SCOPEFINDER_PATH}/.config:/root/.config" \
    -v "$(pwd):/output" \
    -w /output \
    scopefinder -c "$*"
}
```

Reload your shell configuration:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

## 📖 Usage

### Basic Commands

```bash
# Run full enumeration
ScopeFinder example.com

# Show help
ScopeFinder --help

# Check module completion status
ScopeFinder example.com --status

# List all available modules
ScopeFinder --list-modules
```

### Advanced Options

```bash
# Re-run specific completed modules
ScopeFinder example.com --replay wordpress_scan,secret_scan

# Reset all checkpoints
ScopeFinder example.com --reset

# Dry run (show what would be executed)
ScopeFinder example.com --dry-run

# Run with proxy
ScopeFinder example.com --proxy http://127.0.0.1:8080
```

### Running Individual Tools

```bash
# Access container shell
sf-run

# Run specific tools directly
sf-run subfinder -d example.com
sf-run nuclei -u https://example.com
sf-run trufflehog filesystem /output/example.com
```

## 🤝 Contributing

Contributions are welcome! To add a new module:

1. Create a new module file in `modules/`:
```bash
#!/bin/bash
MODULE_NAME="my_module"
MODULE_DESC="Description of my module"

module_init() {
    # Initialize directories
}

module_run() {
    # Main logic
}

module_cleanup() {
    # Cleanup on failure
}
```

2. Register in `lib/registry.sh`:
```bash
declare -a MODULES_ORDER=(
    # ... existing modules ...
    "my_module"
)
```

## 🙏 Acknowledgments

ScopeFinder integrates many excellent tools from the security community. Special thanks to all tool authors and contributors.

## 🔗 Integration

Use the [ActiveScan Kicker](https://github.com/0xQRx/BurpPlugins/tree/master/ActiveScanKicker) Burp Suite extension to perform audits on URLs prepared for Burp's active scanner.