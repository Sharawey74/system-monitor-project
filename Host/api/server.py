#!/usr/bin/env python3
"""
Host Metrics API Server
FastAPI TCP server serving metrics from Host/output/latest.json
Port: 9999
"""

import json
import time
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

# Configuration
API_PORT = 8888
API_HOST = "0.0.0.0"
METRICS_FILE = Path(__file__).parent.parent / "output" / "latest.json"
MONITOR_SCRIPT = Path(__file__).parent.parent / "scripts" / "main_monitor.sh"

# Initialize FastAPI app
app = FastAPI(
    title="Host System Monitor API",
    description="TCP API serving system metrics from host monitoring",
    version="1.0.0"
)


@app.get("/health")
async def health_check() -> Dict[str, str]:
    """
    Health check endpoint
    
    Returns:
        dict: Health status
    """
    return {
        "status": "ok",
        "service": "host-monitor-api",
        "port": str(API_PORT),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    }


@app.get("/metrics")
async def get_metrics() -> Dict[str, Any]:
    """
    Get current system metrics from latest.json
    
    Returns:
        dict: System metrics including CPU, memory, disk, network, temperature, GPU, etc.
        
    Raises:
        HTTPException: If metrics file is not found or invalid
    """
    try:
        if not METRICS_FILE.exists():
            # Return empty data with helpful message if file doesn't exist yet
            return {
                "status": "waiting",
                "message": "Metrics file not yet generated. Run host_monitor_loop.sh to start collecting data.",
                "file": str(METRICS_FILE),
                "data": {}
            }
        
        # Read metrics file
        with METRICS_FILE.open('r', encoding='utf-8') as f:
            metrics_data = json.load(f)
        
        # Get file modification time
        file_mtime = METRICS_FILE.stat().st_mtime
        file_timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(file_mtime))
        
        # Return metrics with metadata
        return {
            "status": "ok",
            "file_timestamp": file_timestamp,
            "server_timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "data": metrics_data
        }
        
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=500,
            detail=f"Invalid JSON in metrics file: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error reading metrics: {str(e)}"
        )


@app.post("/refresh")
async def refresh_metrics() -> Dict[str, Any]:
    """
    Trigger manual refresh of metrics by running main_monitor.sh
    """
    try:
        if not MONITOR_SCRIPT.exists():
            raise HTTPException(
                status_code=500,
                detail=f"Monitor script not found at {MONITOR_SCRIPT}"
            )

        # Run the script
        start_time = time.time()
        result = subprocess.run(
            ["bash", str(MONITOR_SCRIPT)],
            capture_output=True,
            text=True,
            timeout=10  # 10s timeout
        )
        duration = time.time() - start_time

        if result.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=f"Monitor script failed: {result.stderr}"
            )

        return {
            "status": "success",
            "message": "Metrics refreshed",
            "duration": f"{duration:.2f}s"
        }

    except subprocess.TimeoutExpired:
        raise HTTPException(
            status_code=504,
            detail="Monitor script timed out"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Refresh failed: {str(e)}"
        )


@app.get("/")
async def root() -> Dict[str, Any]:
    """
    Root endpoint with API information
    
    Returns:
        dict: API documentation
    """
    return {
        "name": "Host System Monitor API",
        "version": "1.0.0",
        "endpoints": {
            "/": "This endpoint (API info)",
            "/health": "Health check",
            "/metrics": "Current system metrics"
        },
        "metrics_file": str(METRICS_FILE),
        "docs": "/docs (Swagger UI)",
        "redoc": "/redoc (ReDoc)"
    }


def main():
    """Start the FastAPI server"""
    print("=" * 60)
    print("  Host System Monitor - TCP API Server")
    print("=" * 60)
    print()
    print(f"[*] Starting API server on {API_HOST}:{API_PORT}")
    print(f"[*] Metrics file: {METRICS_FILE}")
    print()
    print(f"[*] Endpoints:")
    print(f"   - GET  http://localhost:{API_PORT}/         (API Info)")
    print(f"   - GET  http://localhost:{API_PORT}/health   (Health Check)")
    print(f"   - GET  http://localhost:{API_PORT}/metrics  (System Metrics)")
    print(f"   - DOCS http://localhost:{API_PORT}/docs     (Swagger UI)")
    print()
    print(f"[*] Press Ctrl+C to stop")
    print()
    
    # Run uvicorn server
    uvicorn.run(
        app,
        host=API_HOST,
        port=API_PORT,
        log_level="info",
        access_log=True
    )


if __name__ == "__main__":
    main()
