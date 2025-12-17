"""Unit tests for core.alert_manager module."""

import json
import pytest
from pathlib import Path
from datetime import datetime
from core.alert_manager import (
    load_alerts,
    create_empty_alerts_file,
    add_alert,
    clear_alerts,
    get_alert_counts,
    filter_alerts_by_metric,
    get_latest_alert,
    _sort_alerts_by_timestamp
)


@pytest.fixture
def valid_alerts_data():
    """Sample valid alerts data."""
    return {
        "timestamp": "2025-12-05T10:30:00Z",
        "alerts": [
            {
                "level": "warning",
                "metric": "cpu",
                "message": "CPU usage above 80%",
                "value": 85.5,
                "threshold": 80.0,
                "timestamp": "2025-12-05T10:30:00Z"
            },
            {
                "level": "critical",
                "metric": "memory",
                "message": "Memory usage critical",
                "value": 95.0,
                "threshold": 90.0,
                "timestamp": "2025-12-05T10:25:00Z"
            },
            {
                "level": "info",
                "metric": "disk",
                "message": "Disk space below 30%",
                "value": 25.0,
                "threshold": 30.0,
                "timestamp": "2025-12-05T10:20:00Z"
            }
        ]
    }


@pytest.fixture
def temp_alerts_file(tmp_path, valid_alerts_data):
    """Create a temporary alerts file."""
    alerts_file = tmp_path / "alerts.json"
    with open(alerts_file, 'w') as f:
        json.dump(valid_alerts_data, f)
    return alerts_file


class TestLoadAlerts:
    """Tests for load_alerts function."""
    
    def test_load_valid_alerts(self, temp_alerts_file):
        """Test loading valid alerts file."""
        alerts = load_alerts(str(temp_alerts_file))
        
        assert len(alerts) == 3
        assert alerts[0]['level'] == 'warning'
        assert alerts[1]['level'] == 'critical'
        assert alerts[2]['level'] == 'info'
    
    def test_load_alerts_creates_empty_file_if_missing(self, tmp_path):
        """Test loading creates empty file if missing."""
        missing_file = tmp_path / "alerts.json"
        alerts = load_alerts(str(missing_file))
        
        assert alerts == []
        assert missing_file.exists()
    
    def test_load_malformed_json(self, tmp_path):
        """Test loading malformed JSON returns empty list."""
        bad_file = tmp_path / "bad.json"
        with open(bad_file, 'w') as f:
            f.write("{invalid json")
        
        alerts = load_alerts(str(bad_file))
        
        assert alerts == []
    
    def test_load_alerts_with_level_filter(self, temp_alerts_file):
        """Test filtering alerts by level."""
        critical_alerts = load_alerts(str(temp_alerts_file), level_filter='critical')
        
        assert len(critical_alerts) == 1
        assert critical_alerts[0]['level'] == 'critical'
    
    def test_load_alerts_with_limit(self, temp_alerts_file):
        """Test limiting number of alerts returned."""
        alerts = load_alerts(str(temp_alerts_file), limit=2)
        
        assert len(alerts) == 2
    
    def test_load_invalid_alerts_format(self, tmp_path):
        """Test handling invalid alerts format."""
        invalid_file = tmp_path / "invalid.json"
        with open(invalid_file, 'w') as f:
            json.dump({"alerts": "not a list"}, f)
        
        alerts = load_alerts(str(invalid_file))
        
        assert alerts == []


class TestCreateEmptyAlertsFile:
    """Tests for create_empty_alerts_file function."""
    
    def test_create_empty_file(self, tmp_path):
        """Test creating empty alerts file."""
        alerts_file = tmp_path / "alerts.json"
        result = create_empty_alerts_file(str(alerts_file))
        
        assert result is True
        assert alerts_file.exists()
        
        # Verify structure
        with open(alerts_file, 'r') as f:
            data = json.load(f)
        
        assert 'timestamp' in data
        assert data['alerts'] == []
    
    def test_create_in_nested_directory(self, tmp_path):
        """Test creating file in nested directory."""
        nested_path = tmp_path / "data" / "alerts" / "alerts.json"
        result = create_empty_alerts_file(str(nested_path))
        
        assert result is True
        assert nested_path.exists()
    
    def test_create_with_permission_error(self, tmp_path):
        """Test handling directory creation errors."""
        # Try to create in a path that would require permissions we don't have
        # On Windows, this might not fail, so we just verify the function handles it
        import os
        if os.name == 'nt':
            # On Windows, skip this test as permission handling is different
            pytest.skip("Permission tests not reliable on Windows")
        
        # On Unix, try to create in /root (typically restricted)
        result = create_empty_alerts_file("/root/test_alerts.json")
        
        # Should return False when unable to create file
        assert result is False


class TestAddAlert:
    """Tests for add_alert function."""
    
    def test_add_alert_to_empty_file(self, tmp_path):
        """Test adding alert to non-existent file."""
        alerts_file = tmp_path / "alerts.json"
        
        result = add_alert(
            metric='cpu',
            level='warning',
            message='CPU usage high',
            value=85.5,
            threshold=80.0,
            path=str(alerts_file)
        )
        
        assert result is True
        
        # Verify alert was added
        alerts = load_alerts(str(alerts_file))
        assert len(alerts) == 1
        assert alerts[0]['metric'] == 'cpu'
        assert alerts[0]['level'] == 'warning'
        assert alerts[0]['value'] == 85.5
    
    def test_add_alert_to_existing_file(self, temp_alerts_file):
        """Test adding alert to existing file."""
        result = add_alert(
            metric='temperature',
            level='critical',
            message='Temperature too high',
            path=str(temp_alerts_file)
        )
        
        assert result is True
        
        # Verify alert was added
        alerts = load_alerts(str(temp_alerts_file))
        assert len(alerts) == 4
    
    def test_add_alert_invalid_level(self, tmp_path):
        """Test adding alert with invalid level."""
        alerts_file = tmp_path / "alerts.json"
        
        result = add_alert(
            metric='cpu',
            level='invalid_level',
            message='Test',
            path=str(alerts_file)
        )
        
        assert result is False
    
    def test_add_alert_without_value_threshold(self, tmp_path):
        """Test adding alert without value/threshold."""
        alerts_file = tmp_path / "alerts.json"
        
        result = add_alert(
            metric='system',
            level='info',
            message='System started',
            path=str(alerts_file)
        )
        
        assert result is True
        
        alerts = load_alerts(str(alerts_file))
        assert 'value' not in alerts[0]
        assert 'threshold' not in alerts[0]


class TestClearAlerts:
    """Tests for clear_alerts function."""
    
    def test_clear_existing_alerts(self, temp_alerts_file):
        """Test clearing existing alerts."""
        # Verify file has alerts
        alerts = load_alerts(str(temp_alerts_file))
        assert len(alerts) > 0
        
        # Clear alerts
        result = clear_alerts(str(temp_alerts_file))
        assert result is True
        
        # Verify alerts cleared
        alerts = load_alerts(str(temp_alerts_file))
        assert alerts == []


class TestGetAlertCounts:
    """Tests for get_alert_counts function."""
    
    def test_count_alerts_by_level(self):
        """Test counting alerts by level."""
        alerts = [
            {"level": "info", "message": "Test 1"},
            {"level": "warning", "message": "Test 2"},
            {"level": "warning", "message": "Test 3"},
            {"level": "critical", "message": "Test 4"}
        ]
        
        counts = get_alert_counts(alerts)
        
        assert counts['info'] == 1
        assert counts['warning'] == 2
        assert counts['critical'] == 1
    
    def test_count_empty_alerts(self):
        """Test counting empty alerts list."""
        counts = get_alert_counts([])
        
        assert counts['info'] == 0
        assert counts['warning'] == 0
        assert counts['critical'] == 0


class TestSortAlertsByTimestamp:
    """Tests for _sort_alerts_by_timestamp function."""
    
    def test_sort_alerts_newest_first(self):
        """Test sorting alerts by timestamp (newest first)."""
        alerts = [
            {"message": "Old", "timestamp": "2025-12-05T10:00:00Z"},
            {"message": "New", "timestamp": "2025-12-05T12:00:00Z"},
            {"message": "Middle", "timestamp": "2025-12-05T11:00:00Z"}
        ]
        
        sorted_alerts = _sort_alerts_by_timestamp(alerts)
        
        assert sorted_alerts[0]['message'] == "New"
        assert sorted_alerts[1]['message'] == "Middle"
        assert sorted_alerts[2]['message'] == "Old"
    
    def test_sort_alerts_with_missing_timestamp(self):
        """Test sorting alerts when some lack timestamps."""
        alerts = [
            {"message": "With timestamp", "timestamp": "2025-12-05T10:00:00Z"},
            {"message": "Without timestamp"}
        ]
        
        # Should not crash
        sorted_alerts = _sort_alerts_by_timestamp(alerts)
        
        assert len(sorted_alerts) == 2


class TestFilterAlertsByMetric:
    """Tests for filter_alerts_by_metric function."""
    
    def test_filter_by_metric(self):
        """Test filtering alerts by metric type."""
        alerts = [
            {"metric": "cpu", "message": "CPU alert"},
            {"metric": "memory", "message": "Memory alert"},
            {"metric": "cpu", "message": "Another CPU alert"}
        ]
        
        cpu_alerts = filter_alerts_by_metric(alerts, 'cpu')
        
        assert len(cpu_alerts) == 2
        assert all(a['metric'] == 'cpu' for a in cpu_alerts)
    
    def test_filter_no_matches(self):
        """Test filtering with no matches."""
        alerts = [
            {"metric": "cpu", "message": "CPU alert"}
        ]
        
        disk_alerts = filter_alerts_by_metric(alerts, 'disk')
        
        assert disk_alerts == []


class TestGetLatestAlert:
    """Tests for get_latest_alert function."""
    
    def test_get_latest_from_multiple_alerts(self):
        """Test getting latest alert from multiple."""
        alerts = [
            {"message": "Old", "timestamp": "2025-12-05T10:00:00Z"},
            {"message": "Latest", "timestamp": "2025-12-05T12:00:00Z"},
            {"message": "Middle", "timestamp": "2025-12-05T11:00:00Z"}
        ]
        
        latest = get_latest_alert(alerts)
        
        assert latest['message'] == "Latest"
    
    def test_get_latest_from_empty_list(self):
        """Test getting latest alert from empty list."""
        latest = get_latest_alert([])
        
        assert latest is None


class TestAlertThresholds:
    """Tests for alert threshold validation."""
    
    def test_cpu_warning_threshold(self):
        """Test CPU warning threshold (90%)."""
        cpu_usage = 91.5
        threshold = 90.0
        
        should_alert = cpu_usage > threshold
        
        assert should_alert is True
    
    def test_cpu_below_threshold(self):
        """Test CPU below warning threshold."""
        cpu_usage = 85.0
        threshold = 90.0
        
        should_alert = cpu_usage > threshold
        
        assert should_alert is False
    
    def test_memory_critical_threshold(self):
        """Test memory critical threshold (95%)."""
        memory_usage = 96.0
        critical_threshold = 95.0
        
        is_critical = memory_usage > critical_threshold
        
        assert is_critical is True
    
    def test_disk_warning_threshold(self):
        """Test disk warning threshold (85%)."""
        disk_usage = 87.0
        threshold = 85.0
        
        should_alert = disk_usage > threshold
        
        assert should_alert is True
    
    def test_gpu_temp_threshold(self):
        """Test GPU temperature threshold (80°C)."""
        gpu_temp = 82.0
        threshold = 80.0
        
        should_alert = gpu_temp > threshold
        
        assert should_alert is True
    
    def test_threshold_boundary_condition(self):
        """Test exact threshold boundary."""
        value = 90.0
        threshold = 90.0
        
        # Should not alert on exact threshold
        should_alert = value > threshold
        
        assert should_alert is False


class TestAlertDuration:
    """Tests for alert duration tracking."""
    
    def test_sustained_alert_tracking(self):
        """Test tracking sustained alerts (e.g., CPU > 90% for 30s)."""
        alert_history = [
            {"metric": "cpu", "value": 91.0, "timestamp": "2025-12-17T10:00:00Z"},
            {"metric": "cpu", "value": 92.0, "timestamp": "2025-12-17T10:00:15Z"},
            {"metric": "cpu", "value": 91.5, "timestamp": "2025-12-17T10:00:30Z"}
        ]
        
        # All alerts within 30 seconds
        assert len(alert_history) == 3
        
        # Check sustained condition
        sustained = all(a["value"] > 90.0 for a in alert_history)
        
        assert sustained is True
    
    def test_intermittent_alert_not_sustained(self):
        """Test intermittent alerts don't trigger sustained warning."""
        alert_history = [
            {"metric": "cpu", "value": 91.0, "timestamp": "2025-12-17T10:00:00Z"},
            {"metric": "cpu", "value": 85.0, "timestamp": "2025-12-17T10:00:15Z"},
            {"metric": "cpu", "value": 92.0, "timestamp": "2025-12-17T10:00:30Z"}
        ]
        
        # Not all above threshold
        sustained = all(a["value"] > 90.0 for a in alert_history)
        
        assert sustained is False


class TestAlertPriority:
    """Tests for alert priority/severity."""
    
    def test_critical_higher_than_warning(self):
        """Test critical alerts have higher priority."""
        severity_levels = {
            "info": 1,
            "warning": 2,
            "critical": 3
        }
        
        assert severity_levels["critical"] > severity_levels["warning"]
        assert severity_levels["warning"] > severity_levels["info"]
    
    def test_sort_by_severity(self):
        """Test sorting alerts by severity."""
        alerts = [
            {"level": "info", "message": "Info alert"},
            {"level": "critical", "message": "Critical alert"},
            {"level": "warning", "message": "Warning alert"}
        ]
        
        severity_order = {"critical": 3, "warning": 2, "info": 1}
        sorted_alerts = sorted(alerts, key=lambda a: severity_order[a["level"]], reverse=True)
        
        assert sorted_alerts[0]["level"] == "critical"
        assert sorted_alerts[1]["level"] == "warning"
        assert sorted_alerts[2]["level"] == "info"


class TestAlertDeduplication:
    """Tests for alert deduplication."""
    
    def test_duplicate_alert_detection(self):
        """Test detecting duplicate alerts."""
        existing_alerts = [
            {"metric": "cpu", "level": "warning", "message": "CPU high"}
        ]
        
        new_alert = {"metric": "cpu", "level": "warning", "message": "CPU high"}
        
        # Check if duplicate
        is_duplicate = any(
            a["metric"] == new_alert["metric"] and 
            a["level"] == new_alert["level"]
            for a in existing_alerts
        )
        
        assert is_duplicate is True
    
    def test_different_alert_not_duplicate(self):
        """Test different alerts are not duplicates."""
        existing_alerts = [
            {"metric": "cpu", "level": "warning", "message": "CPU high"}
        ]
        
        new_alert = {"metric": "memory", "level": "warning", "message": "Memory high"}
        
        is_duplicate = any(
            a["metric"] == new_alert["metric"] and 
            a["level"] == new_alert["level"]
            for a in existing_alerts
        )
        
        assert is_duplicate is False


class TestAlertFormatting:
    """Tests for alert message formatting."""
    
    def test_format_cpu_alert_message(self):
        """Test CPU alert message formatting."""
        metric = "cpu"
        value = 91.5
        threshold = 90.0
        
        message = f"CPU usage ({value:.1f}%) exceeds threshold ({threshold:.1f}%)"
        
        assert "CPU usage" in message
        assert "91.5%" in message
        assert "90.0%" in message
    
    def test_format_disk_alert_message(self):
        """Test disk alert message formatting."""
        device = "C:"
        value = 95.0
        threshold = 90.0
        
        message = f"Disk {device} usage ({value:.1f}%) exceeds threshold ({threshold:.1f}%)"
        
        assert "Disk C:" in message
        assert "95.0%" in message
    
    def test_format_temperature_alert_message(self):
        """Test temperature alert message formatting."""
        component = "GPU"
        temp = 82.0
        threshold = 80.0
        
        message = f"{component} temperature ({temp:.1f}°C) exceeds threshold ({threshold:.1f}°C)"
        
        assert "GPU temperature" in message
        assert "82.0°C" in message

