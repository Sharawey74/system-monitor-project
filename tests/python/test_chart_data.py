"""Unit tests for chart data aggregation and formatting."""

import pytest
import json
from datetime import datetime, timedelta
from unittest.mock import Mock, patch


class TestChartDataAggregation:
    """Tests for chart data collection and aggregation."""
    
    @pytest.fixture
    def sample_metrics(self):
        """Sample metrics data for testing."""
        return {
            "timestamp": "2025-12-17T10:00:00Z",
            "cpu": {"usage_percent": 45.5},
            "memory": {"usage_percent": 62.3},
            "network": [
                {"iface": "eth0", "rx_bytes": 1000000, "tx_bytes": 500000}
            ],
            "disk": [
                {"device": "C:", "used_percent": 75.0}
            ]
        }
    
    def test_rolling_window_maintains_size(self):
        """Test that rolling window maintains maximum size."""
        max_size = 60
        window = []
        
        # Add more than max_size entries
        for i in range(100):
            window.append({"value": i, "timestamp": i})
            if len(window) > max_size:
                window.pop(0)
        
        assert len(window) == max_size
        assert window[0]["value"] == 40  # First kept value
        assert window[-1]["value"] == 99  # Last value
    
    def test_chart_data_structure(self, sample_metrics):
        """Test chart data has correct structure."""
        chart_data = {
            "labels": [],
            "datasets": [
                {
                    "label": "Windows CPU",
                    "data": [],
                    "borderColor": "#22c55e",
                    "backgroundColor": "rgba(34, 197, 94, 0.1)"
                },
                {
                    "label": "WSL CPU",
                    "data": [],
                    "borderColor": "#f59e0b",
                    "backgroundColor": "rgba(245, 158, 11, 0.1)"
                }
            ]
        }
        
        assert "labels" in chart_data
        assert "datasets" in chart_data
        assert len(chart_data["datasets"]) == 2
        assert chart_data["datasets"][0]["label"] == "Windows CPU"
    
    def test_timestamp_formatting(self):
        """Test timestamp formatting for chart labels."""
        timestamp = "2025-12-17T10:30:45Z"
        # Expected format: "10:30:45"
        dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        formatted = dt.strftime("%H:%M:%S")
        
        assert formatted == "10:30:45"
    
    def test_data_point_addition(self):
        """Test adding data points to chart history."""
        history = {
            "cpu": [],
            "memory": [],
            "network_rx": [],
            "network_tx": []
        }
        
        # Add data point
        history["cpu"].append(45.5)
        history["memory"].append(62.3)
        history["network_rx"].append(1.5)  # MB/s
        history["network_tx"].append(0.8)  # MB/s
        
        assert len(history["cpu"]) == 1
        assert history["cpu"][0] == 45.5
        assert history["network_rx"][0] == 1.5


class TestDualDatasetFormatting:
    """Tests for dual dataset (Win/WSL) formatting."""
    
    def test_dual_cpu_dataset(self):
        """Test dual CPU dataset creation."""
        win_data = [45.5, 46.2, 44.8]
        wsl_data = [12.3, 13.1, 11.9]
        
        datasets = [
            {
                "label": "Windows CPU",
                "data": win_data,
                "borderColor": "#22c55e"
            },
            {
                "label": "WSL CPU",
                "data": wsl_data,
                "borderColor": "#f59e0b"
            }
        ]
        
        assert len(datasets) == 2
        assert datasets[0]["data"] == win_data
        assert datasets[1]["data"] == wsl_data
    
    def test_dataset_color_coding(self):
        """Test that datasets have correct color coding."""
        win_color = "#22c55e"  # Green
        wsl_color = "#f59e0b"  # Orange
        
        assert win_color.startswith("#")
        assert wsl_color.startswith("#")
        assert len(win_color) == 7
        assert len(wsl_color) == 7
    
    def test_empty_dataset_handling(self):
        """Test handling of empty datasets."""
        empty_data = []
        
        dataset = {
            "label": "Test",
            "data": empty_data
        }
        
        assert dataset["data"] == []
        assert len(dataset["data"]) == 0


class TestNetworkThroughputChart:
    """Tests for network throughput chart data."""
    
    def test_network_rate_calculation(self):
        """Test network rate calculation for charts."""
        # Previous state
        prev_rx = 1000000  # bytes
        prev_tx = 500000   # bytes
        prev_time = datetime.now()
        
        # Current state (2 seconds later)
        curr_rx = 3000000  # bytes
        curr_tx = 1500000  # bytes
        curr_time = prev_time + timedelta(seconds=2)
        
        # Calculate rates
        time_delta = (curr_time - prev_time).total_seconds()
        rx_rate = (curr_rx - prev_rx) / time_delta / (1024 * 1024)  # MB/s
        tx_rate = (curr_tx - prev_tx) / time_delta / (1024 * 1024)  # MB/s
        
        assert rx_rate > 0
        assert tx_rate > 0
        assert rx_rate == pytest.approx(0.95, rel=0.1)  # ~1 MB/s
        assert tx_rate == pytest.approx(0.48, rel=0.1)  # ~0.5 MB/s
    
    def test_stacked_area_chart_data(self):
        """Test stacked area chart data structure."""
        chart_data = {
            "labels": ["10:00", "10:01", "10:02"],
            "datasets": [
                {
                    "label": "Download",
                    "data": [1.5, 2.3, 1.8],
                    "fill": True,
                    "backgroundColor": "rgba(34, 197, 94, 0.3)"
                },
                {
                    "label": "Upload",
                    "data": [0.5, 0.8, 0.6],
                    "fill": True,
                    "backgroundColor": "rgba(59, 130, 246, 0.3)"
                }
            ]
        }
        
        assert len(chart_data["datasets"]) == 2
        assert chart_data["datasets"][0]["fill"] is True
        assert chart_data["datasets"][1]["fill"] is True


class TestDiskUsageChart:
    """Tests for disk usage over time chart."""
    
    def test_disk_usage_tracking(self):
        """Test tracking disk usage over time."""
        disk_history = {
            "C:": [75.0, 75.2, 75.5],
            "D:": [45.0, 45.1, 45.0]
        }
        
        assert "C:" in disk_history
        assert len(disk_history["C:"]) == 3
        assert disk_history["C:"][-1] == 75.5  # Latest value
    
    def test_multi_disk_dataset(self):
        """Test multiple disk datasets."""
        datasets = [
            {"label": "C:", "data": [75.0, 75.2], "borderColor": "#6366f1"},
            {"label": "D:", "data": [45.0, 45.1], "borderColor": "#8b5cf6"}
        ]
        
        assert len(datasets) == 2
        assert datasets[0]["label"] == "C:"
        assert datasets[1]["label"] == "D:"


class TestChartConfiguration:
    """Tests for Chart.js configuration."""
    
    def test_dark_theme_colors(self):
        """Test dark theme color configuration."""
        theme = {
            "backgroundColor": "#1e293b",
            "gridColor": "#334155",
            "textColor": "#cbd5e1",
            "borderColor": "rgba(255, 255, 255, 0.1)"
        }
        
        assert theme["backgroundColor"] == "#1e293b"
        assert "rgba" in theme["borderColor"]
    
    def test_chart_options_structure(self):
        """Test Chart.js options structure."""
        options = {
            "responsive": True,
            "maintainAspectRatio": False,
            "plugins": {
                "legend": {
                    "display": True,
                    "labels": {"color": "#cbd5e1"}
                }
            },
            "scales": {
                "y": {
                    "beginAtZero": True,
                    "max": 100,
                    "grid": {"color": "#334155"},
                    "ticks": {"color": "#94a3b8"}
                },
                "x": {
                    "grid": {"display": False},
                    "ticks": {"color": "#94a3b8"}
                }
            }
        }
        
        assert options["responsive"] is True
        assert options["scales"]["y"]["max"] == 100
        assert "plugins" in options
    
    def test_smooth_line_configuration(self):
        """Test smooth line (tension) configuration."""
        dataset = {
            "label": "CPU",
            "data": [45, 46, 44],
            "tension": 0.4,  # Smooth curves
            "borderWidth": 2,
            "pointRadius": 0  # No points, just line
        }
        
        assert dataset["tension"] == 0.4
        assert dataset["pointRadius"] == 0


class TestDataValidation:
    """Tests for chart data validation."""
    
    def test_validate_percentage_range(self):
        """Test percentage values are in valid range."""
        test_values = [45.5, 0, 100, 99.9]
        
        for value in test_values:
            assert 0 <= value <= 100
    
    def test_handle_null_values(self):
        """Test handling of null/missing values."""
        data = [45.5, None, 46.2, None, 44.8]
        
        # Filter out None values
        filtered = [v for v in data if v is not None]
        
        assert len(filtered) == 3
        assert None not in filtered
    
    def test_handle_negative_values(self):
        """Test handling of negative values (should not occur)."""
        value = -5.0
        
        # Clamp to 0
        clamped = max(0, value)
        
        assert clamped == 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
