# Use the official Debian base image
FROM debian:bookworm

# Set environment variables to avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and install necessary packages
RUN apt update && apt install -y \
    jq wget curl unzip gcc git make xdg-utils \
    libnss3 libxss1 libatk1.0-0 libatk-bridge2.0-0 libdrm2 libx11-xcb1 \
    libxcomposite1 libxcursor1 libxdamage1 libxi6 libxtst6 libasound2 \
    libpangocairo-1.0-0 libcups2 libxkbcommon0 fonts-liberation libgbm-dev \
    libpango1.0-0 libjpeg-dev libxrandr2 pipx dnsutils ca-certificates && \
    apt clean && rm -rf /var/lib/apt/lists/*

# Install Golang (required for the tools)
RUN wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz && \
    rm go1.23.4.linux-amd64.tar.gz

# Install headless chromium
RUN wget https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64/1131003/chrome-linux.zip && \
    mkdir -p /root/.cache/rod/browser/chromium-1131003 && \
    unzip chrome-linux.zip && \
    rm chrome-linux.zip && \
    mv chrome-linux/* /root/.cache/rod/browser/chromium-1131003/ && \
    rm -rf chrome-linux

# Set Golang environment variables
ENV PATH="/usr/local/go/bin:/root/.local/bin:$PATH"
ENV GOBIN="$HOME/go/bin"
ENV PATH="$PATH:$GOBIN"

# Install the required tools using Go and pipx
RUN go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    go install -v github.com/s0md3v/smap/cmd/smap@latest && \
    GOPRIVATE=github.com/0xQRx/crtsh-tool go install github.com/0xQRx/crtsh-tool/cmd/crtsh-tool@latest && \
    go install github.com/incogbyte/shosubgo@latest && \
    go install github.com/0xQRx/subbrute/cmd/subbrute@latest && \
    go install github.com/g0ldencybersec/CloudRecon@latest && \
    go install github.com/projectdiscovery/asnmap/cmd/asnmap@latest && \
    pipx install git+https://github.com/xnl-h4ck3r/waymore.git && \
    CGO_ENABLED=1 go install github.com/projectdiscovery/katana/cmd/katana@latest && \
    pipx ensurepath > /dev/null

# Copy the script into the container
COPY ScopeFinder.sh /opt/ScopeFinder.sh

# Make the script executable
RUN chmod +x /opt/ScopeFinder.sh

# Create a directory for output
RUN mkdir /output

# Set working directory to /output
WORKDIR /output

# Entry point for the container
ENTRYPOINT ["/opt/ScopeFinder.sh"]
