# System Monitor - Dashboard Container
# Two-Tier Architecture: This runs the dashboard only
# Host API must run natively on your machine for real hardware access

FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies + GPU monitoring tools
RUN echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "📦 Installing System Dependencies..." && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    apt-get update && apt-get install -y \
    bash \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    python3-dev \
    lm-sensors \
    mesa-utils \
    pciutils \
    && rm -rf /var/lib/apt/lists/* && \
    echo "✓ System dependencies installed"

# Install optional AMD GPU tools
RUN echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "🔥 Installing AMD GPU Tools (radeontop)..." && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    apt-get update && apt-get install -y radeontop && echo "✓ radeontop installed" || echo "⚠ radeontop not available" && \
    rm -rf /var/lib/apt/lists/*

# Install optional Intel GPU tools
RUN echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "💎 Installing Intel GPU Tools..." && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    apt-get update && apt-get install -y intel-gpu-tools && echo "✓ intel-gpu-tools installed" || echo "⚠ intel-gpu-tools not available" && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Python requirements
COPY requirements.txt .

# Install Python dependencies
RUN echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "🐍 Installing Python Dependencies..." && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    pip3 install --no-cache-dir -r requirements.txt && \
    pip3 install --no-cache-dir requests && \
    echo "✓ Python packages installed"

# Copy application files
COPY web/ ./web/
COPY static/ ./static/
COPY templates/ ./templates/
COPY core/ ./core/
COPY display/ ./display/
COPY scripts/ ./scripts/
COPY dashboard_tui.py .

# Create data directories
RUN mkdir -p \
    /app/data/metrics \
    /app/data/logs \
    /app/data/alerts \
    /app/reports

# Make scripts executable
RUN echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "🔧 Setting Up Scripts and Permissions..." && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    find /app/scripts -type f -name "*.sh" -exec chmod +x {} \; && \
    echo "✓ Scripts configured"

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    FLASK_ENV=production \
    HOST_API_URL=http://host.docker.internal:8888

# Expose dashboard port
EXPOSE 5000

# Copy startup script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:5000/api/health || exit 1

# Use entrypoint script for startup messages
ENTRYPOINT ["/docker-entrypoint.sh"]
