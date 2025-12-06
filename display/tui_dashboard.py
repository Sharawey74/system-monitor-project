"""
Terminal UI Dashboard Module

Provides a live terminal dashboard for system monitoring using the rich library.
Displays CPU, memory, disk, network, temperature, and alert information.
"""

import time
import logging
from pathlib import Path
from typing import Dict, Any, List, Optional
from datetime import datetime

from rich.console import Console, Group
from rich.layout import Layout
from rich.panel import Panel
from rich.table import Table
from rich.progress import Progress, BarColumn, TextColumn
from rich.text import Text
from rich.live import Live
from rich.align import Align

from core.metrics_collector import load_current_metrics
from core.alert_manager import load_alerts

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    filename='data/logs/dashboard.log'
)
logger = logging.getLogger(__name__)

# Constants
REFRESH_RATE = 2  # seconds
COLOR_THRESHOLD_LOW = 60
COLOR_THRESHOLD_HIGH = 80


class SystemDashboard:
    """
    Terminal UI dashboard for system monitoring.
    
    Displays live system metrics including CPU, memory, disk, network,
    temperature, and alerts with automatic refresh every 2 seconds.
    """
    
    def __init__(self, metrics_path: str, alerts_path: str):
        """
        Initialize dashboard with data file paths.
        
        Args:
            metrics_path: Path to current.json metrics file
            alerts_path: Path to alerts.json alerts file
        """
        self.metrics_path = Path(metrics_path)
        self.alerts_path = Path(alerts_path)
        self.console = Console()
        logger.info(f"Dashboard initialized: metrics={metrics_path}, alerts={alerts_path}")
    
    def create_layout(self) -> Layout:
        """
        Create the dashboard layout structure.
        
        Returns:
            Layout: Rich layout with header, body, and footer sections
        """
        layout = Layout()
        
        # Split into header, body, footer
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body"),
            Layout(name="footer", size=4)
        )
        
        # Split body into left and right columns
        layout["body"].split_row(
            Layout(name="left"),
            Layout(name="right")
        )
        
        # Split left column into CPU and disk
        layout["left"].split_column(
            Layout(name="cpu", size=13),
            Layout(name="disk", size=12)
        )
        
        # Split right column into memory, GPU, and network
        layout["right"].split_column(
            Layout(name="memory", size=9),
            Layout(name="gpu", size=10),
            Layout(name="network")
        )
        
        return layout
    
    def generate_header_panel(self, metrics: Dict[str, Any]) -> Panel:
        """
        Generate header panel with system info and timestamp.
        
        Args:
            metrics: System metrics dictionary
            
        Returns:
            Panel: Header panel
        """
        hostname = metrics.get('system', {}).get('hostname', 'unknown')
        platform = metrics.get('platform', 'unknown')
        timestamp = metrics.get('timestamp', 'N/A')
        
        header_text = Text()
        header_text.append("SYSTEM MONITOR DASHBOARD", style="bold cyan")
        header_text.append(f" - {hostname} ({platform}) - ", style="white")
        header_text.append(timestamp, style="yellow")
        
        return Panel(
            Align.center(header_text),
            style="bold white on blue"
        )
    
    def generate_cpu_panel(self, metrics: Dict[str, Any]) -> Panel:
        """
        Generate CPU metrics panel.
        
        Args:
            metrics: System metrics dictionary
            
        Returns:
            Panel: CPU metrics panel with usage, load, and temperature
        """
        cpu = metrics.get('cpu', {})
        temp = metrics.get('temperature', {})
        
        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Label", style="cyan")
        table.add_column("Value")
        
        # CPU Usage
        usage = cpu.get('usage_percent')
        if usage is not None:
            usage_color = self._get_color_for_percentage(usage)
            usage_bar = self._create_progress_bar(usage, usage_color)
            table.add_row("Usage:", usage_bar)
        else:
            table.add_row("Usage:", "[dim]N/A[/dim]")
        
        # Load Average
        load_avg = cpu.get('load_average')
        if load_avg and isinstance(load_avg, list) and len(load_avg) >= 3:
            load_text = f"{load_avg[0]:.2f}, {load_avg[1]:.2f}, {load_avg[2]:.2f}"
            table.add_row("Load (1/5/15):", load_text)
        else:
            table.add_row("Load:", "[dim]N/A[/dim]")
        
        # CPU Info
        cores = cpu.get('cores')
        vendor = cpu.get('vendor', 'N/A')
        if cores:
            table.add_row("Cores:", f"{cores} ({vendor})")
        
        model = cpu.get('model', 'N/A')
        if model and model != 'N/A':
            # Show shortened model name (first 40 chars)
            model_short = model[:40] + "..." if len(model) > 40 else model
            table.add_row("Model:", f"[dim]{model_short}[/dim]")
        
        # CPU Temperature
        cpu_temp = temp.get('cpu_temp')
        if cpu_temp is not None and cpu_temp > 0:
            temp_color = self._get_color_for_temperature(cpu_temp)
            table.add_row("Temp:", f"[{temp_color}]{cpu_temp:.1f}°C[/{temp_color}]")
        else:
            table.add_row("Temp:", "[dim]N/A[/dim]")
        
        return Panel(
            table,
            title="[bold]CPU",
            border_style="blue"
        )
    
    def generate_memory_panel(self, metrics: Dict[str, Any]) -> Panel:
        """
        Generate memory metrics panel.
        
        Args:
            metrics: System metrics dictionary
            
        Returns:
            Panel: Memory metrics panel
        """
        memory = metrics.get('memory', {})
        
        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Label", style="cyan")
        table.add_column("Value")
        
        used_mb = memory.get('used_mb')
        total_mb = memory.get('total_mb')
        usage_percent = memory.get('usage_percent')
        
        if used_mb is not None and total_mb is not None:
            used_gb = used_mb / 1024
            total_gb = total_mb / 1024
            table.add_row("Used:", f"{used_gb:.2f} GB / {total_gb:.2f} GB")
        else:
            table.add_row("Used:", "[dim]N/A[/dim]")
        
        if usage_percent is not None:
            usage_color = self._get_color_for_percentage(usage_percent)
            usage_bar = self._create_progress_bar(usage_percent, usage_color)
            table.add_row("Usage:", usage_bar)
        else:
            table.add_row("Usage:", "[dim]N/A[/dim]")
        
        free_mb = memory.get('free_mb')
        if free_mb is not None:
            free_gb = free_mb / 1024
            table.add_row("Free:", f"{free_gb:.2f} GB")
        
        return Panel(
            table,
            title="[bold]MEMORY",
            border_style="green"
        )
    
    def generate_disk_panel(self, metrics: Dict[str, Any]) -> Panel:
        """
        Generate disk metrics panel.
        
        Args:
            metrics: System metrics dictionary
            
        Returns:
            Panel: Disk metrics panel showing all disks
        """
        disks = metrics.get('disk', [])
        
        if not disks:
            return Panel(
                "[dim]No disk information available[/dim]",
                title="[bold]DISK",
                border_style="magenta"
            )
        
        table = Table(show_header=True, box=None, padding=(0, 1), show_edge=False)
        table.add_column("Device", style="cyan", width=7, no_wrap=True)
        table.add_column("Usage", justify="right", width=7)
        table.add_column("Used/Total", justify="right", width=17)
        table.add_column("Bar", width=18)
        
        # Show all disks (up to 10 to avoid clutter)
        for disk in disks[:10]:
            device = disk.get('device', 'N/A')
            usage_percent = disk.get('usage_percent')
            used_gb = disk.get('used_gb')
            total_gb = disk.get('total_gb')
            
            if usage_percent is not None:
                usage_color = self._get_color_for_percentage(usage_percent)
                usage_text = f"[{usage_color}]{usage_percent:.1f}%[/{usage_color}]"
                progress_bar = self._create_mini_progress_bar(usage_percent, usage_color)
            else:
                usage_text = "[dim]N/A[/dim]"
                progress_bar = "[dim]—[/dim]"
            
            if used_gb is not None and total_gb is not None:
                size_text = f"{used_gb:.1f}/{total_gb:.1f} GB"
            else:
                size_text = "[dim]N/A[/dim]"
            
            table.add_row(device, usage_text, size_text, progress_bar)
        
        return Panel(
            table,
            title="[bold]DISK",
            border_style="magenta"
        )
    
    def generate_network_panel(self, metrics: Dict[str, Any]) -> Panel:
        """
        Generate network metrics panel.
        
        Args:
            metrics: System metrics dictionary
            
        Returns:
            Panel: Network metrics panel
        """
        network = metrics.get('network', {})
        
        # Summary table at top
        summary = Table(show_header=False, box=None, padding=(0, 1), show_edge=False)
        summary.add_column("Label", style="cyan", width=10)
        summary.add_column("Value")
        
        total_rx = network.get('total_rx_bytes', 0)
        total_tx = network.get('total_tx_bytes', 0)
        
        # Convert to appropriate units
        rx_formatted = self._format_bytes(total_rx)
        tx_formatted = self._format_bytes(total_tx)
        
        summary.add_row("Total RX:", f"[green]{rx_formatted}[/green]")
        summary.add_row("Total TX:", f"[yellow]{tx_formatted}[/yellow]")
        
        # Interfaces table
        interfaces = network.get('interfaces', [])
        active_interfaces = sorted(
            [i for i in interfaces if i.get('rx_bytes', 0) > 0 or i.get('tx_bytes', 0) > 0],
            key=lambda x: x.get('rx_bytes', 0) + x.get('tx_bytes', 0),
            reverse=True
        )[:3]
        
        if active_interfaces:
            iface_table = Table(show_header=True, box=None, padding=(0, 1), show_edge=False)
            iface_table.add_column("Interface", style="dim cyan", width=15, no_wrap=True)
            iface_table.add_column("RX", justify="right", style="green", width=10)
            iface_table.add_column("TX", justify="right", style="yellow", width=10)
            
            for iface in active_interfaces:
                iface_name = iface.get('iface', 'Unknown')
                # Shorten interface name if too long
                if len(iface_name) > 15:
                    iface_name = iface_name[:12] + "..."
                rx = self._format_bytes(iface.get('rx_bytes', 0))
                tx = self._format_bytes(iface.get('tx_bytes', 0))
                iface_table.add_row(iface_name, rx, tx)
            
            # Combine both tables
            from rich.console import Group
            table = Group(summary, Text(""), iface_table)
        else:
            table = summary
        
        return Panel(
            table,
            title="[bold]NETWORK",
            border_style="cyan"
        )
    
    def generate_temperature_panel(self, metrics: Dict[str, Any]) -> Panel:
        """
        Generate CPU temperature panel.
        
        Args:
            metrics: System metrics dictionary
            
        Returns:
            Panel: CPU Temperature panel
        """
        temp = metrics.get('temperature', {})
        
        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Label", style="cyan")
        table.add_column("Value")
        
        # CPU Temperature
        cpu_temp = temp.get('cpu_temp')
        cpu_vendor = temp.get('cpu_vendor', 'N/A')
        if cpu_temp is not None and cpu_temp > 0:
            temp_color = self._get_color_for_temperature(cpu_temp)
            table.add_row("CPU:", f"[{temp_color}]{cpu_temp:.1f}°C[/{temp_color}] [dim]({cpu_vendor})[/dim]")
        else:
            table.add_row("CPU:", f"[dim]N/A ({cpu_vendor})[/dim]")
        
        return Panel(
            table,
            title="[bold]TEMPERATURE",
            border_style="red"
        )
    
    def generate_gpu_panel(self, metrics: Dict[str, Any]) -> Panel:
        """
        Generate GPU information panel with temperature, model, and VRAM.
        
        Args:
            metrics: System metrics dictionary
            
        Returns:
            Panel: GPU metrics panel
        """
        temp = metrics.get('temperature', {})
        gpus = temp.get('gpus', [])
        
        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Label", style="cyan")
        table.add_column("Value")
        
        # Find the primary GPU (prefer dedicated, then first available)
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
            gpu_temp = primary_gpu.get('temperature_celsius', 0)
            gpu_vendor = primary_gpu.get('vendor', 'N/A')
            gpu_model = primary_gpu.get('model', 'N/A')
            gpu_type = primary_gpu.get('type', 'N/A')
            vram_total = primary_gpu.get('vram_total_mb', 0)
            vram_used = primary_gpu.get('vram_used_mb', 0)
            vram_free = primary_gpu.get('vram_free_mb', 0)
            
            # GPU Temperature
            if gpu_temp is not None and gpu_temp > 0:
                temp_color = self._get_color_for_temperature(gpu_temp)
                table.add_row("Temp:", f"[{temp_color}]{gpu_temp:.1f}°C[/{temp_color}]")
            else:
                table.add_row("Temp:", f"[dim]N/A[/dim]")
            
            # GPU Vendor
            table.add_row("Vendor:", f"[white]{gpu_vendor}[/white]")
            
            # GPU Model
            if gpu_model != 'N/A' and gpu_model != 'Unknown':
                # Truncate long model names
                model_display = gpu_model if len(gpu_model) <= 30 else gpu_model[:27] + "..."
                table.add_row("Model:", f"[white]{model_display}[/white]")
            
            # GPU Type
            if gpu_type != 'N/A' and gpu_type != 'Unknown':
                table.add_row("Type:", f"[white]{gpu_type}[/white]")
            
            # VRAM Information
            if vram_total > 0:
                vram_gb_total = vram_total / 1024
                vram_gb_used = vram_used / 1024
                vram_usage_pct = (vram_used / vram_total * 100) if vram_total > 0 else 0
                vram_color = self._get_color_for_percentage(vram_usage_pct)
                vram_bar = self._create_mini_progress_bar(vram_usage_pct, vram_color)
                
                table.add_row("", "")  # Empty row for spacing
                table.add_row("VRAM:", f"{vram_gb_used:.1f} / {vram_gb_total:.1f} GB")
                table.add_row("Usage:", f"[{vram_color}]{vram_usage_pct:.1f}%[/{vram_color}] {vram_bar}")
            
            # Show GPU count if multiple
            if len(gpus) > 1:
                table.add_row("", "")
                table.add_row("GPUs:", f"[dim]{len(gpus)} detected[/dim]")
        else:
            # No GPU data available
            table.add_row("Temp:", f"[dim]N/A[/dim]")
            table.add_row("Vendor:", f"[dim]N/A[/dim]")
        
        return Panel(
            table,
            title="[bold cyan]GPU[/]",
            border_style="cyan"
        )
    
    def generate_alerts_panel(self, alerts: List[Dict[str, Any]]) -> Panel:
        """
        Generate alerts panel as footer.
        
        Args:
            alerts: List of alert dictionaries
            
        Returns:
            Panel: Alerts panel with color-coded alerts
        """
        if not alerts:
            return Panel(
                Align.center("[dim]No alerts[/dim]"),
                title="[bold]ALERTS (0)",
                border_style="dim white"
            )
        
        table = Table(show_header=False, box=None, padding=(0, 1), show_edge=False)
        table.add_column("Level", width=8)
        table.add_column("Message", overflow="ellipsis")
        
        # Show up to 3 most recent alerts for compact display
        for alert in alerts[:3]:
            level = alert.get('level', 'info')
            message = alert.get('message', 'Unknown alert')
            
            # Get icon and color based on level
            if level == 'critical':
                icon = "🔴"
                color = "red"
            elif level == 'warning':
                icon = "⚠️"
                color = "yellow"
            else:
                icon = "ℹ️"
                color = "blue"
            
            level_text = f"{icon}[{color}]{level.upper()}[/{color}]"
            table.add_row(level_text, message)
        
        alert_count = len(alerts)
        return Panel(
            table,
            title=f"[bold]ALERTS ({alert_count})",
            border_style="red" if any(a.get('level') == 'critical' for a in alerts) else "yellow"
        )
    
    def generate_dashboard(self) -> Layout:
        """
        Generate the complete dashboard with current data.
        
        Returns:
            Layout: Complete dashboard layout
        """
        # Load data
        metrics = load_current_metrics(str(self.metrics_path))
        alerts = load_alerts(str(self.alerts_path))
        
        # Create layout
        layout = self.create_layout()
        
        # Populate layout
        layout["header"].update(self.generate_header_panel(metrics))
        layout["cpu"].update(self.generate_cpu_panel(metrics))
        layout["memory"].update(self.generate_memory_panel(metrics))
        layout["gpu"].update(self.generate_gpu_panel(metrics))
        layout["disk"].update(self.generate_disk_panel(metrics))
        layout["network"].update(self.generate_network_panel(metrics))
        layout["footer"].update(self.generate_alerts_panel(alerts))
        
        return layout
    
    def run(self):
        """
        Start the live dashboard with 2-second refresh.
        
        Runs until user presses Ctrl+C.
        """
        logger.info("Starting dashboard...")
        
        try:
            with Live(
                self.generate_dashboard(),
                console=self.console,
                refresh_per_second=1,
                screen=False
            ) as live:
                while True:
                    time.sleep(REFRESH_RATE)
                    live.update(self.generate_dashboard())
                    
        except KeyboardInterrupt:
            self.console.print("\n[yellow]Dashboard stopped by user[/yellow]")
            logger.info("Dashboard stopped by user (Ctrl+C)")
            
        except Exception as e:
            self.console.print(f"\n[red]Error: {e}[/red]")
            logger.error(f"Dashboard error: {e}", exc_info=True)
            raise
    
    # Helper methods
    
    def _get_color_for_percentage(self, percentage: float) -> str:
        """Get color based on percentage thresholds."""
        if percentage < COLOR_THRESHOLD_LOW:
            return "green"
        elif percentage < COLOR_THRESHOLD_HIGH:
            return "yellow"
        else:
            return "red"
    
    def _get_color_for_temperature(self, temp: float) -> str:
        """Get color based on temperature thresholds."""
        if temp < 60:
            return "green"
        elif temp < 80:
            return "yellow"
        else:
            return "red"
    
    def _create_progress_bar(self, percentage: float, color: str) -> str:
        """Create a text-based progress bar."""
        filled = int(percentage / 10)
        bar = "█" * filled + "░" * (10 - filled)
        return f"[{color}]{percentage:.1f}% [{bar}][/{color}]"
    
    def _create_mini_progress_bar(self, percentage: float, color: str) -> str:
        """Create a smaller progress bar for tables."""
        filled = int(percentage / 10)
        bar = "█" * filled + "░" * (10 - filled)
        return f"[{color}]{bar}[/{color}]"
    
    def _format_bytes(self, bytes_value: int) -> str:
        """Format bytes into human-readable format."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_value < 1024:
                return f"{bytes_value:.2f} {unit}"
            bytes_value /= 1024
        return f"{bytes_value:.2f} PB"
