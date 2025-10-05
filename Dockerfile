# ============================================
# ScopeFinder 2.0 - Enhanced Dockerfile
# ============================================
# Multi-architecture support for amd64 and arm64
# Optimized for size and build speed
# ============================================

# Use slim base for smaller image
FROM debian:bookworm-slim

# Build arguments for multi-architecture support
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETVARIANT

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# ============================================
# LAYER 1: Essential build tools
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    ca-certificates \
    curl \
    wget \
    git \
    make \
    gcc \
    g++ \
    build-essential \
    pkg-config \
    unzip \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# LAYER 2: Language runtimes and utilities
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby \
    ruby-dev \
    python3 \
    python3-pip \
    pipx \
    jq \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# LAYER 3: Chrome/Chromium dependencies
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 \
    libxss1 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libx11-xcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxi6 \
    libxtst6 \
    libasound2 \
    libpangocairo-1.0-0 \
    libpango1.0-0 \
    libcups2 \
    libxkbcommon0 \
    fonts-liberation \
    libgbm-dev \
    libxrandr2 \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# LAYER 4: Development libraries
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2 \
    libxml2-dev \
    libxslt1-dev \
    libgmp-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Install Golang with multi-arch support
# ============================================
ENV GO_VERSION=1.23.5

RUN set -ex && \
    # Detect architecture if not set
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi && \
    case "${TARGETARCH}" in \
        amd64|arm64) \
            GO_TARBALL="go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
            ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}" && exit 1 \
            ;; \
    esac && \
    wget -q "https://go.dev/dl/${GO_TARBALL}" && \
    tar -C /usr/local -xzf "${GO_TARBALL}" && \
    rm "${GO_TARBALL}" && \
    /usr/local/go/bin/go version

# ============================================
# Install Rust
# ============================================
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable

# ============================================
# Install Chromium with multi-arch support
# ============================================
RUN set -ex && \
    # Detect architecture if not set
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi && \
    case "${TARGETARCH}" in \
        amd64) \
            CHROMIUM_VERSION="1131003" && \
            CHROMIUM_URL="https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64/${CHROMIUM_VERSION}/chrome-linux.zip" \
            ;; \
        arm64) \
            CHROMIUM_VERSION="270195" && \
            CHROMIUM_URL="https://storage.googleapis.com/chromium-browser-snapshots/Linux_ARM_Cross-Compile/${CHROMIUM_VERSION}/chrome-linux.zip" \
            ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}" && exit 1 \
            ;; \
    esac && \
    wget -q "${CHROMIUM_URL}" && \
    mkdir -p /root/.cache/rod/browser/chromium-${CHROMIUM_VERSION} && \
    unzip -q chrome-linux.zip && \
    mv chrome-linux/* /root/.cache/rod/browser/chromium-${CHROMIUM_VERSION}/ && \
    rm -rf chrome-linux.zip chrome-linux && \
    echo "Chromium ${CHROMIUM_VERSION} installed for ${TARGETARCH}"

# ============================================
# Install TruffleHog with multi-arch support
# ============================================
ARG TRUFFLEHOG_VERSION=3.90.8
RUN set -ex && \
    # Detect architecture if not set
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi && \
    case "${TARGETARCH}" in \
        amd64|arm64) \
            FILENAME="trufflehog_${TRUFFLEHOG_VERSION}_linux_${TARGETARCH}.tar.gz" \
            ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}" && exit 1 \
            ;; \
    esac && \
    wget -q "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/${FILENAME}" && \
    tar -xzf "${FILENAME}" && \
    mv trufflehog /usr/local/bin/ && \
    chmod +x /usr/local/bin/trufflehog && \
    rm "${FILENAME}" && \
    trufflehog --version

# ============================================
# Install public Go tools (using @latest as requested)
# ============================================
RUN set -ex && \
    export PATH="/usr/local/go/bin:$PATH" && \
    export GOBIN="/root/go/bin" && \
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    go install -v github.com/s0md3v/smap/cmd/smap@latest && \
    go install -v github.com/incogbyte/shosubgo@latest && \
    go install -v github.com/g0ldencybersec/CloudRecon@latest && \
    go install -v github.com/projectdiscovery/asnmap/cmd/asnmap@latest && \
    echo "Public Go tools installed"

# ============================================
# Install katana (requires CGO)
# ============================================
RUN set -ex && \
    export PATH="/usr/local/go/bin:$PATH" && \
    export GOBIN="/root/go/bin" && \
    CGO_ENABLED=1 go install -v github.com/projectdiscovery/katana/cmd/katana@latest && \
    echo "Katana installed"

# ============================================
# Install private Go tools (with GOPRIVATE)
# ============================================
RUN set -ex && \
    export PATH="/usr/local/go/bin:$PATH" && \
    export GOBIN="/root/go/bin" && \
    GOPRIVATE=github.com/0xQRx go install -v github.com/0xQRx/crtsh-tool/cmd/crtsh-tool@main && \
    GOPRIVATE=github.com/0xQRx go install -v github.com/0xQRx/jshunter@main && \
    GOPRIVATE=github.com/0xQRx go install -v github.com/0xQRx/godigger@main && \
    GOPRIVATE=github.com/0xQRx go install -v github.com/0xQRx/URLDedup/cmd/urldedup@main && \
    echo "Private Go tools installed"

# ============================================
# Install Python tools
# ============================================
RUN set -ex && \
    export PATH="/root/.local/bin:$PATH" && \
    pipx install git+https://github.com/xnl-h4ck3r/waymore.git && \
    pipx install git+https://github.com/0xQRx/LinkFinder.git --include-deps && \
    pipx install git+https://github.com/xnl-h4ck3r/xnLinkFinder.git && \
    pipx install git+https://github.com/0xQRx/msftrecon.git && \
    pipx install uro && \
    echo "Python tools installed"

# ============================================
# Install Ruby tools
# ============================================
RUN gem install wpscan && \
    wpscan --version && \
    echo "Ruby tools installed"

# ============================================
# Install Rust tools
# ============================================
RUN set -ex && \
    export PATH="/root/.cargo/bin:$PATH" && \
    cargo install x8 && \
    echo "Rust tools installed"

# ============================================
# Download wordlists
# ============================================
RUN mkdir -p /wordlists && \
    cd /wordlists && \
    wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/refs/heads/master/Discovery/Web-Content/burp-parameter-names.txt && \
    echo "Wordlists downloaded"

# ============================================
# Set up final environment variables and PATH
# ============================================
ENV PATH="/usr/local/go/bin:/root/go/bin:/root/.cargo/bin:/root/.local/bin:$PATH" \
    GOBIN="/root/go/bin" \
    GO111MODULE=on \
    GOPROXY=https://proxy.golang.org,direct \
    GOPRIVATE=github.com/0xQRx

# ============================================
# Verify all tools are installed
# ============================================
RUN set -ex && \
    echo "=== Verifying tool installation ===" && \
    subfinder -version 2>/dev/null | head -1 && \
    httpx -version 2>/dev/null | head -1 && \
    katana -version 2>/dev/null | head -1 && \
    asnmap -version 2>/dev/null | head -1 && \
    smap -h 2>&1 | head -1 && \
    which crtsh-tool && \
    which jshunter && \
    which godigger && \
    which urldedup && \
    which waymore && \
    which linkfinder && \
    which xnLinkFinder && \
    which msftrecon && \
    which uro && \
    which shosubgo && \
    which CloudRecon && \
    wpscan --version | head -1 && \
    x8 --version && \
    trufflehog --version && \
    echo "=== All tools verified successfully ==="

# ============================================
# Create output directory
# ============================================
RUN mkdir -p /output

# ============================================
# Set working directory
# ============================================
WORKDIR /output

# ============================================
# Set environment for ScopeFinder
# ============================================
ENV SCRIPT_DIR=/opt \
    DISABLE_UPDATE_CHECK=true \
    GOGC=50

# ============================================
# Metadata labels
# ============================================
LABEL maintainer="ScopeFinder" \
      version="2.0" \
      description="ScopeFinder 2.0 - Modular reconnaissance framework" \
      architecture="${TARGETARCH}"

# ============================================
# Health check
# ============================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD subfinder -version && httpx -version && echo "Health check passed" || exit 1

# ============================================
# Entry point - default to bash, will be overridden when mounting scripts
# ============================================
ENTRYPOINT ["/bin/bash"]