#!/bin/bash
# start-universal.sh
# UNIVERSAL STARTUP SCRIPT - Works for everyone!
#
# Usage Scenarios:
#   1. Developer with full repo: Just run this script
#   2. User with pulled image: Run this script (auto-downloads Host API)
#
# This script:
#   - Auto-downloads Host API scripts if missing
#   - Starts Host API with full verbose output
#   - Starts Dashboard container
#   - Verifies everything is running

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Get project root
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
HOST_DIR="$PROJECT_ROOT/Host"
TEMP_CLONE_DIR="/tmp/system-monitor-host-api"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 System Monitor - Universal Startup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================
# HELPER: Check and Install Dependencies
# ============================================
check_dependency() {
    local cmd=$1
    local package=$2
    local install_cmd=$3

    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}►${NC} $cmd is missing. Attempting auto-installation..."
        if [ -n "$install_cmd" ]; then
            eval "$install_cmd"
        else
            if command -v apt-get &> /dev/null; then
                 echo -e "${YELLOW}►${NC} Running: sudo apt-get install -y $package"
                 sudo apt-get update >/dev/null 2>&1
                 sudo apt-get install -y "$package"
            else
                 echo -e "${RED}✗${NC} Cannot auto-install $package. Please install manually."
                 exit 1
            fi
        fi
        
        # Verify again
        if ! command -v "$cmd" &> /dev/null; then
             echo -e "${RED}✗${NC} Failed to install $cmd."
             echo "Please install manually: sudo apt-get install -y $package"
             exit 1
        fi
        echo -e "${GREEN}✓${NC} $cmd installed successfully."
    else
        echo -e "${GREEN}✓${NC} $cmd found"
    fi
}

# Check Core Dependencies
echo -e "${BLUE}[0/4]${NC} Checking System Dependencies..."
check_dependency "git" "git"
check_dependency "curl" "curl"
check_dependency "python3" "python3"

# Check Monitoring Dependencies (Required for Legacy Agent)
echo -e "${BLUE}[0.2/4]${NC} Checking Monitoring Tools..."
check_dependency "sensors" "lm-sensors"
check_dependency "mpstat" "sysstat"
check_dependency "lspci" "pciutils"
check_dependency "smartctl" "smartmontools"

# Check pip (special case for python3-pip)
if ! python3 -m pip --version > /dev/null 2>&1; then
     echo -e "${YELLOW}►${NC} pip is missing. Installing python3-pip..."
     if command -v apt-get &> /dev/null; then
         sudo apt-get update >/dev/null 2>&1
         sudo apt-get install -y python3-pip
     else
         echo -e "${RED}✗${NC} Please install pip manually: sudo apt-get install -y python3-pip"
         exit 1
     fi
fi
echo -e "${GREEN}✓${NC} pip modules found"

# Check Docker (Critical)
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗${NC} Docker is missing!"
    echo "This requires Docker Desktop (Windows/Mac) or Docker Engine (Linux)."
    echo "Automatic installation of Docker is risky. Please install Docker Desktop manually."
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker found"



# ============================================
# STEP -1: Check/Generate Docker Config
# ============================================
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${YELLOW}►${NC} docker-compose.yml not found. Generating default config..."
    
    # ---------------------------------------------------------
    # CONFIGURATION: Replace 'yourusername' below before distributing
    # ---------------------------------------------------------
    DOCKER_IMAGE="sharawey74/system-monitor:latest" 
    
    cat > docker-compose.yml <<EOF
version: '3.8'

services:
  dashboard:
    image: ${DOCKER_IMAGE}
    container_name: system-monitor-dashboard
    
    # Enable connection to Host API running on native OS
    extra_hosts:
      - "host.docker.internal:host-gateway"
      
    ports:
      - "5000:5000"

    # Minimal volumes for persistence
    volumes:
      - ./data:/app/data
      - ./reports:/app/reports
      
    environment:
      - HOST_API_URL=http://host.docker.internal:8888
      - NATIVE_AGENT_URL=http://host.docker.internal:8889
      - HOST_MONITORING=true
      
    restart: unless-stopped
EOF
    echo -e "${GREEN}✓${NC} Generated docker-compose.yml (Image: $DOCKER_IMAGE)"
fi

# ============================================
# STEP 0: Check/Download Host API Scripts
# ============================================
echo -e "${BLUE}[0.5/4]${NC} Checking Host API scripts..."
if [ ! -d "$HOST_DIR" ] || [ ! -f "$HOST_DIR/api/server.py" ]; then
    echo -e "${YELLOW}⚠${NC}  Host API scripts not found locally"
    echo -e "${YELLOW}►${NC}  Downloading Host API scripts from GitHub..."
    rm -rf "$TEMP_CLONE_DIR"
    git clone --depth 1 --filter=blob:none --sparse https://github.com/Sharawey74/system-monitor-project.git "$TEMP_CLONE_DIR" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        cd "$TEMP_CLONE_DIR"
        git sparse-checkout set Host
        if [ -d "$TEMP_CLONE_DIR/Host" ]; then
            cp -r "$TEMP_CLONE_DIR/Host" "$PROJECT_ROOT/"
            echo -e "${GREEN}✓${NC}  Host API scripts downloaded successfully"
        fi
        rm -rf "$TEMP_CLONE_DIR"
    else 
        echo -e "${RED}✗${NC} Global download failed. Check internet."
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC}  Host API scripts found"
fi

# ============================================
# STEP 1: Start Host API
# ============================================
echo ""
echo -e "${BLUE}[1/3]${NC} Starting Host API..."
echo ""
echo "=================================================="
echo "  Starting Host API (Native OS)"
echo "=================================================="

# Check if Host API is already running
if curl -s http://localhost:8888/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Host API already running on port 8888"
else
    # Check Python dependencies
    echo -e "${YELLOW}►${NC} Checking Python dependencies..."
    if ! python3 -c "import fastapi, uvicorn" 2>/dev/null; then
        echo -e "${YELLOW}►${NC} Installing Python dependencies (fastapi, uvicorn)..."
        python3 -m pip install --break-system-packages fastapi uvicorn 2>/dev/null || \
        python3 -m pip install --user fastapi uvicorn || {
            echo -e "${RED}✗${NC} Failed to install dependencies."
            echo "It seems 'pip' is missing or failed."
            echo "Try installing pip manually first:"
            echo "  sudo apt update && sudo apt install -y python3-pip"
            echo "Then run this script again."
            exit 1
        }
    fi
    
    # Generate initial metrics with FULL OUTPUT
    echo -e "${YELLOW}►${NC} Generating initial metrics..."
    cd "$HOST_DIR/scripts"
    bash main_monitor.sh
    
    echo ""
    echo -e "${YELLOW}►${NC} Starting Host API Server..."
    cd "$HOST_DIR/api"
    nohup python3 server.py > /tmp/host-api.log 2>&1 &
    HOST_API_PID=$!
    echo $HOST_API_PID > /tmp/host-api.pid
    
    echo -e "${GREEN}✓${NC} Host API Server started (PID: $HOST_API_PID)"
    echo -e "   ${CYAN}Logs: tail -f /tmp/host-api.log${NC}"
    
    # Wait for Host API to be ready
    echo -e "${YELLOW}►${NC} Waiting for API to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8888/health > /dev/null 2>&1; then
            echo -e ".${GREEN}✓${NC} Host API is ready!"
            break
        fi
        sleep 1
        echo -n "."
    done
    echo ""
    
    # Final health check
    if ! curl -s http://localhost:8888/health > /dev/null 2>&1; then
        echo -e "${RED}✗${NC} Host API failed to start"
        echo ""
        echo "Check logs: tail -f /tmp/host-api.log"
        exit 1
    fi
fi

# Check and start Monitor Loop (INDEPENDENT of API)
echo ""
echo -e "${YELLOW}►${NC} Checking Host Monitor Loop..."
MONITOR_PID_FILE="/tmp/host-monitor-loop.pid"
MONITOR_RUNNING=false

if [ -f "$MONITOR_PID_FILE" ]; then
    MONITOR_PID=$(cat "$MONITOR_PID_FILE")
    if ps -p "$MONITOR_PID" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Monitor Loop already running (PID: $MONITOR_PID)"
        MONITOR_RUNNING=true
    else
        echo -e "${YELLOW}►${NC} Stale PID file found, removing..."
        rm -f "$MONITOR_PID_FILE"
    fi
fi

if [ "$MONITOR_RUNNING" = false ]; then
    echo -e "${YELLOW}►${NC} Starting Host Monitoring Loop (collects data every 60s)..."
    cd "$HOST_DIR/loop"
    nohup bash host_monitor_loop.sh > /tmp/host-monitor-loop.log 2>&1 &
    MONITOR_PID=$!
    echo $MONITOR_PID > "$MONITOR_PID_FILE"
    echo -e "${GREEN}✓${NC} Host Monitor Loop started (PID: $MONITOR_PID)"
    echo -e "   ${CYAN}Logs: tail -f /tmp/host-monitor-loop.log${NC}"
fi

# ============================================
# STEP 1.5: Start Native Go Agent (NEW)
# ============================================
echo ""
echo -e "${BLUE}[1.5/4]${NC} Starting Native Go Agent..."
echo ""

HOST2_DIR="$PROJECT_ROOT/Host2"
NATIVE_AGENT_PID_FILE="/tmp/native-agent.pid"

# Detect OS and select binary
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
    # Windows or WSL2
    NATIVE_BINARY="$HOST2_DIR/bin/host-agent-windows.exe"
    PLATFORM="Windows"
    # On WSL, we need to launch Windows binary using cmd.exe
    if grep -qi microsoft /proc/version 2>/dev/null; then
        LAUNCH_CMD="cmd.exe /c start"
    else
        LAUNCH_CMD=""
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    NATIVE_BINARY="$HOST2_DIR/bin/host-agent-macos"
    PLATFORM="macOS"
    LAUNCH_CMD=""
else
    # Linux
    NATIVE_BINARY="$HOST2_DIR/bin/host-agent-linux"
    PLATFORM="Linux"
    LAUNCH_CMD=""
fi

echo -e "${YELLOW}►${NC} Detected platform: $PLATFORM"

# Check if native agent binary exists
if [ -f "$NATIVE_BINARY" ]; then
    # Check if already running
    if [ -f "$NATIVE_AGENT_PID_FILE" ]; then
        NATIVE_PID=$(cat "$NATIVE_AGENT_PID_FILE")
        if ps -p "$NATIVE_PID" > /dev/null 2>&1 || curl -s http://localhost:8889/health > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Native Agent already running (PID: $NATIVE_PID)"
        else
            rm -f "$NATIVE_AGENT_PID_FILE"
        fi
    fi
    
    # Start if not running
    if ! curl -s http://localhost:8889/health > /dev/null 2>&1; then
        echo -e "${YELLOW}►${NC} Starting Native Agent ($PLATFORM)..."
        
        if [ -n "$LAUNCH_CMD" ]; then
            # WSL2: Launch Windows binary (Background it properly)
            # We redirect to /dev/null because 'start' opens a new window anyway
            nohup $LAUNCH_CMD "$(wslpath -w "$NATIVE_BINARY")" > /dev/null 2>&1 &
            sleep 3
        else
            # Direct launch
            chmod +x "$NATIVE_BINARY" 2>/dev/null || true
            nohup "$NATIVE_BINARY" > /tmp/native-agent.log 2>&1 &
            NATIVE_PID=$!
            echo $NATIVE_PID > "$NATIVE_AGENT_PID_FILE"
        fi
        
        # Wait for agent to be ready
        echo -e "${YELLOW}►${NC} Waiting for Native Agent..."
        for i in {1..15}; do
            # Try Linux curl first
            if curl -s http://localhost:8889/health > /dev/null 2>&1; then
                echo -e ".${GREEN}✓${NC} Native Agent is ready (localhost)!"
                break
            fi
            
            # If on WSL, try Windows curl.exe (as it shares network stack with the agent)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                 if curl.exe -s http://localhost:8889/health > /dev/null 2>&1; then
                    echo -e ".${GREEN}✓${NC} Native Agent is ready (Windows Network)!"
                    break
                 fi
            fi
            
            sleep 1
            echo -n "."
        done
        echo ""
        
        echo ""
        
        # Verify result
        IS_RUNNING=false
        if curl -s http://localhost:8889/health > /dev/null 2>&1; then
            IS_RUNNING=true
        elif grep -qi microsoft /proc/version 2>/dev/null && curl.exe -s http://localhost:8889/health > /dev/null 2>&1; then
             IS_RUNNING=true
        fi

        if [ "$IS_RUNNING" = true ]; then
            echo -e "${GREEN}✓${NC} Native Agent started successfully"
            echo -e "   ${CYAN}Logs: tail -f /tmp/native-agent.log${NC}"
            echo -e "   ${CYAN}Endpoint: http://localhost:8889/metrics${NC}"
        else
            echo -e "${YELLOW}⚠${NC}  Native Agent failed to start (falling back to legacy)"
            echo -e "   ${CYAN}Check logs: tail -f /tmp/native-agent.log${NC}"
        fi
    fi
else
    # Auto-Build Section
    echo -e "${YELLOW}⚠${NC}  Native Agent binary not found: $NATIVE_BINARY"
    
    if command -v go &> /dev/null; then
        echo -e "${YELLOW}►${NC}  Go compiler found. Attempting auto-build..."
        cd "$HOST2_DIR"
        
        # Auto download deps if needed
        if [ ! -f "go.sum" ]; then
             echo -e "${YELLOW}►${NC}  Downloading Go dependencies..."
             go mod tidy > /dev/null 2>&1
        fi
        
        # Build
        echo -e "${YELLOW}►${NC}  Building for $PLATFORM (output: bin/$(basename "$NATIVE_BINARY"))..."
        
        if [[ "$PLATFORM" == "Windows" ]]; then
            GOOS=windows GOARCH=amd64 go build -o "bin/host-agent-windows.exe" main.go
        elif [[ "$PLATFORM" == "macOS" ]]; then
            GOOS=darwin GOARCH=amd64 go build -o "bin/host-agent-macos" main.go
        else
            GOOS=linux GOARCH=amd64 go build -o "bin/host-agent-linux" main.go
        fi
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC}  Build successful!"
            cd "$PROJECT_ROOT"
            # Rerun this step (recursion via exec would be complex, so just continue to start logic)
            # Re-check binary - it should exist now
             echo -e "${GREEN}►${NC}  Starting newly built agent..."
             # ... (replicate start logic or rely on user restarting script? NO, RUN IT NOW)
             
             if [ -n "$LAUNCH_CMD" ]; then
                nohup $LAUNCH_CMD "$(wslpath -w "$NATIVE_BINARY")" > /dev/null 2>&1 &
                sleep 3
             else
                chmod +x "$NATIVE_BINARY" 2>/dev/null || true
                nohup "$NATIVE_BINARY" > /tmp/native-agent.log 2>&1 &
             fi
             echo -e "${GREEN}✓${NC}  Native Agent started"
        else
            echo -e "${RED}✗${NC}  Build failed. Please build manually in Host2 directory."
        fi
        cd "$PROJECT_ROOT"
    else
        echo -e "${RED}✗${NC}  Go compiler not found. Cannot auto-build."
        echo -e "${YELLOW}►${NC}  Please install Go or download the binary manually."
        echo -e "${YELLOW}►${NC}  Continuing with legacy system only..."
    fi
fi


# ============================================
# STEP 2: Start Dashboard
# ============================================
echo ""
echo -e "${BLUE}[2/4]${NC} Starting Dashboard..."
echo ""

cd "$PROJECT_ROOT"

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${YELLOW}⚠${NC}  docker-compose.yml not found"
    echo -e "${YELLOW}►${NC}  Using docker run instead..."
    echo ""
    
    # Stop old container if exists
    docker stop system-monitor-dashboard 2>/dev/null || true
    docker rm system-monitor-dashboard 2>/dev/null || true
    
    # Create necessary directories
    mkdir -p data reports json
    
    # Check if image exists locally
    if ! docker image inspect sharawey74/system-monitor:latest > /dev/null 2>&1 && \
       ! docker image inspect system-monitor:latest > /dev/null 2>&1; then
        echo -e "${YELLOW}►${NC}  Docker image not found locally"
        echo -e "${YELLOW}►${NC}  Pulling image from Docker Hub..."
        docker pull sharawey74/system-monitor:latest || {
            echo -e "${RED}✗${NC}  Failed to pull image from Docker Hub"
            echo ""
            echo "Please pull the image manually:"
            echo "  docker pull sharawey74/system-monitor:latest"
            exit 1
        }
        IMAGE_NAME="sharawey74/system-monitor:latest"
    else
        # Use whatever image is available
        if docker image inspect sharawey74/system-monitor:latest > /dev/null 2>&1; then
            IMAGE_NAME="sharawey74/system-monitor:latest"
        else
            IMAGE_NAME="system-monitor:latest"
        fi
    fi
    
    echo -e "${YELLOW}►${NC}  Starting container..."
    
    # Run container manually
    docker run -d \
      --name system-monitor-dashboard \
      --pid host \
      --privileged \
      -p 5000:5000 \
      -v "$(pwd)/data:/app/data" \
      -v "$(pwd)/reports:/app/reports" \
      -v "$(pwd)/json:/app/json" \
      -v "$(pwd)/Host/output:/app/Host/output:ro" \
      -v "$(pwd)/Host2:/app/Host2:ro" \
      -e HOST_API_URL=http://host.docker.internal:8888 \
      -e NATIVE_AGENT_URL=http://host.docker.internal:8889 \
      -e JSON_LOGGING_ENABLED=true \
      -e JSON_LOG_INTERVAL=10 \
      --add-host=host.docker.internal:host-gateway \
      "$IMAGE_NAME"
    
    echo -e "${GREEN}✓${NC} Dashboard container started"
else
    # Use docker-compose or docker compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD="docker compose"
    fi

    echo -e "${YELLOW}►${NC} Stopping old containers..."
    $COMPOSE_CMD down 2>/dev/null || true
    
    echo -e "${YELLOW}►${NC} Building and starting Dashboard container..."
    if $COMPOSE_CMD up --build -d 2>&1 | grep -v "WARN.*version.*obsolete"; then
        echo -e "${GREEN}✓${NC} Dashboard container started"
    else
        echo -e "${RED}✗${NC} Dashboard failed to start"
        echo ""
        echo "Check logs: $COMPOSE_CMD logs"
        exit 1
    fi
fi

# ============================================
# STEP 3: Verify System
# ============================================
echo ""
echo -e "${BLUE}[3/4]${NC} Verifying system..."
echo ""

# Wait for dashboard to be ready
echo -e "${YELLOW}►${NC} Waiting for Dashboard..."
for i in {1..20}; do
    if curl -s http://localhost:5000/api/health > /dev/null 2>&1; then
        echo -e ".${GREEN}✓${NC} Dashboard is ready!"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Final verification
HOST_STATUS=$(curl -s http://localhost:8888/health 2>/dev/null || echo "failed")
DASH_STATUS=$(curl -s http://localhost:5000/api/health 2>/dev/null || echo "failed")

# Check Native Agent (Robust Check)
# Check Native Agent (Robust Check)
# Retry for up to 5 seconds to allow late binding
NATIVE_STATUS="failed"
for i in {1..5}; do
    if curl -s http://localhost:8889/health > /dev/null 2>&1; then
        NATIVE_STATUS="running"
        break
    elif grep -qi microsoft /proc/version 2>/dev/null && curl.exe -s http://localhost:8889/health > /dev/null 2>&1; then
        NATIVE_STATUS="running"
        break
    fi
    sleep 1
done

echo ""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ SYSTEM MONITOR IS RUNNING!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "  ${GREEN}●${NC} Web Dashboard:     ${CYAN}http://localhost:5000${NC}"
echo -e "  ${GREEN}●${NC} Legacy API:        ${CYAN}http://localhost:8888${NC}"
echo -e "  ${GREEN}●${NC} Native Agent:      ${CYAN}http://localhost:8889${NC}"
echo -e "  ${GREEN}●${NC} API Metrics:       ${CYAN}http://localhost:5000/api/metrics${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Status:"
echo -e "  Monitor Loop: $(if [[ -f /tmp/host-monitor-loop.pid ]] && ps -p $(cat /tmp/host-monitor-loop.pid 2>/dev/null) > /dev/null 2>&1; then echo -e "${GREEN}✓ Collecting data every 60s${NC}"; else echo -e "${YELLOW}⚠ Check /tmp/host-monitor-loop.log${NC}"; fi)"
echo -e "  Legacy API:   $(if [[ "$HOST_STATUS" != "failed" ]]; then echo -e "${GREEN}✓ Running${NC}"; else echo -e "${RED}✗ Failed${NC}"; fi)"
echo -e "  Native Agent: $(if [[ "$NATIVE_STATUS" != "failed" ]]; then echo -e "${GREEN}✓ Running (Real Metrics)${NC}"; else echo -e "${YELLOW}⚠ Not Available${NC}"; fi)"
echo -e "  Dashboard:    $(if [[ "$DASH_STATUS" != "failed" ]]; then echo -e "${GREEN}✓ Running${NC}"; else echo -e "${RED}✗ Failed${NC}"; fi)"
echo ""
echo "Terminal Dashboard:"
echo -e "  ${CYAN}docker exec -it system-monitor-dashboard python3 dashboard_tui.py${NC}"
echo ""
echo "Logs:"
echo -e "  Monitor Loop: ${CYAN}tail -f /tmp/host-monitor-loop.log${NC}"
echo -e "  Legacy API:   ${CYAN}tail -f /tmp/host-api.log${NC}"
echo -e "  Native Agent: ${CYAN}tail -f /tmp/native-agent.log${NC}"
echo -e "  Dashboard:    ${CYAN}docker logs -f system-monitor-dashboard${NC}"
echo ""
echo "Data File:"
echo -e "  ${CYAN}watch -n 5 stat Host/output/latest.json${NC}  ${YELLOW}# Watch file being updated${NC}"
echo ""
echo "To stop:"
echo -e "  ${CYAN}bash stop-system-monitor.sh${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
