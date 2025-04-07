# Use the official Debian base image
FROM debian:bookworm

# Set environment variables to avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and install necessary packages
RUN apt update && apt install -y \
    jq wget curl unzip gcc ruby git make xdg-utils pkg-config libssl-dev \
    libnss3 libxss1 libatk1.0-0 libatk-bridge2.0-0 libdrm2 libx11-xcb1 \
    libxcomposite1 libxcursor1 libxdamage1 libxi6 libxtst6 libasound2 \
    libpangocairo-1.0-0 libcups2 libxkbcommon0 fonts-liberation libgbm-dev build-essential libcurl4-openssl-dev libxml2 libxml2-dev libxslt1-dev ruby-dev  libgmp-dev zlib1g-dev \
    libpango1.0-0 libjpeg-dev libxrandr2 pipx dnsutils ca-certificates && \
    apt clean && rm -rf /var/lib/apt/lists/*

# Install Golang (required for the tools)
ENV GO_VERSION=1.23.5

# Detect architecture and install the correct Go version
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then ARCH="arm64"; \
    else echo "Unsupported architecture: $ARCH"; exit 1; fi && \
    \
    # Construct the Go download URL dynamically
    GO_TARBALL="go${GO_VERSION}.linux-${ARCH}.tar.gz" && \
    GO_URL="https://go.dev/dl/${GO_TARBALL}" && \
    \
    # Download and install Go
    wget "$GO_URL" && \
    tar -C /usr/local -xzf "$GO_TARBALL" && \
    rm "$GO_TARBALL"

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

# Install headless chromium
RUN wget https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64/1131003/chrome-linux.zip && \
    mkdir -p /root/.cache/rod/browser/chromium-1131003 && \
    unzip chrome-linux.zip && \
    rm chrome-linux.zip && \
    mv chrome-linux/* /root/.cache/rod/browser/chromium-1131003/ && \
    rm -rf chrome-linux

# Set Golang environment variables
ENV PATH="/root/.cargo/bin:/usr/local/go/bin:/root/.local/bin:$PATH"
ENV GOBIN="/root/go/bin"
ENV PATH="$PATH:$GOBIN"

# Download and install TruffleHog prebuilt binary
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then ARCH="arm64"; \
    else echo "Unsupported architecture: $ARCH"; exit 1; fi && \
    \
    VERSION="3.88.20" && \
    FILENAME="trufflehog_${VERSION}_linux_${ARCH}.tar.gz" && \
    URL="https://github.com/trufflesecurity/trufflehog/releases/download/v${VERSION}/${FILENAME}" && \
    \
    wget "$URL" && \
    tar -xzf "$FILENAME" && \
    mv trufflehog /usr/local/bin/trufflehog && \
    chmod +x /usr/local/bin/trufflehog && \
    rm "$FILENAME"

# Install the required tools using Go, cargo and pipx 
RUN go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    go install -v github.com/s0md3v/smap/cmd/smap@latest && \
    go install github.com/incogbyte/shosubgo@latest && \
    CGO_ENABLED=1 go install github.com/projectdiscovery/katana/cmd/katana@latest && \
    go install github.com/g0ldencybersec/CloudRecon@latest && \
    go install github.com/projectdiscovery/asnmap/cmd/asnmap@latest && \
    pipx install git+https://github.com/xnl-h4ck3r/waymore.git && \
    pipx install git+https://github.com/0xQRx/LinkFinder.git --include-deps && \
    pipx install git+https://github.com/xnl-h4ck3r/xnLinkFinder.git && \ 
    pipx install git+https://github.com/0xQRx/msftrecon.git && \ 
    GOPRIVATE=github.com/0xQRx/crtsh-tool go install github.com/0xQRx/crtsh-tool/cmd/crtsh-tool@main && \
    GOPRIVATE=github.com/0xQRx/jshunter go install -v github.com/0xQRx/jshunter@main && \
    GOPRIVATE=github.com/0xQRx/godigger go install -v github.com/0xQRx/godigger@main && \
    GOPRIVATE=github.com/0xQRx/URLDedup go install -v github.com/0xQRx/URLDedup/cmd/urldedup@main && \
    gem install wpscan && \
    pipx install uro && \
    cargo install x8

# Download wordlists
RUN mkdir -p /wordlists && cd /wordlists && wget https://raw.githubusercontent.com/danielmiessler/SecLists/refs/heads/master/Discovery/Web-Content/burp-parameter-names.txt

# Create a directory for output
RUN mkdir /output

# Set working directory to /output
WORKDIR /output

# Entry point for the container
ENTRYPOINT ["/opt/ScopeFinder.sh"]
