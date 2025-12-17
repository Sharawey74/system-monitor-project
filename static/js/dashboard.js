/**
 * Observability Dashboard Logic
 * Symmetric Host (Windows) + Guest (WSL) Monitoring
 */

// State for Rate Calculations
let previousState = {
    win: { timestamp: null, net: {}, rx: 0, tx: 0 },
    wsl: { timestamp: null, net: {}, rx: 0, tx: 0 }
};

document.addEventListener('DOMContentLoaded', () => {
    fetchData();
    setInterval(fetchData, 2000); // 2s polling
});

async function fetchData() {
    try {
        const response = await fetch('/api/metrics/dual');
        const data = await response.json();
        if (data.success) {
            console.log('Fetched data:', {
                win: data.native ? 'Available' : 'Missing',
                wsl: data.legacy ? 'Available' : 'Missing',
                winNetwork: data.native?.network?.length || 0,
                wslNetwork: data.legacy?.network?.length || 0
            });
            updateObservabilityGrid(data.native, data.legacy);
        } else {
            console.error('API returned success=false:', data);
        }
    } catch (e) {
        console.error("Fetch failed", e);
    }
}

// Instant Refresh Button Handler
async function instantRefresh() {
    try {
        const btn = event.target.closest('button');
        const originalContent = btn.innerHTML;

        // Show loading state
        btn.disabled = true;
        btn.innerHTML = "<i class='bx bx-loader-alt bx-spin'></i> Refreshing...";

        // Call backend to trigger scripts
        console.log("Triggering instant refresh...");
        const response = await fetch('/api/refresh', { method: 'POST' });
        const result = await response.json();

        if (result.success) {
            console.log("Refresh successful:", result);
            // Fetch fresh data immediately
            await fetchData();

            // Show success briefly
            btn.innerHTML = "<i class='bx bx-check'></i> Done!";
            setTimeout(() => {
                btn.innerHTML = originalContent;
                btn.disabled = false;
            }, 1000);
        } else {
            console.error("Refresh failed:", result);
            alert("Refresh failed: " + (result.error || "Unknown error"));
            btn.innerHTML = originalContent;
            btn.disabled = false;
        }
    } catch (e) {
        console.error("Instant refresh error:", e);
        const btn = event.target.closest('button');
        if (btn) btn.disabled = false;
        alert("Error triggering refresh");
    }
}

function updateObservabilityGrid(winData, wslData) {
    if (winData) renderHostColumn(winData);
    if (wslData) renderGuestColumn(wslData);
}

// 🧮 NETWORK RATE VALIDATION & CALCULATION (PER INTERFACE)
function calculateNetworkRates(key, currentNets) {
    const now = new Date();
    const prev = previousState[key];

    let globalRxRate = 0;
    let globalTxRate = 0;
    let interfaceRates = {};

    // Map current for easy lookup & Global Sum
    const currentMap = {};
    let totalRx = 0;
    let totalTx = 0;

    if (currentNets) {
        currentNets.forEach(n => {
            currentMap[n.iface] = n;
            totalRx += n.rx_bytes;
            totalTx += n.tx_bytes;
        });
    }

    console.log(`[${key}] Network calc:`, {
        totalRx: (totalRx / 1024 / 1024).toFixed(2) + ' MB',
        totalTx: (totalTx / 1024 / 1024).toFixed(2) + ' MB',
        hasPrev: !!prev.timestamp,
        interfaces: Object.keys(currentMap).join(', ')
    });

    // 1. Persistence Check: If global match, hold stats
    if (prev.timestamp && prev.rx === totalRx && prev.tx === totalTx) {
        return {
            globalRxRate: prev.lastGlobalRx || 0,
            globalTxRate: prev.lastGlobalTx || 0,
            interfaceRates: prev.lastInterfaceRates || {}
        };
    }

    if (prev.timestamp) {
        const timeDelta = (now - prev.timestamp) / 1000;

        console.log(`[${key}] Time delta: ${timeDelta.toFixed(2)}s`);

        if (timeDelta > 0 && timeDelta < 20) {
            // Global Rate
            const gRxDiff = totalRx - prev.rx;
            const gTxDiff = totalTx - prev.tx;
            if (gRxDiff >= 0) globalRxRate = gRxDiff / timeDelta;
            if (gTxDiff >= 0) globalTxRate = gTxDiff / timeDelta;

            console.log(`[${key}] Rates calculated:`, {
                rxRate: formatRate(globalRxRate),
                txRate: formatRate(globalTxRate),
                rxDiff: (gRxDiff / 1024).toFixed(2) + ' KB',
                txDiff: (gTxDiff / 1024).toFixed(2) + ' KB'
            });

            // Per-Interface Rate
            if (prev.net) {
                for (const [iface, n] of Object.entries(currentMap)) {
                    const old = prev.net[iface];
                    if (old) {
                        const rxDiff = n.rx_bytes - old.rx_bytes;
                        const txDiff = n.tx_bytes - old.tx_bytes;
                        interfaceRates[iface] = {
                            rx: rxDiff >= 0 ? rxDiff / timeDelta : 0,
                            tx: txDiff >= 0 ? txDiff / timeDelta : 0
                        };
                    }
                }
            }
        }
    }

    // Update State
    previousState[key] = {
        timestamp: now,
        rx: totalRx,
        tx: totalTx,
        net: currentMap,
        lastGlobalRx: globalRxRate,
        lastGlobalTx: globalTxRate,
        lastInterfaceRates: interfaceRates
    };

    return { globalRxRate, globalTxRate, interfaceRates };
}

// ============================================
// WINDOWS HOST RENDERER
// ============================================
function renderHostColumn(data) {
    // CPU
    const cpuName = data.cpu.model || data.cpu.brand || 'Unknown CPU';
    setText('win-cpu-model', cpuName);
    setText('win-cpu-val', `${(data.cpu.usage_percent || 0).toFixed(1)}%`);

    // Show both physical and logical cores
    const logicalCores = data.cpu.logical_processors || 8;
    const physicalCores = data.cpu.physical_processors || Math.floor(logicalCores / 2);
    setText('win-cpu-cores', `${physicalCores} Physical | ${logicalCores} Logical`);

    // CPU Temperature (from temperature section)
    if (data.temperature && data.temperature.cpu_celsius > 0) {
        setText('win-cpu-temp', `${data.temperature.cpu_celsius}°C`);
    } else {
        setText('win-cpu-temp', 'N/A');
    }

    // Memory
    setText('win-mem-val', `${(data.memory.usage_percent || 0).toFixed(1)}%`);
    setText('win-mem-detail', `${(data.memory.used_mb / 1024).toFixed(1)} / ${(data.memory.total_mb / 1024).toFixed(1)} GB`);

    // Storage
    const validDisks = (data.disk || []).filter(d => /^[CDE]:/.test(d.device));
    renderDiskList('win-disk-list', validDisks);

    // Network (Calculated Rates)
    const { globalRxRate, globalTxRate, interfaceRates } = calculateNetworkRates('win', data.network);
    setText('win-net-rx', formatRate(globalRxRate));
    setText('win-net-tx', formatRate(globalTxRate));
    renderNetworkList('win-net-list', data.network, interfaceRates);

    // GPU
    renderGPUList('win-gpu-list', data.gpu);

    setText('win-host', data.system.hostname);
    setText('win-os', data.system.os);
    setText('win-uptime', formatUptime(data.system.uptime_seconds));
    setText('win-kernel', data.system.kernel);
}

// ============================================
// WSL GUEST RENDERER
// ============================================
function renderGuestColumn(data) {
    // CPU
    const cpuName = data.cpu.model || data.cpu.brand || 'Unknown CPU';
    setText('wsl-cpu-model', cpuName);
    setText('wsl-cpu-val', `${(data.cpu.usage_percent || 0).toFixed(1)}%`);

    let load = 'N/A';
    if (data.cpu.load_1 !== undefined) {
        load = `${data.cpu.load_1.toFixed(2)} / ${data.cpu.load_5.toFixed(2)} / ${data.cpu.load_15.toFixed(2)}`;
    }
    setText('wsl-load', `Load: ${load}`);
    // Show logical cores
    const cores = data.cpu.logical_processors || '?';
    setText('wsl-cpu-cores', `${cores} vCPUs`);
    // CPU Temperature (from temperature section)
    if (data.temperature && data.temperature.cpu_celsius > 0) {
        setText('wsl-cpu-temp', `${data.temperature.cpu_celsius}°C`);
    } else {
        setText('wsl-cpu-temp', 'N/A');
    }

    setText('wsl-mem-val', `${(data.memory.usage_percent || 0).toFixed(1)}%`);
    setText('wsl-mem-detail', `${(data.memory.used_mb / 1024).toFixed(1)} / ${(data.memory.total_mb / 1024).toFixed(1)} GB`);

    // Storage
    const wslDisks = (data.disk || []).filter(d =>
        d.device === '/' ||
        (d.device.startsWith('/mnt/') && !d.device.includes('docker') && !d.device.includes('wslg'))
    );
    renderDiskList('wsl-disk-list', wslDisks);

    // Network
    const { globalRxRate, globalTxRate, interfaceRates } = calculateNetworkRates('wsl', data.network);
    setText('wsl-net-rx', formatRate(globalRxRate));
    setText('wsl-net-tx', formatRate(globalTxRate));
    renderNetworkList('wsl-net-list', data.network, interfaceRates);

    renderGPUList('wsl-gpu-list', data.gpu);

    setText('wsl-host', data.system.hostname);
    setText('wsl-os', data.system.os);
    setText('wsl-uptime', formatUptime(data.system.uptime_seconds));
    setText('wsl-kernel', data.system.kernel);
}

// ============================================
// HELPER FUNCTIONS
// ============================================

function renderDiskList(containerId, disks) {
    const el = document.getElementById(containerId);
    if (!el) return;
    el.innerHTML = disks.map(d => {
        const color = d.used_percent > 90 ? '#ef4444' : (d.used_percent > 70 ? '#f59e0b' : '#6366f1');
        return `
        <div class="list-item" style="display:block;">
            <div style="display:flex; justify-content:space-between;">
                <span style="color:#e2e8f0; font-weight:500;">${d.device}</span>
                <span style="color:${color}; font-weight:bold;">${d.used_percent.toFixed(1)}%</span>
            </div>
            <div class="disk-bar-bg"><div class="disk-bar-fill" style="width:${d.used_percent}%; background:${color};"></div></div>
            <div style="font-size:0.75rem; color:#64748b; margin-top:2px;">${d.used_gb.toFixed(1)} GB used of ${d.total_gb.toFixed(1)} GB</div>
        </div>`;
    }).join('');
}

function renderGPUList(containerId, gpuData) {
    const el = document.getElementById(containerId);
    if (!el) return;
    if (!gpuData || !gpuData.devices || gpuData.devices.length === 0) {
        el.innerHTML = '<div style="color:#64748b; padding:5px;">No GPU Detected</div>';
        return;
    }
    el.innerHTML = gpuData.devices.map(g => {
        const temp = (g.temperature_celsius && g.temperature_celsius > 0) ? `${g.temperature_celsius}°C` : 'N/A';
        const tempColor = g.temperature_celsius > 80 ? '#ef4444' : (g.temperature_celsius > 60 ? '#f59e0b' : '#22c55e');
        const mem = g.memory_total_mb ? `${(g.memory_used_mb || 0)}/${g.memory_total_mb} MB` : 'N/A';
        return `
        <div class="list-item">
            <div>
                <div style="color:#cbd5e1; font-weight:600;">${g.model || g.vendor || 'GPU'}</div>
                <div style="color:#64748b; font-size:0.75rem;">
                    ${g.vendor} • Load: ${g.utilization_percent || 0}% • Mem: ${mem}
                </div>
            </div>
            <div style="color:${tempColor}; font-weight:bold; font-size:1.1rem;">${temp}</div>
        </div>`;
    }).join('');
}

function renderNetworkList(containerId, nets, rates) {
    const el = document.getElementById(containerId);
    if (!el) return;
    if (!nets) return;

    // Filter active interfaces only (bytes > 0)
    const active = nets.filter(n => (n.rx_bytes + n.tx_bytes) > 0)
        .sort((a, b) => (b.rx_bytes + b.tx_bytes) - (a.rx_bytes + a.tx_bytes));

    el.innerHTML = active.map(n => {
        const r = rates && rates[n.iface] ? rates[n.iface] : { rx: 0, tx: 0 };
        // Clean display (don't show 0.00 B/s if truly idle, just show 0 MB/s or similar? 
        // User asked for Actual Numbers, so we show what we calc.)

        return `
        <div class="list-item">
            <div>
                <span style="color:#e2e8f0; font-weight:500;">${n.iface}</span>
            </div>
            <div style="font-size: 0.75rem; color: #94a3b8; text-align: right;">
                <span style="color:#22c55e;">↓ ${formatBytes(r.rx)}/s</span> 
                <span style="margin:0 4px; color:#475569;">|</span>
                <span style="color:#3b82f6;">↑ ${formatBytes(r.tx)}/s</span>
            </div>
        </div>`;
    }).join('');
}

// UTILS
function setText(id, txt) {
    const el = document.getElementById(id);
    if (el) el.textContent = txt;
}

function formatRate(bytesPerSec) {
    if (!bytesPerSec || bytesPerSec === 0) return '0.0 MB/s';
    const kb = bytesPerSec / 1024;
    if (kb < 1024) {
        return kb.toFixed(1) + ' KB/s';
    }
    const mb = bytesPerSec / (1024 * 1024);
    return mb.toFixed(2) + ' MB/s';
}

function formatBytes(b) {
    if (b === 0) return '0';
    const i = Math.floor(Math.log(b) / Math.log(1024));
    return (b / Math.pow(1024, i)).toFixed(1) + ['B', 'KB', 'MB', 'GB'][i];
}

function formatUptime(s) {
    if (!s) return '0h 0m';
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return `${h}h ${m}m`;
}

// Generate Report Function
async function generateReport() {
    try {
        const btn = event.target.closest('button');
        const originalText = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="bx bx-loader bx-spin"></i> Generating...';

        const response = await fetch('/api/reports/generate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });

        const result = await response.json();

        if (result.success) {
            alert('Report generated successfully!\n\nHTML: ' + result.files.html + '\nMarkdown: ' + result.files.markdown);
        } else {
            alert('Failed to generate report: ' + (result.error || 'Unknown error'));
        }

        btn.disabled = false;
        btn.innerHTML = originalText;
    } catch (error) {
        console.error('Report generation error:', error);
        alert('Error generating report: ' + error.message);
    }
}

// ===================================
// CHART.JS INITIALIZATION
// ===================================

// Chart data history (rolling window of 60 points = 2 minutes at 2s intervals)
const chartHistory = {
    labels: [],
    cpu: { win: [], wsl: [] },
    memory: { win: [], wsl: [] },
    network: { rx: [], tx: [] },
    disk: { win: [], wsl: [] }
};

const MAX_DATA_POINTS = 60;

// Chart instances
let cpuChart, memoryChart, networkChart, diskChart;

// Dark theme configuration
const chartTheme = {
    backgroundColor: '#1e293b',
    gridColor: '#334155',
    textColor: '#cbd5e1',
    borderColor: 'rgba(255, 255, 255, 0.1)'
};

// Initialize all charts
document.addEventListener('DOMContentLoaded', () => {
    initializeCharts();
});

function initializeCharts() {
    // CPU Chart
    const cpuCtx = document.getElementById('cpuChart');
    if (cpuCtx) {
        cpuChart = new Chart(cpuCtx, {
            type: 'line',
            data: {
                labels: chartHistory.labels,
                datasets: [
                    {
                        label: 'Windows CPU',
                        data: chartHistory.cpu.win,
                        borderColor: '#22c55e',
                        backgroundColor: 'rgba(34, 197, 94, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    },
                    {
                        label: 'WSL CPU',
                        data: chartHistory.cpu.wsl,
                        borderColor: '#f59e0b',
                        backgroundColor: 'rgba(245, 158, 11, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    }
                ]
            },
            options: getChartOptions(0, 100, '%')
        });
    }

    // Memory Chart
    const memCtx = document.getElementById('memoryChart');
    if (memCtx) {
        memoryChart = new Chart(memCtx, {
            type: 'line',
            data: {
                labels: chartHistory.labels,
                datasets: [
                    {
                        label: 'Windows Memory',
                        data: chartHistory.memory.win,
                        borderColor: '#22c55e',
                        backgroundColor: 'rgba(34, 197, 94, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    },
                    {
                        label: 'WSL Memory',
                        data: chartHistory.memory.wsl,
                        borderColor: '#f59e0b',
                        backgroundColor: 'rgba(245, 158, 11, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    }
                ]
            },
            options: getChartOptions(0, 100, '%')
        });
    }

    // Network Chart (Stacked Area)
    const netCtx = document.getElementById('networkChart');
    if (netCtx) {
        networkChart = new Chart(netCtx, {
            type: 'line',
            data: {
                labels: chartHistory.labels,
                datasets: [
                    {
                        label: 'Download',
                        data: chartHistory.network.rx,
                        borderColor: '#22c55e',
                        backgroundColor: 'rgba(34, 197, 94, 0.3)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    },
                    {
                        label: 'Upload',
                        data: chartHistory.network.tx,
                        borderColor: '#3b82f6',
                        backgroundColor: 'rgba(59, 130, 246, 0.3)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    }
                ]
            },
            options: getChartOptions(0, null, 'MB/s')
        });
    }

    // Disk Chart
    const diskCtx = document.getElementById('diskChart');
    if (diskCtx) {
        diskChart = new Chart(diskCtx, {
            type: 'line',
            data: {
                labels: chartHistory.labels,
                datasets: [
                    {
                        label: 'Windows Disk',
                        data: chartHistory.disk.win,
                        borderColor: '#6366f1',
                        backgroundColor: 'rgba(99, 102, 241, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    },
                    {
                        label: 'WSL Disk',
                        data: chartHistory.disk.wsl,
                        borderColor: '#8b5cf6',
                        backgroundColor: 'rgba(139, 92, 246, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 0,
                        fill: true
                    }
                ]
            },
            options: getChartOptions(0, 100, '%')
        });
    }
}

function getChartOptions(min, max, suffix) {
    return {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                display: true,
                labels: {
                    color: chartTheme.textColor,
                    font: { size: 11 },
                    usePointStyle: true,
                    padding: 15
                }
            },
            tooltip: {
                mode: 'index',
                intersect: false,
                backgroundColor: 'rgba(15, 23, 42, 0.9)',
                titleColor: chartTheme.textColor,
                bodyColor: chartTheme.textColor,
                borderColor: chartTheme.borderColor,
                borderWidth: 1,
                padding: 10,
                callbacks: {
                    label: function (context) {
                        let label = context.dataset.label || '';
                        if (label) {
                            label += ': ';
                        }
                        label += context.parsed.y.toFixed(2) + (suffix || '');
                        return label;
                    }
                }
            }
        },
        scales: {
            y: {
                beginAtZero: true,
                min: min,
                max: max,
                grid: {
                    color: chartTheme.gridColor,
                    drawBorder: false
                },
                ticks: {
                    color: chartTheme.textColor,
                    font: { size: 10 },
                    callback: function (value) {
                        return value + (suffix || '');
                    }
                }
            },
            x: {
                grid: {
                    display: false
                },
                ticks: {
                    color: chartTheme.textColor,
                    font: { size: 9 },
                    maxRotation: 0,
                    autoSkip: true,
                    maxTicksLimit: 10
                }
            }
        },
        interaction: {
            mode: 'nearest',
            axis: 'x',
            intersect: false
        }
    };
}

// Update charts with new data
function updateCharts(winData, wslData) {
    const now = new Date();
    const timeLabel = now.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });

    // Add timestamp
    chartHistory.labels.push(timeLabel);

    // Add CPU data
    chartHistory.cpu.win.push(winData?.cpu?.usage_percent || 0);
    chartHistory.cpu.wsl.push(wslData?.cpu?.usage_percent || 0);

    // Add Memory data
    chartHistory.memory.win.push(winData?.memory?.usage_percent || 0);
    chartHistory.memory.wsl.push(wslData?.memory?.usage_percent || 0);

    // Add Network data (use global rates from previousState)
    const winNetRate = previousState.win.rxRate || 0;
    const winNetTxRate = previousState.win.txRate || 0;
    chartHistory.network.rx.push((winNetRate / (1024 * 1024)) || 0); // Convert to MB/s
    chartHistory.network.tx.push((winNetTxRate / (1024 * 1024)) || 0);

    // Add Disk data (average of all disks)
    const winDiskAvg = getAverageDiskUsage(winData?.disk);
    const wslDiskAvg = getAverageDiskUsage(wslData?.disk);
    chartHistory.disk.win.push(winDiskAvg);
    chartHistory.disk.wsl.push(wslDiskAvg);

    // Maintain rolling window
    if (chartHistory.labels.length > MAX_DATA_POINTS) {
        chartHistory.labels.shift();
        chartHistory.cpu.win.shift();
        chartHistory.cpu.wsl.shift();
        chartHistory.memory.win.shift();
        chartHistory.memory.wsl.shift();
        chartHistory.network.rx.shift();
        chartHistory.network.tx.shift();
        chartHistory.disk.win.shift();
        chartHistory.disk.wsl.shift();
    }

    // Update chart instances
    if (cpuChart) cpuChart.update('none');
    if (memoryChart) memoryChart.update('none');
    if (networkChart) networkChart.update('none');
    if (diskChart) diskChart.update('none');
}

function getAverageDiskUsage(disks) {
    if (!disks || disks.length === 0) return 0;
    const total = disks.reduce((sum, d) => sum + (d.usage_percent || d.used_percent || 0), 0);
    return total / disks.length;
}

// ===================================
// ============================================
// UI INTERACTIONS
// ============================================

function toggleNotificationDrawer() {
    const drawer = document.getElementById('notificationDrawer');
    if (drawer) drawer.classList.toggle('open');
}

function clearAllNotifications() {
    const list = document.getElementById('notificationList');
    if (list) list.innerHTML = '<div class="empty-state">No new alerts</div>';

    const badge = document.getElementById('alert-count');
    if (badge) {
        badge.innerText = '0';
        badge.style.display = 'none';
    }

    if (window.alertManager) {
        window.alertManager.alerts.clear();
    }
}

function updateStatusChips(winData, wslData) {
    // Windows Chip
    const winChip = document.getElementById('chip-win');
    if (winChip) {
        if (winData) {
            winChip.className = 'chip online';
            winChip.innerHTML = '<span class="chip-dot"></span> Windows: Online';
        } else {
            winChip.className = 'chip offline';
            winChip.innerHTML = '<span class="chip-dot"></span> Windows: Offline';
        }
    }

    // WSL Chip
    const wslChip = document.getElementById('chip-wsl');
    if (wslChip) {
        if (wslData) {
            wslChip.className = 'chip online';
            wslChip.innerHTML = '<span class="chip-dot"></span> WSL2: Online';
        } else {
            wslChip.className = 'chip offline';
            wslChip.innerHTML = '<span class="chip-dot"></span> WSL2: Offline';
        }
    }

    // Last Updated Chip
    const timeChip = document.getElementById('chip-last-updated');
    if (timeChip) {
        const now = new Date();
        const timeStr = now.toLocaleTimeString();
        timeChip.innerHTML = `<i class='bx bx-time'></i> Updated: ${timeStr}`;
    }
}

// ===================================
// ALERT MANAGER
// ===================================

class AlertManager {
    constructor() {
        this.alerts = new Map(); // key -> alert object
        this.thresholds = {
            cpu: { warning: 90, critical: 95 },
            memory: { warning: 85, critical: 95 },
            disk: { warning: 85, critical: 95 },
            gpuTemp: { warning: 80, critical: 90 }
        };
        window.alertManager = this;
    }

    checkMetrics(winData, wslData) {
        this.checkCPU('win', winData?.cpu?.usage_percent);
        this.checkCPU('wsl', wslData?.cpu?.usage_percent);
        this.checkMemory('win', winData?.memory?.usage_percent);
        this.checkMemory('wsl', wslData?.memory?.usage_percent);
        this.checkDisks('win', winData?.disk);
        this.checkDisks('wsl', wslData?.disk);
        this.checkGPUTemp('win', winData?.temperature?.gpus);
        this.checkGPUTemp('wsl', wslData?.temperature?.gpus);
        this.renderAlerts();
    }

    checkCPU(source, value) {
        if (!value) return;
        const key = `cpu-${source}`;
        const label = source === 'win' ? 'Windows' : 'WSL';
        if (value > this.thresholds.cpu.critical) {
            this.addAlert(key, 'critical', `${label} CPU`, `Usage critical: ${value.toFixed(1)}%`);
        } else if (value > this.thresholds.cpu.warning) {
            this.addAlert(key, 'warning', `${label} CPU`, `Usage high: ${value.toFixed(1)}%`);
        } else {
            this.removeAlert(key);
        }
    }

    checkMemory(source, value) {
        if (!value) return;
        const key = `memory-${source}`;
        const label = source === 'win' ? 'Windows' : 'WSL';
        if (value > this.thresholds.memory.critical) {
            this.addAlert(key, 'critical', `${label} Memory`, `Usage critical: ${value.toFixed(1)}%`);
        } else if (value > this.thresholds.memory.warning) {
            this.addAlert(key, 'warning', `${label} Memory`, `Usage high: ${value.toFixed(1)}%`);
        } else {
            this.removeAlert(key);
        }
    }

    checkDisks(source, disks) {
        if (!disks || !Array.isArray(disks)) return;
        const label = source === 'win' ? 'Windows' : 'WSL';
        disks.forEach(disk => {
            const usage = disk.usage_percent || disk.used_percent || 0;
            const device = disk.device || disk.mount || 'Unknown';
            const key = `disk-${source}-${device}`;
            if (usage > this.thresholds.disk.critical) {
                this.addAlert(key, 'critical', `${label} Disk ${device}`, `${usage.toFixed(1)}% used`);
            } else if (usage > this.thresholds.disk.warning) {
                this.addAlert(key, 'warning', `${label} Disk ${device}`, `${usage.toFixed(1)}% used`);
            } else {
                this.removeAlert(key);
            }
        });
    }

    checkGPUTemp(source, gpus) {
        if (!gpus || !Array.isArray(gpus)) return;
        const label = source === 'win' ? 'Windows' : 'WSL';
        gpus.forEach((gpu, idx) => {
            const temp = gpu.temperature_celsius || gpu.temperature || 0;
            if (temp === 0) return;
            const key = `gpu-temp-${source}-${idx}`;
            const gpuName = gpu.model || `GPU ${idx}`;
            if (temp > this.thresholds.gpuTemp.critical) {
                this.addAlert(key, 'critical', `${label} ${gpuName}`, `Critical Temp: ${temp}°C`);
            } else if (temp > this.thresholds.gpuTemp.warning) {
                this.addAlert(key, 'warning', `${label} ${gpuName}`, `High Temp: ${temp}°C`);
            } else {
                this.removeAlert(key);
            }
        });
    }

    addAlert(key, level, title, message) {
        this.alerts.set(key, { level, title, message, timestamp: Date.now() });
    }

    removeAlert(key) {
        this.alerts.delete(key);
    }

    renderAlerts() {
        const list = document.getElementById('notificationList');
        const badge = document.getElementById('alert-count');

        if (!list || !badge) return;

        const activeAlerts = Array.from(this.alerts.values()).sort((a, b) => b.timestamp - a.timestamp);

        // Update Badge
        if (activeAlerts.length > 0) {
            badge.innerText = activeAlerts.length > 9 ? '9+' : activeAlerts.length;
            badge.style.display = 'flex';
        } else {
            badge.style.display = 'none';
        }

        if (activeAlerts.length === 0) {
            list.innerHTML = '<div class="empty-state">No new alerts</div>';
            return;
        }

        list.innerHTML = activeAlerts.map(alert => {
            let iconClass = 'bx-info-circle';
            let severityClass = 'notif-info';

            if (alert.level === 'warning') {
                iconClass = 'bx-error';
                severityClass = 'notif-warning';
            } else if (alert.level === 'critical') {
                iconClass = 'bx-radiation';
                severityClass = 'notif-critical';
            }

            const timeAgo = Math.floor((Date.now() - alert.timestamp) / 1000);
            const timeText = timeAgo < 60 ? 'Just now' : `${Math.floor(timeAgo / 60)}m ago`;

            return `
            <div class="notification-item ${severityClass}">
                <i class='bx ${iconClass} notif-icon'></i>
                <div class="notif-body">
                    <div class="notif-title">${alert.title}</div>
                    <div class="notif-msg">${alert.message}</div>
                    <div class="notif-time">${timeText}</div>
                </div>
            </div>`;
        }).join('');
    }
}

// Initialize AlertManager
const alertManager = new AlertManager();

// Modify updateObservabilityGrid to include chart and alert updates
const originalUpdateObservabilityGrid = updateObservabilityGrid;
updateObservabilityGrid = function (winData, wslData) {
    originalUpdateObservabilityGrid(winData, wslData);
    updateCharts(winData, wslData);
    alertManager.checkMetrics(winData, wslData);
    updateStatusChips(winData, wslData); // UI Update
};

