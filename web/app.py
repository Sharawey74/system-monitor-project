#!/usr/bin/env python3
"""
System Monitor Dashboard v5.0 - Backend
Serves the modern cyber-aesthetic dashboard and creates a strict data pipeline
from Host/output/latest.json to the frontend.
"""

import sys
import json
import logging
from pathlib import Path
from flask import Flask, render_template, jsonify, send_file, request
from datetime import datetime
import os
import requests

# Ensure 'web' directory is in path for imports regardless of run context
current_dir = Path(__file__).parent
if str(current_dir) not in sys.path:
    sys.path.append(str(current_dir))

try:
    from report_generator import ReportGenerator
except ImportError:
    from web.report_generator import ReportGenerator

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / 'data'
JSON_DIR = PROJECT_ROOT / 'json'
HOST_OUTPUT_DIR = PROJECT_ROOT / 'Host' / 'output'
HOST_LATEST_JSON = HOST_OUTPUT_DIR / 'latest.json'
HOST2_OUTPUT_DIR = PROJECT_ROOT / 'Host2'
GO_LATEST_JSON = HOST2_OUTPUT_DIR / 'bin' / 'go_latest.json'
REPORTS_DIR = PROJECT_ROOT / 'reports'
ALERTS_FILE = DATA_DIR / 'alerts' / 'alerts.json'

# Native Agent Configuration
NATIVE_AGENT_URL = os.getenv('NATIVE_AGENT_URL', 'http://host.docker.internal:8889')
USE_NATIVE_AGENT = os.getenv('USE_NATIVE_AGENT', 'false').lower() == 'true'

# Initialize Report Generator
report_gen = ReportGenerator(HOST_LATEST_JSON, ALERTS_FILE, REPORTS_DIR)

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('dashboard-v5')

app = Flask(__name__,
            template_folder=str(PROJECT_ROOT / 'templates'),
            static_folder=str(PROJECT_ROOT / 'static'))

@app.route('/')
def index():
    """Render the V5 Dashboard."""
    return render_template('dashboard.html')

@app.route('/api/metrics')
def get_metrics():
    """
    Primary Metrics Endpoint.
    Strategy:
    1. Check Host/output/latest.json (Real-time data from native host).
    2. Fallback to newest file in json/ (Historical data if host is offline).
    3. Return 'unavailable' state if neither exists.
    """
    # 1. Try Host Output (Preferred)
    if HOST_LATEST_JSON.exists():
        try:
            with open(HOST_LATEST_JSON, 'r', encoding='utf-8') as f:
                data = json.load(f)
            return jsonify({
                'success': True,
                'source': 'host_direct',
                'timestamp': datetime.now().isoformat(),
                'data': data
            })
        except Exception as e:
            logger.error(f"Failed to read host json: {e}")

    # 2. Try Latest Log in json/ directory
    try:
        if JSON_DIR.exists():
            json_files = sorted(JSON_DIR.glob('*.json'), key=lambda p: p.stat().st_mtime, reverse=True)
            if json_files:
                latest_log = json_files[0]
                with open(latest_log, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                return jsonify({
                    'success': True,
                    'source': 'archive_log',
                    'timestamp': datetime.now().isoformat(),
                    'file': latest_log.name,
                    'data': data
                })
    except Exception as e:
        logger.error(f"Failed to read archive json: {e}")

    # 3. No Data Available
    return jsonify({
        'success': False,
        'error': 'No metrics available. Ensure Host Monitor is running.'
    }), 503

@app.route('/api/metrics/native')
def get_native_metrics():
    """
    Proxy endpoint for Native Go Agent metrics.
    Strategy:
    1. Try live API (http://localhost:8889)
    2. Fallback to reading 'Host2/go_latest.json' (if agent is writing files but API unreachable)
    """
    # 1. Try Live API
    try:
        response = requests.get(f"{NATIVE_AGENT_URL}/metrics", timeout=2)
        if response.status_code == 200:
            return jsonify({
                'success': True,
                'source': 'native_agent_api',
                'timestamp': datetime.now().isoformat(),
                'data': response.json()
            })
    except:
        pass

    # 2. Try File Fallback
    if GO_LATEST_JSON.exists():
        try:
            with open(GO_LATEST_JSON, 'r', encoding='utf-8') as f:
                data = json.load(f)
            return jsonify({
                'success': True,
                'source': 'native_agent_file',
                'timestamp': datetime.now().isoformat(),
                'data': data
            })
        except Exception as e:
            logger.error(f"Failed to read native json file: {e}")

    return jsonify({
        'success': False,
        'error': 'Native agent unavailable (API and File failed)'
    }), 503

@app.route('/api/metrics/dual')
def get_dual_metrics():
    """
    Returns BOTH Legacy (Bash) and Native (Go) metrics for side-by-side comparison.
    """
    legacy_data = None
    native_data = None

    # Get Legacy
    if HOST_LATEST_JSON.exists():
        try:
            with open(HOST_LATEST_JSON, 'r', encoding='utf-8') as f:
                legacy_data = json.load(f)
        except: pass

    # Get Native (File preferred for speed, else API)
    if GO_LATEST_JSON.exists():
        try:
            with open(GO_LATEST_JSON, 'r', encoding='utf-8') as f:
                native_data = json.load(f)
        except: pass
    
    # If native file missing, try API
    if not native_data:
        try:
            response = requests.get(f"{NATIVE_AGENT_URL}/metrics", timeout=1)
            if response.status_code == 200:
                native_data = response.json()
        except: pass

    return jsonify({
        'success': True,
        'timestamp': datetime.now().isoformat(),
        'legacy': legacy_data,
        'native': native_data
    })

@app.route('/api/metrics/source')
def get_metrics_source():
    """Return which data source is currently active."""
    return jsonify({
        'use_native': USE_NATIVE_AGENT,
        'native_url': NATIVE_AGENT_URL,
        'legacy_available': HOST_LATEST_JSON.exists(),
        'native_file_available': GO_LATEST_JSON.exists()
    })

@app.route('/api/reports/generate', methods=['POST'])
def generate_report():
    """Generate a system report on demand."""
    try:
        # Fetch Dual Metrics (similar to get_dual_metrics)
        legacy_data = None
        native_data = None

        # 1. Get Legacy
        if HOST_LATEST_JSON.exists():
            try:
                with open(HOST_LATEST_JSON, 'r', encoding='utf-8') as f:
                    legacy_data = json.load(f)
            except: pass
        
        # Fallback for Legacy if missing
        if not legacy_data and JSON_DIR.exists():
            try:
                json_files = sorted(JSON_DIR.glob('*.json'), key=lambda p: p.stat().st_mtime, reverse=True)
                if json_files:
                    with open(json_files[0], 'r', encoding='utf-8') as f:
                        legacy_data = json.load(f)
            except: pass

        # 2. Get Native
        if GO_LATEST_JSON.exists():
            try:
                with open(GO_LATEST_JSON, 'r', encoding='utf-8') as f:
                    native_data = json.load(f)
            except: pass
        
        if not native_data:
            try:
                response = requests.get(f"{NATIVE_AGENT_URL}/metrics", timeout=1)
                if response.status_code == 200:
                    native_data = response.json()
            except: pass

        if not legacy_data and not native_data:
             return jsonify({'success': False, 'error': 'No metrics available to generate report'})
        
        # Determine alerts (mock or load real)
        alerts_data = []
        if ALERTS_FILE.exists():
            with open(ALERTS_FILE, 'r', encoding='utf-8') as f:
                alerts_data = json.load(f)

        html_path, md_path = report_gen.generate_report(legacy_data, native_data, alerts_data)
        
        return jsonify({
            'success': True, 
            'files': {
                'html': str(html_path),
                'markdown': str(md_path)
            }
        })
    except Exception as e:
        logger.error(f"Report generation failed: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/reports/download/html/<filename>')
def download_report_html(filename):
    """Download HTML report."""
    return send_file(REPORTS_DIR / 'html' / filename, as_attachment=True)


@app.route('/api/refresh', methods=['POST'])
def trigger_refresh():
    """
    Trigger immediate metric collection on Host and Native Agent.
    """
    results = {}
    
    # 1. Refresh Legacy Host (if URL available)
    host_api_url = os.getenv('HOST_API_URL', 'http://host.docker.internal:8888')
    try:
        resp = requests.post(f"{host_api_url}/refresh", timeout=12)
        results['legacy'] = resp.json() if resp.status_code == 200 else {'error': resp.text}
    except Exception as e:
        results['legacy'] = {'error': str(e)}

    # 2. Refresh Native Agent (if supported)
    if os.getenv('USE_NATIVE_AGENT', 'false').lower() == 'true' or True: # Try anyway
        native_url = os.getenv('NATIVE_AGENT_URL', 'http://host.docker.internal:8889')
        try:
            resp = requests.post(f"{native_url}/refresh", timeout=5)
            results['native'] = resp.json() if resp.status_code == 200 else {'error': resp.text}
        except Exception as e:
            results['native'] = {'error': str(e)}
    
    return jsonify({
        'success': True,
        'results': results
    })


@app.route('/api/health')
def health_check():
    """Simple health check for Docker."""
    return jsonify({'status': 'healthy', 'version': '5.0'})

def run_server(host='0.0.0.0', port=5000, debug=False):
    """Start the Flask server."""
    print(f"🚀 System Monitor v5.0 Starting...")
    print(f"📂 Project Root: {PROJECT_ROOT}")
    print(f"📡 Metrics Source: {HOST_LATEST_JSON}")
    print(f"🌍 Server: http://{host}:{port}")
    
    app.run(host=host, port=port, debug=debug)

if __name__ == '__main__':
    run_server()
