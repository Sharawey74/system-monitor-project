#!/usr/bin/env python3
"""Test if metrics collector loads GPU data correctly"""

import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from core.metrics_collector import load_current_metrics

metrics = load_current_metrics()

print("=" * 60)
print("METRICS COLLECTOR TEST")
print("=" * 60)

# Check CPU
cpu = metrics.get('cpu', {})
print(f"\nCPU Usage: {cpu.get('usage_percent')}%")

# Check temperature structure
temp = metrics.get('temperature', {})
print(f"\nTemperature Status: {temp.get('status')}")
print(f"GPU Count: {temp.get('gpu_count', 0)}")

# Check GPUs array
gpus = temp.get('gpus', [])
print(f"\nGPUs Array Length: {len(gpus)}")

if gpus:
    for i, gpu in enumerate(gpus):
        print(f"\n--- GPU [{i}] ---")
        print(f"  Vendor: {gpu.get('vendor')}")
        print(f"  Model: {gpu.get('model')}")
        print(f"  Type: {gpu.get('type')}")
        print(f"  Temperature: {gpu.get('temperature_celsius')}°C")
        print(f"  Temp Source: {gpu.get('temperature_source')}")
        print(f"  VRAM: {gpu.get('vram_used_mb')}/{gpu.get('vram_total_mb')} MB")
else:
    print("\n⚠️  No GPUs found in metrics!")

print("\n" + "=" * 60)
