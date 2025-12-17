#!/usr/bin/env python3
"""Report generation module for system monitoring"""

from pathlib import Path
from datetime import datetime
from jinja2 import Environment, FileSystemLoader, select_autoescape
import os


class ReportGenerator:
    """Generate HTML and Markdown reports from metrics and alerts"""
    
    def __init__(self, metrics_file, alerts_file, reports_dir):
        """Initialize report generator
        
        Args:
            metrics_file: Path to current.json metrics file
            alerts_file: Path to alerts.json file
            reports_dir: Directory to save generated reports
        """
        self.metrics_file = Path(metrics_file)
        self.alerts_file = Path(alerts_file)
        self.reports_dir = Path(reports_dir)
        
        # Create report directories
        self.html_dir = self.reports_dir / 'html'
        self.markdown_dir = self.reports_dir / 'markdown'
        self.html_dir.mkdir(parents=True, exist_ok=True)
        self.markdown_dir.mkdir(parents=True, exist_ok=True)
        
        # Setup Jinja2 environment
        template_dir = Path(__file__).parent.parent / 'templates'
        self.env = Environment(
            loader=FileSystemLoader(str(template_dir)),
            autoescape=select_autoescape(['html', 'xml'])
        )
        
        # Add custom filters
        self.env.filters['format_bytes'] = self._format_bytes
        self.env.filters['format_timestamp'] = self._format_timestamp
        self.env.filters['percentage_color'] = self._percentage_color
        self.env.filters['alert_level_badge'] = self._alert_level_badge
    
    def _format_bytes(self, bytes_value, unit='auto'):
        """Format bytes to human readable format"""
        try:
            bytes_value = float(bytes_value)
            if unit == 'auto':
                for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
                    if bytes_value < 1024.0:
                        return f"{bytes_value:.2f} {unit}"
                    bytes_value /= 1024.0
            return f"{bytes_value:.2f} {unit}"
        except (ValueError, TypeError):
            return "N/A"
    
    def _format_timestamp(self, timestamp_str):
        """Format ISO timestamp to readable format"""
        try:
            dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            return dt.strftime('%Y-%m-%d %H:%M:%S UTC')
        except:
            return timestamp_str
    
    def _percentage_color(self, percentage):
        """Get color class based on percentage"""
        try:
            pct = float(percentage)
            if pct >= 80:
                return 'danger'
            elif pct >= 60:
                return 'warning'
            else:
                return 'success'
        except (ValueError, TypeError):
            return 'secondary'
    
    def _alert_level_badge(self, level):
        """Get Bootstrap badge class for alert level"""
        level_map = {
            'critical': 'danger',
            'warning': 'warning',
            'info': 'info'
        }
        return level_map.get(level.lower(), 'secondary')
    
    def generate_report(self, legacy_metrics, native_metrics, alerts):
        """Generate both HTML and Markdown reports
        
        Args:
            legacy_metrics: Dictionary of legacy (WSL) metrics
            native_metrics: Dictionary of native (Windows) metrics
            alerts: List of alert dictionaries
            
        Returns:
            Tuple of (html_path, markdown_path)
        """
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # Prepare report data
        report_data = {
            'generated_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'legacy': legacy_metrics,
            'native': native_metrics,
            'alerts': alerts,
            'alert_counts': self._count_alerts_by_level(alerts),
            'summary_legacy': self._generate_summary(legacy_metrics),
            'summary_native': self._generate_summary(native_metrics)
        }
        
        # Generate HTML report
        html_template = self.env.get_template('report_template.html')
        html_content = html_template.render(**report_data)
        html_filename = f'report_{timestamp}.html'
        html_path = self.html_dir / html_filename
        html_path.write_text(html_content, encoding='utf-8')
        
        # Generate Markdown report
        md_template = self.env.get_template('report_template.md')
        md_content = md_template.render(**report_data)
        md_filename = f'report_{timestamp}.md'
        md_path = self.markdown_dir / md_filename
        md_path.write_text(md_content, encoding='utf-8')
        
        return html_path, md_path
    
    def _count_alerts_by_level(self, alerts):
        """Count alerts by severity level"""
        counts = {'critical': 0, 'warning': 0, 'info': 0}
        # Handle both list of dicts and empty cases
        if not alerts:
            return counts
        if not isinstance(alerts, list):
            alerts = []
        for alert in alerts:
            if isinstance(alert, dict):
                level = alert.get('level', 'info').lower()
                if level in counts:
                    counts[level] += 1
        return counts
    
    def _generate_summary(self, metrics):
        """Generate summary statistics from metrics"""
        if not metrics:
            return {}
            
        summary = {
            'cpu_usage': 0,
            'memory_usage': 0,
            'disk_count': 0,
            'network_interfaces': 0,
            'gpu_count': 0,
            'temperature_max': 0
        }
        
        # Get CPU usage
        cpu = metrics.get('cpu', {})
        if isinstance(cpu, dict):
            summary['cpu_usage'] = cpu.get('usage_percent', 0)
        
        # Calculate memory usage percentage
        memory = metrics.get('memory', {})
        if isinstance(memory, dict) and memory.get('total_mb') and memory.get('used_mb'):
            summary['memory_usage'] = round(
                (memory['used_mb'] / memory['total_mb']) * 100, 1
            )
        
        # Count disks
        disk = metrics.get('disk', [])
        if isinstance(disk, list):
            summary['disk_count'] = len(disk)
        
        # Count network interfaces (network can be list or dict)
        network = metrics.get('network', [])
        if isinstance(network, list):
            summary['network_interfaces'] = len(network)
        elif isinstance(network, dict):
            summary['network_interfaces'] = len(network.get('interfaces', []))
        else:
            summary['network_interfaces'] = 0
        
        # Count GPUs and get max temperature
        temp = metrics.get('temperature', {})
        if isinstance(temp, dict):
            gpus = temp.get('gpus', [])
            if isinstance(gpus, list):
                summary['gpu_count'] = len(gpus)
            
            # Get maximum temperature
            temps = []
            cpu_temp = temp.get('cpu_celsius')
            if cpu_temp and cpu_temp > 0:
                temps.append(cpu_temp)
            
            if isinstance(gpus, list):
                for gpu in gpus:
                    if isinstance(gpu, dict):
                        gpu_temp = gpu.get('temperature_celsius')
                        if gpu_temp and gpu_temp > 0:
                            temps.append(gpu_temp)
            
            summary['temperature_max'] = max(temps) if temps else 0
        
        return summary
    
    def list_reports(self):
        """List all generated reports"""
        reports = []
        
        # List HTML reports
        for html_file in self.html_dir.glob('report_*.html'):
            stat = html_file.stat()
            reports.append({
                'type': 'html',
                'filename': html_file.name,
                'size': stat.st_size,
                'created': datetime.fromtimestamp(stat.st_ctime).isoformat(),
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'path': str(html_file.relative_to(self.reports_dir.parent))
            })
        
        # List Markdown reports
        for md_file in self.markdown_dir.glob('report_*.md'):
            stat = md_file.stat()
            reports.append({
                'type': 'markdown',
                'filename': md_file.name,
                'size': stat.st_size,
                'created': datetime.fromtimestamp(stat.st_ctime).isoformat(),
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'path': str(md_file.relative_to(self.reports_dir.parent))
            })
        
        # Sort by creation time (newest first)
        reports.sort(key=lambda r: r['created'], reverse=True)
        
        return reports
