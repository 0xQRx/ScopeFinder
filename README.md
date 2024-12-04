# ScopeFinder

**ScopeFinder** is a comprehensive tool for automated domain enumeration and analysis. It installs necessary tools, performs passive and active scans, and organizes results into structured output files.

## Features

- **Automated Installation**: Installs all required tools if not already present:
  - `subfinder`, `waymore`, `httpx`, `smap`, `crtsh-tool`, `shosubgo`.
- **Passive Analysis**: Subdomain enumeration, URL, emails and leaked credential discovery .
- **Active Analysis**: HTTP probing, banner grabbing, technology detection, and screenshots.
- **Output Management**: Organized and deduplicated results stored in domain-specific directories.

## Requirements

1. **Golang**: Install from [https://go.dev/](https://go.dev/).
2. **Pipx**: Install from [pipx documentation](https://pypa.github.io/pipx/).
3. **API Keys**: Set the required API keys in the corresponding configuration files:
   - Shodan, Dehashed, Hunter.io API keys must be set in `~/.zshrc` or `~/.bashrc`.
   - Other tools (e.g., `waymore`, `subfinder`) need API keys configured in their specific files for full functionality.

# IMPORTANT
4. **First Run Notice**: kali comes with `httpx` however, that version is not what this script use, you would need to remove standard utility before you can use this script. `httpx` will download the Chromium browser on its first run. A machine reboot may be required to ensure it functions correctly.

## Usage

1. Clone or download ScopeFinder.
2. Set your API Keys in `~/.zshrc` or `~/.bashrc`:
   ```bash
   export SHODAN_API_KEY=your_api_key
   export DEHASHED_EMAIL=your_email
   export DEHASHED_API_KEY=your_api_key
   export HUNTERIO_API_KEY=your_api_key
   ```
3. Ensure other tools' API keys are configured.
4. Run the script with:
   ```bash
   sudo ./ScopeFinder.sh domain
   ```
5. Check output in the generated directory named after the target domain.

## Output

- **Subdomains**: Discovered subdomains in `subdomains.txt`.
- **Wildcard Subdomains**: Wildcard subdomains in `wildcard_subdomains.txt`.
- **URLs**: Discovered URLs from `waymore`.
- **HTTP Analysis**: HTTP probing results and screenshots.

# TODO:
- add crosslinked support (pass company name as a second argument)
- add subdomain/vhost bruteforcing
- add ASN to find IP ranges (outside of domain search - separate folder(?))
- add IP search support via VirusTotal, AlienVault, etc. (outside of domain search - separate folder(?))
- add certificate brute on identified IPs using CloudRecon. (outside of domain search - separate folder(?))
- add smap support to get ports open on the targets. (outside of domain search - separate folder(?))
