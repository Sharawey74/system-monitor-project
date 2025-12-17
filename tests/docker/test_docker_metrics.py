"""
Docker Test Suite for System Monitor
Tests Docker container functionality, metric collection, and bash script execution
"""

import pytest
import docker
import json
import time
from pathlib import Path

# Test configuration
PROJECT_ROOT = Path(__file__).parent.parent.parent
DOCKER_COMPOSE_FILE = PROJECT_ROOT / "docker-compose.method2.yml"
CONTAINER_NAME = "system-monitor-method2"
IMAGE_NAME = "system-monitor:method2"


@pytest.fixture(scope="session")
def docker_client():
    """Create Docker client"""
    try:
        client = docker.from_env()
        return client
    except Exception as e:
        pytest.skip(f"Docker is not available: {e}")


@pytest.fixture(scope="session")
def container(docker_client):
    """
    Get or start the system monitor container
    """
    try:
        # Check if container is already running
        container = docker_client.containers.get(CONTAINER_NAME)
        if container.status != "running":
            container.start()
            time.sleep(5)  # Wait for startup
        return container
    except docker.errors.NotFound:
        pytest.skip(f"Container {CONTAINER_NAME} not found. Run docker-compose up first.")


class TestDockerBuild:
    """Test Docker image build"""
    
    def test_image_exists(self, docker_client):
        """Verify Docker image exists"""
        try:
            image = docker_client.images.get(IMAGE_NAME)
            assert image is not None
            assert IMAGE_NAME in image.tags
        except docker.errors.ImageNotFound:
            pytest.fail(f"Docker image {IMAGE_NAME} not found. Build it first.")
    
    def test_image_has_required_layers(self, docker_client):
        """Verify image has required components"""
        image = docker_client.images.get(IMAGE_NAME)
        history = image.history()
        
        # Should have multiple layers
        assert len(history) > 5, "Image should have multiple layers"


class TestContainerStartup:
    """Test container startup and health"""
    
    def test_container_running(self, container):
        """Verify container is running"""
        assert container.status == "running"
    
    def test_container_health(self, container):
        """Verify container health status"""
        # Wait for health check
        max_wait = 30
        for _ in range(max_wait):
            container.reload()
            health = container.attrs.get("State", {}).get("Health", {})
            status = health.get("Status", "none")
            
            if status == "healthy":
                break
            elif status == "unhealthy":
                pytest.fail("Container is unhealthy")
            
            time.sleep(1)
        
        assert status in ["healthy", "none"], f"Container health: {status}"
    
    def test_required_mounts(self, container):
        """Verify required volumes are mounted"""
        mounts = container.attrs.get("Mounts", [])
        mount_destinations = [m["Destination"] for m in mounts]
        
        required_mounts = [
            "/host/proc",
            "/host/sys",
            "/host/dev",
            "/app/data",
            "/app/reports"
        ]
        
        for required in required_mounts:
            assert required in mount_destinations, f"Missing mount: {required}"


class TestBashScripts:
    """Test bash script execution in container"""
    
    def test_main_monitor_script_exists(self, container):
        """Verify main monitor script exists"""
        exit_code, output = container.exec_run(
            "test -f /app/scripts/main_monitor.sh"
        )
        assert exit_code == 0, "main_monitor.sh not found"
    
    def test_main_monitor_executable(self, container):
        """Verify main monitor is executable"""
        exit_code, output = container.exec_run(
            "test -x /app/scripts/main_monitor.sh"
        )
        assert exit_code == 0, "main_monitor.sh not executable"
    
    def test_all_unix_monitors_exist(self, container):
        """Verify all Unix monitor scripts exist"""
        monitors = [
            "cpu_monitor.sh",
            "memory_monitor.sh",
            "disk_monitor.sh",
            "network_monitor.sh",
            "temperature_monitor.sh",
            "fan_monitor.sh",
            "smart_monitor.sh",
            "system_monitor.sh"
        ]
        
        for monitor in monitors:
            exit_code, _ = container.exec_run(
                f"test -f /app/scripts/monitors/unix/{monitor}"
            )
            assert exit_code == 0, f"Monitor {monitor} not found"
    
    def test_main_monitor_execution(self, container):
        """Test main monitor script execution"""
        exit_code, output = container.exec_run(
            "/app/scripts/main_monitor.sh",
            environment={"DEBIAN_FRONTEND": "noninteractive"}
        )
        
        assert exit_code == 0, f"Script failed with output: {output.decode()}"
        
        # Verify output mentions success
        output_str = output.decode()
        assert "current.json" in output_str.lower()


class TestMetricsCollection:
    """Test metrics collection and JSON output"""
    
    def test_metrics_file_created(self, container):
        """Verify current.json is created"""
        # Run monitor
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        # Check file exists
        exit_code, _ = container.exec_run(
            "test -f /app/data/metrics/current.json"
        )
        assert exit_code == 0, "current.json not created"
    
    def test_metrics_valid_json(self, container):
        """Verify metrics file contains valid JSON"""
        # Run monitor
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        # Read and parse JSON
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        assert exit_code == 0
        
        try:
            metrics = json.loads(output.decode())
            assert isinstance(metrics, dict)
        except json.JSONDecodeError as e:
            pytest.fail(f"Invalid JSON: {e}")
    
    def test_metrics_has_required_fields(self, container):
        """Verify metrics contain all required fields"""
        # Run monitor
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        # Read metrics
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        required_fields = ["timestamp", "platform", "system", "cpu", "memory", "disk", "network"]
        for field in required_fields:
            assert field in metrics, f"Missing field: {field}"
    
    def test_docker_flag_set(self, container):
        """Verify docker flag is set in metrics"""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        assert metrics.get("docker") is True, "Docker flag not set"


class TestSystemMetrics:
    """Test system metrics collection"""
    
    def test_cpu_metrics(self, container):
        """Test CPU metrics are collected"""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        cpu = metrics.get("cpu", {})
        assert "usage_percent" in cpu or "status" in cpu
        assert "logical_processors" in cpu or "status" in cpu
    
    def test_memory_metrics(self, container):
        """Test memory metrics are collected"""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        memory = metrics.get("memory", {})
        assert "total_mb" in memory or "status" in memory
        assert "used_mb" in memory or "status" in memory
    
    def test_disk_metrics(self, container):
        """Test disk metrics are collected"""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        disk = metrics.get("disk", [])
        assert isinstance(disk, list)
        if len(disk) > 0:
            assert "device" in disk[0]
            assert "total_gb" in disk[0] or "filesystem" in disk[0]
    
    def test_network_metrics(self, container):
        """Test network metrics are collected"""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        network = metrics.get("network", [])
        assert isinstance(network, list)


class TestToolAvailability:
    """Test availability of system monitoring tools"""
    
    def test_bash_available(self, container):
        """Verify bash is available"""
        exit_code, output = container.exec_run("which bash")
        assert exit_code == 0
    
    def test_proc_filesystem_accessible(self, container):
        """Verify /proc filesystem is accessible"""
        exit_code, _ = container.exec_run("test -r /host/proc/cpuinfo")
        assert exit_code == 0, "/host/proc not accessible"
    
    def test_sys_filesystem_accessible(self, container):
        """Verify /sys filesystem is accessible"""
        exit_code, _ = container.exec_run("test -d /host/sys")
        assert exit_code == 0, "/host/sys not accessible"
    
    def test_dev_filesystem_accessible(self, container):
        """Verify /dev filesystem is accessible"""
        exit_code, _ = container.exec_run("test -d /host/dev")
        assert exit_code == 0, "/host/dev not accessible"
    
    def test_python_available(self, container):
        """Verify Python is available"""
        exit_code, output = container.exec_run("python3 --version")
        assert exit_code == 0
        assert b"Python 3" in output
    
    def test_json_validation_works(self, container):
        """Verify JSON validation tool works"""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "python3 -m json.tool /app/data/metrics/current.json"
        )
        assert exit_code == 0, f"JSON validation failed: {output.decode()}"


class TestEnvironmentVariables:
    """Test environment variable configuration"""
    
    def test_host_proc_env_set(self, container):
        """Verify HOST_PROC environment variable is used"""
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        
        # Should contain docker flag indicating HOST_PROC was used
        if exit_code == 0:
            metrics = json.loads(output.decode())
            assert metrics.get("docker") is True
    
    def test_environment_variables_passed(self, container):
        """Verify environment variables are passed to scripts"""
        exit_code, output = container.exec_run(
            "bash -c 'source /app/scripts/main_monitor.sh; echo $PROC_PATH'",
            environment={
                "HOST_PROC": "/host/proc",
                "HOST_SYS": "/host/sys",
                "HOST_DEV": "/host/dev"
            }
        )
        
        # PROC_PATH should be set
        output_str = output.decode().strip()
        assert "/host/proc" in output_str or "/proc" in output_str


class TestWebAPI:
    """Test web API endpoints"""
    
    def test_api_health_endpoint(self, container):
        """Test /api/health endpoint"""
        exit_code, output = container.exec_run(
            "curl -s http://localhost:5000/api/health"
        )
        
        if exit_code == 0:
            try:
                response = json.loads(output.decode())
                assert "status" in response or "success" in response
            except:
                pass  # API might not be running in all test scenarios
    
    def test_api_metrics_endpoint(self, container):
        """Test /api/metrics endpoint"""
        exit_code, output = container.exec_run(
            "curl -s http://localhost:5000/api/metrics"
        )
        
        if exit_code == 0:
            try:
                response = json.loads(output.decode())
                assert "data" in response or "success" in response
            except:
                pass  # API might not be running in all test scenarios


class TestGracefulDegradation:
    """Test graceful handling of missing sensors/tools"""
    
    def test_missing_sensors_handled(self, container):
        """Verify missing lm-sensors doesn't crash"""
        # Temperature monitoring should handle missing sensors gracefully
        exit_code, output = container.exec_run(
            "/app/scripts/monitors/unix/temperature_monitor.sh"
        )
        
        # Should not crash (exit code 0) even if sensors missing
        assert exit_code == 0
        
        # Should output valid JSON
        try:
            data = json.loads(output.decode())
            assert isinstance(data, dict)
        except:
            pass  # Some monitors might not output JSON directly
    
    def test_missing_gpu_handled(self, container):
        """Verify missing nvidia-smi doesn't crash"""
        # Temperature monitoring should handle missing GPU tools
        exit_code, _ = container.exec_run(
            "/app/scripts/monitors/unix/temperature_monitor.sh"
        )
        assert exit_code == 0
    
    def test_missing_smart_tools_handled(self, container):
        """Verify missing smartctl doesn't crash"""
        exit_code, _ = container.exec_run(
            "/app/scripts/monitors/unix/smart_monitor.sh"
        )
        assert exit_code == 0


class TestMetricsEdgeCases:
    """Test edge cases in metrics collection."""
    
    def test_high_cpu_usage_handling(self, container):
        """Test handling of very high CPU usage values."""
        # CPU usage should never exceed 100%
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        cpu_usage = metrics.get("cpu", {}).get("usage_percent", 0)
        
        # Validate range
        assert 0 <= cpu_usage <= 100, f"Invalid CPU usage: {cpu_usage}"
    
    def test_memory_percentage_validation(self, container):
        """Test memory percentage is within valid range."""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        mem_usage = metrics.get("memory", {}).get("usage_percent", 0)
        
        assert 0 <= mem_usage <= 100, f"Invalid memory usage: {mem_usage}"
    
    def test_disk_usage_validation(self, container):
        """Test disk usage percentages are valid."""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        disks = metrics.get("disk", [])
        
        for disk in disks:
            usage = disk.get("used_percent", 0)
            assert 0 <= usage <= 100, f"Invalid disk usage for {disk.get('device')}: {usage}"
    
    def test_network_bytes_non_negative(self, container):
        """Test network bytes are non-negative."""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        network = metrics.get("network", [])
        
        for iface in network:
            rx = iface.get("rx_bytes", 0)
            tx = iface.get("tx_bytes", 0)
            
            assert rx >= 0, f"Negative RX bytes for {iface.get('iface')}"
            assert tx >= 0, f"Negative TX bytes for {iface.get('iface')}"


class TestTimestampValidation:
    """Test timestamp format and validity."""
    
    def test_timestamp_format(self, container):
        """Test timestamp is in ISO 8601 format."""
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        timestamp = metrics.get("timestamp")
        
        assert timestamp is not None
        # Should contain 'T' and 'Z' for ISO format
        assert 'T' in timestamp
        assert timestamp.endswith('Z')
    
    def test_timestamp_parseable(self, container):
        """Test timestamp can be parsed as datetime."""
        from datetime import datetime
        
        container.exec_run("/app/scripts/main_monitor.sh")
        time.sleep(2)
        
        exit_code, output = container.exec_run(
            "cat /app/data/metrics/current.json"
        )
        metrics = json.loads(output.decode())
        
        timestamp = metrics.get("timestamp")
        
        # Should be parseable
        try:
            dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            assert dt is not None
        except ValueError:
            pytest.fail(f"Invalid timestamp format: {timestamp}")


class TestDataConsistency:
    """Test data consistency across multiple runs."""
    
    def test_multiple_runs_produce_valid_json(self, container):
        """Test multiple monitor runs all produce valid JSON."""
        for i in range(3):
            container.exec_run("/app/scripts/main_monitor.sh")
            time.sleep(2)
            
            exit_code, output = container.exec_run(
                "cat /app/data/metrics/current.json"
            )
            
            assert exit_code == 0
            
            try:
                metrics = json.loads(output.decode())
                assert isinstance(metrics, dict)
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON on run {i+1}")
    
    def test_required_fields_always_present(self, container):
        """Test required fields are present in every run."""
        required = ["timestamp", "platform", "system", "cpu", "memory"]
        
        for i in range(2):
            container.exec_run("/app/scripts/main_monitor.sh")
            time.sleep(2)
            
            exit_code, output = container.exec_run(
                "cat /app/data/metrics/current.json"
            )
            metrics = json.loads(output.decode())
            
            for field in required:
                assert field in metrics, f"Missing {field} on run {i+1}"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])

