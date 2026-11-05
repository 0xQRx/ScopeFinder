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

### DNS Resolvers

Before subdomain enumeration, the `resolver_refresh` module fetches a current
public resolver list, validates each resolver with `dig` (it must resolve a
neutral anchor host and must *not* answer a random non-existent name, which
weeds out dead and lying/wildcarding resolvers), and writes a validated
`<domain>/resolvers/resolvers.txt` that `subdomain_enum` passes to subfinder via
`-rlist`. This keeps stale resolver lists from silently degrading DNS
resolution. It degrades gracefully: a failed refresh warns and falls back to a
cache or the tools' built-in defaults rather than failing the run.

Tunable via environment variables (all optional):

| Variable | Default | Purpose |
|----------|---------|---------|
| `RESOLVERS_URL` | trickest trusted list | Public resolver list to fetch |
| `RESOLVERS_FILE` | – | Use a local list verbatim (skips fetching) |
| `RESOLVERS_CACHE_DIR` | – | Persist/reuse a validated list across runs (age-checked) |
| `RESOLVERS_MAX_AGE_HOURS` | `168` | Staleness threshold for cache/fallback |
| `RESOLVERS_VALIDATE` | `true` | Set `false` to skip `dig` validation |
| `RESOLVERS_VALIDATE_LIMIT` | `200` | Max resolvers to validate |
| `RESOLVERS_ANCHOR` | `www.google.com` | Neutral host used to test resolvers |
| `SCOPEFINDER_SKIP_RESOLVER_REFRESH` | – | Set to skip the module entirely |

### Shodan Organization Search

After the Shodan SSL-certificate search, `shodan_search` can run a second query
for a discovered *organization* to widen IP coverage. Interactively it presents
a numbered org menu, but the prompt no longer blocks an unattended run forever:
it has a timeout and a configurable default, and it can be driven entirely by
environment variables so a scheduled/CI run never hangs.

| Variable | Default | Purpose |
|----------|---------|---------|
| `SHODAN_ORG` | – | `<name>`: scan that org directly (no prompt). `auto`: auto-pick the most common org from the cert matches. `skip`/`none`: skip the org scan |
| `SHODAN_ORG_TIMEOUT` | `30` | Seconds to wait at the interactive org prompt before applying the default |
| `SHODAN_ORG_ON_TIMEOUT` | `skip` | Action when the prompt times out, or when running non-interactively with no `SHODAN_ORG`: `skip` or `auto` |

Precedence: an explicit `SHODAN_ORG` wins; otherwise an interactive terminal is
prompted (with the timeout); a non-interactive run applies
`SHODAN_ORG_ON_TIMEOUT` immediately. `auto` selects the *most frequently seen*
org among the certificate matches (the likeliest true owner), not an
alphabetical first.

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
ScopeFinder example.com --fresh

# Application-layer-only scan of a single host
ScopeFinder www.example.com --app

# Dry run (show what would be executed)
ScopeFinder example.com --dry-run

# Run with proxy
ScopeFinder example.com --proxy http://127.0.0.1:8080
```

### Running Individual Tools

```bash
# Access container shell
sf-run bash

# Run specific tools directly
sf-run subfinder -d example.com
sf-run trufflehog filesystem /output/example.com
```

### Application-Layer-Only Mode (`--app`)

For engagements scoped to a single application rather than a whole domain's
infrastructure, `--app` runs only the application-layer modules and skips all
network/DNS discovery and infrastructure enumeration:

```bash
ScopeFinder www.example.com --app
```

In this mode **the supplied host is the target** — there is no subdomain
enumeration, so the app modules are seeded directly from the host you pass.

**Runs (application layer):** web crawling (`katana`), URL/JS extraction
(`xnLinkFinder`, inline scripts, `js_download`, `linkfinder`), parameter
extraction, URL probing (`httpx`), secret scanning, GraphQL and API-docs
discovery, WordPress scanning, the dork generators (Google/GitHub/Docker
Hub/Postman), and the `run_summary` artifact.

**Skipped (network / infrastructure):** `subdomain_enum`, `resolver_refresh`,
`subdomain_takeover`, `httpx_subdomain_probe`, `shodan_search`, `ip_discovery`,
`smap_port_scan`, `cloud_recon`, `asn_discovery`, `asn_port_scan`, `asn_recon`,
and `credential_intel` (OSINT).

Notes:
- The target host is seeded into the live-host list (and as a WordPress-scan URL,
  so WPScan evaluates it — it self-detects and exits cleanly on non-WordPress
  targets). Seeding is append-if-missing, so `--app` layered on top of a prior
  full scan reuses that run's discovered hosts rather than overwriting them.
- `--app` composes with the other flags; combine with `--fresh` to re-run the
  app modules from scratch against the seeded target.

## 📂 Run Output

Each run writes its results under `<domain>/` as per-module text files, plus two
machine-readable artifacts produced by the final `run_summary` module:

- **`<domain>/summary.json`** — a structured snapshot of the discovered surface
  (subdomains, live hosts, open ports, URL/parameter counts, and findings such
  as subdomain takeovers, GraphQL/API-docs endpoints, WordPress sites, secrets,
  and credentials), plus per-module completion status. Consume this from
  external tooling/pipelines instead of parsing individual text files. A
  timestamped copy is kept under `<domain>/summaries/`, and `summary.json`
  always points at the newest run.

  ```bash
  # e.g. list newly discovered live hosts programmatically
  jq -r '.surface.live_subdomains.items[]' example.com/summary.json
  ```

- **`<domain>/diff.json`** — when a previous summary exists, the run flags the
  *new* surface (new subdomains, newly live hosts, newly open ports) relative to
  the previous baseline, along with removed entries and counts. High value for
  the baseline-before-engagement workflow.

  ```bash
  jq '.counts' example.com/diff.json
  ```

Because `run_summary` is checkpointed like any other module, a plain re-run
reuses the existing summary; regenerate it with `--fresh`, `--replay-from`, or
`--replay run_summary`.

### Error Visibility

Modules lean on `|| true` / `2>/dev/null` so one tool failing never aborts the
whole run — but that can also hide a tool that crashed and left empty output
while the module still checkpoints as "completed". To keep failures visible,
every warning and error a module logs is recorded against that module. These
surface in three places:

- a `⚠ Module completed with N warning(s)/error(s)` line at the end of the module,
- an aggregate `⚠ Run completed with N warning(s)...` line at the end of the run,
- `--status`, which marks affected modules `✅ Complete (⚠ N)`,

and the per-module counts plus a `warnings_total` are included in `summary.json`.
Full details for each module are kept in `<domain>/.checkpoints/<module>.warnings`.

## 🗺️ Roadmap

Planned work, roughly in priority order. Contributions toward any of these are welcome.

- **Wider passive breadth** — wire in more passive subdomain sources as API keys become available (Censys, FOFA, Netlas, BinaryEdge, GitHub token, etc.).

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