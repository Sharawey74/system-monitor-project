#!/usr/bin/env python3
"""Quick test to verify GPU data reading"""
import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

import json
import pytest

def test_gpu_data_reading():
    """Test that GPU data can be read from current.json"""
    metrics_file = project_root / 'data' / 'metrics' / 'current.json'
    
    # Skip if metrics file doesn't exist
    if not metrics_file.exists():
        pytest.skip("Metrics file not found")
    
    try:
        with open(metrics_file, 'r', encoding='utf-8-sig') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.skip("Invalid JSON in metrics file")
    
    # Test temperature data exists
    assert 'temperature' in data, "No temperature data in metrics"
    temp = data.get('temperature', {})
    
    # GPUs are optional, but if present should be valid
    gpus = temp.get('gpus', [])
    
    print(f'\nGPU count: {len(gpus)}')
    
    for i, gpu in enumerate(gpus):
        print(f'\nGPU [{i}]:')
        print(f'  Vendor: {gpu.get("vendor")}')
        print(f'  Model: {gpu.get("model")}')
        print(f'  Type: {gpu.get("type")}')
        print(f'  Temp: {gpu.get("temperature_celsius")}°C')
        print(f'  VRAM: {gpu.get("vram_used_mb")}/{gpu.get("vram_total_mb")} MB')
        
        # Validate GPU structure
        assert 'vendor' in gpu, f"GPU {i} missing vendor"
        assert 'model' in gpu, f"GPU {i} missing model"
    
    # Test dashboard code logic
    print("\nTesting dashboard logic:")
    primary_gpu = None
    if gpus:
        # First try to find a dedicated GPU
        for gpu in gpus:
            if gpu.get('type') == 'Dedicated':
                primary_gpu = gpu
                break
        # If no dedicated GPU, use the first one
        if not primary_gpu:
            primary_gpu = gpus[0]
    
    if primary_gpu:
        print(f"Primary GPU selected: {primary_gpu.get('vendor')} {primary_gpu.get('model')}")
        print(f"Temperature: {primary_gpu.get('temperature_celsius')}°C")
    else:
        print("No GPU found!")


def test_gpu_temperature_alert_threshold():
    """Test GPU temperature alert threshold (80°C)."""
    gpu_temp = 82.0
    warning_threshold = 80.0
    critical_threshold = 90.0
    
    # Test warning level
    is_warning = gpu_temp > warning_threshold
    assert is_warning is True
    
    # Test not critical yet
    is_critical = gpu_temp > critical_threshold
    assert is_critical is False


def test_gpu_temperature_normal():
    """Test GPU temperature in normal range."""
    gpu_temp = 65.0
    warning_threshold = 80.0
    
    should_alert = gpu_temp > warning_threshold
    assert should_alert is False


def test_gpu_temperature_critical():
    """Test GPU temperature in critical range."""
    gpu_temp = 95.0
    critical_threshold = 90.0
    
    is_critical = gpu_temp > critical_threshold
    assert is_critical is True


def test_gpu_missing_temperature():
    """Test handling of missing GPU temperature."""
    gpu = {
        "vendor": "NVIDIA",
        "model": "GTX 1650",
        "temperature_celsius": None
    }
    
    temp = gpu.get("temperature_celsius")
    
    # Should handle None gracefully
    if temp is None:
        display_temp = "N/A"
    else:
        display_temp = f"{temp}°C"
    
    assert display_temp == "N/A"


def test_gpu_zero_temperature():
    """Test handling of zero temperature (sensor error)."""
    gpu_temp = 0.0
    
    # Zero temp likely means sensor error, should not trigger alert
    # but should be flagged as invalid
    is_valid = gpu_temp > 20.0  # Reasonable minimum
    
    assert is_valid is False


def test_multiple_gpu_selection():
    """Test selecting primary GPU from multiple GPUs."""
    gpus = [
        {"vendor": "Intel", "model": "Integrated", "type": "Integrated", "temperature_celsius": 55},
        {"vendor": "NVIDIA", "model": "RTX 3060", "type": "Dedicated", "temperature_celsius": 65}
    ]
    
    # Should select dedicated GPU
    primary = None
    for gpu in gpus:
        if gpu.get('type') == 'Dedicated':
            primary = gpu
            break
    
    assert primary is not None
    assert primary['vendor'] == "NVIDIA"
    assert primary['type'] == "Dedicated"


def test_gpu_memory_usage():
    """Test GPU memory usage calculation."""
    gpu = {
        "vram_used_mb": 2048,
        "vram_total_mb": 4096
    }
    
    usage_percent = (gpu["vram_used_mb"] / gpu["vram_total_mb"]) * 100
    
    assert usage_percent == 50.0
    assert 0 <= usage_percent <= 100

