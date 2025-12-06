#!/usr/bin/env python3
"""Quick test to verify GPU data reading"""
import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

import json
from pathlib import Path

# Read current.json
with open('data/metrics/current.json', 'r') as f:
    data = json.load(f)

temp = data.get('temperature', {})
gpus = temp.get('gpus', [])

print(f'GPU count: {len(gpus)}')
print()

for i, gpu in enumerate(gpus):
    print(f'GPU [{i}]:')
    print(f'  Vendor: {gpu.get("vendor")}')
    print(f'  Model: {gpu.get("model")}')
    print(f'  Type: {gpu.get("type")}')
    print(f'  Temp: {gpu.get("temperature_celsius")}°C')
    print(f'  VRAM: {gpu.get("vram_used_mb")}/{gpu.get("vram_total_mb")} MB')
    print()

# Test dashboard code logic
print("Testing dashboard logic:")
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
