/* SQL Server Sentinel — Auto-refreshing dashboard */

const API_BASE = '';
const REFRESH_INTERVAL = 5000;

function esc(str) {
    if (str == null) return '';
    const d = document.createElement('div');
    d.textContent = String(str);
    return d.innerHTML;
}

async function fetchJSON(url, options = {}) {
    try {
        const resp = await fetch(API_BASE + url, options);
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        return await resp.json();
    } catch (err) {
        console.error(`Fetch error: ${url}`, err);
        return null;
    }
}

function badge(text, type) {
    return `<span class="badge badge-${type}">${text}</span>`;
}

function timeAgo(dateStr) {
    if (!dateStr) return '--';
    const d = new Date(dateStr);
    const now = new Date();
    const diffS = Math.floor((now - d) / 1000);
    if (diffS < 60) return `${diffS}s ago`;
    if (diffS < 3600) return `${Math.floor(diffS / 60)}m ago`;
    if (diffS < 86400) return `${Math.floor(diffS / 3600)}h ago`;
    return `${Math.floor(diffS / 86400)}d ago`;
}

function severityBadge(severity) {
    const map = { critical: 'critical', high: 'critical', warning: 'warning', medium: 'warning', low: 'info', info: 'info' };
    return badge(severity, map[severity] || 'unknown');
}

function statusBadge(status) {
    const map = {
        healthy: 'healthy', running: 'running', success: 'success',
        warning: 'warning', detected: 'warning', investigating: 'warning',
        remediating: 'warning', critical: 'critical', failed: 'failed',
        error: 'critical', escalated: 'escalated',
    };
    return badge(status, map[status] || 'unknown');
}

// --- Update functions ---

function updateHealth(health) {
    const el = (id, val) => { const e = document.getElementById(id); if (e) e.textContent = val ?? '--'; };

    el('metric-cpu', health.cpu_percent != null ? Math.round(health.cpu_percent) : '--');
    el('metric-memory', health.memory_used_mb != null ? Math.round(health.memory_used_mb) : '--');
    el('metric-connections', health.connection_count ?? '--');
    el('metric-blocking', health.blocking_count ?? '--');
    el('metric-long-queries', health.long_query_count ?? '--');

    const statusEl = document.getElementById('status-badge');
    if (statusEl) {
        const st = health.status || 'unknown';
        statusEl.className = `badge badge-${st}`;
        statusEl.textContent = st.toUpperCase();
    }
}

function updateIncidents(open, recent) {
    const container = document.getElementById('incidents-list');
    const countEl = document.getElementById('incident-count');
    if (!container) return;

    if (countEl) {
        countEl.textContent = open.length;
        countEl.className = open.length === 0 ? 'count-badge zero' : 'count-badge';
    }

    if (open.length === 0 && recent.length === 0) {
        container.innerHTML = '<p class="empty-state">No incidents</p>';
        return;
    }

    const items = (open.length > 0 ? open : recent.slice(0, 5));
    container.innerHTML = items.map(i => `
        <div class="list-item">
            <span class="item-title">${esc(i.title)}</span>
            ${severityBadge(i.severity)}
            ${statusBadge(i.status)}
            <span class="item-meta">${timeAgo(i.detected_at)}</span>
        </div>
    `).join('');
}

function updateJobs(jobs, runs) {
    const jobsEl = document.getElementById('jobs-list');
    const runsEl = document.getElementById('job-runs-list');

    if (jobsEl) {
        if (jobs.length === 0) {
            jobsEl.innerHTML = '<p class="empty-state">No jobs configured</p>';
        } else {
            jobsEl.innerHTML = jobs.map(j => `
                <div class="list-item">
                    <span class="item-title">${esc(j.name)}</span>
                    <span class="item-meta">${esc(j.schedule)}</span>
                    ${j.enabled ? badge('ON', 'success') : badge('OFF', 'unknown')}
                </div>
            `).join('');
        }
    }

    if (runsEl) {
        if (runs.length === 0) {
            runsEl.innerHTML = '<p class="empty-state">No recent runs</p>';
        } else {
            runsEl.innerHTML = runs.map(r => `
                <div class="list-item">
                    <span class="item-title">${esc(r.job_name)}</span>
                    ${statusBadge(r.status)}
                    <span class="item-meta">${r.duration_ms != null ? r.duration_ms + 'ms' : '--'}</span>
                    <span class="item-meta">${timeAgo(r.started_at)}</span>
                </div>
            `).join('');
        }
    }
}

function updateValidation(scorecard) {
    const pct = document.getElementById('score-percent');
    const passed = document.getElementById('score-passed');
    const failed = document.getElementById('score-failed');
    const critical = document.getElementById('score-critical');
    const rulesEl = document.getElementById('validation-rules');
    const ring = document.querySelector('.score-ring');

    if (pct) pct.textContent = scorecard.score_percent ?? '--';
    if (passed) passed.textContent = scorecard.passed ?? 0;
    if (failed) failed.textContent = scorecard.failed ?? 0;
    if (critical) critical.textContent = scorecard.critical_failures ?? 0;

    if (ring) {
        ring.className = 'score-ring';
        const s = scorecard.score_percent ?? 100;
        if (s < 50) ring.classList.add('critical');
        else if (s < 80) ring.classList.add('warning');
    }

    if (rulesEl && scorecard.rules) {
        rulesEl.innerHTML = scorecard.rules.map(r => `
            <div class="list-item">
                <span class="item-title">${esc(r.rule_name)}</span>
                ${r.passed ? badge('PASS', 'success') : badge('FAIL', r.severity === 'critical' ? 'critical' : 'warning')}
                <span class="item-meta">${r.violation_count ?? 0} violations</span>
            </div>
        `).join('');
    }
}

function updateChaos(scenarios) {
    const container = document.getElementById('chaos-scenarios');
    if (!container) return;

    container.innerHTML = scenarios.map(s => `
        <div class="list-item" style="flex-wrap: wrap;">
            <span class="item-title">${esc(s.name)}</span>
            ${severityBadge(s.severity)}
            ${s.on_cooldown ? badge(`${s.cooldown_remaining_s}s`, 'cooldown') : ''}
            <button class="btn btn-chaos btn-sm" ${s.on_cooldown ? 'disabled' : ''}
                    onclick="triggerChaos('${esc(s.name)}')">
                Trigger
            </button>
        </div>
    `).join('');
}

function updatePostmortems(postmortems) {
    const container = document.getElementById('postmortems-list');
    if (!container) return;

    if (postmortems.length === 0) {
        container.innerHTML = '<p class="empty-state">No postmortems yet</p>';
        return;
    }

    container.innerHTML = postmortems.map(p => `
        <div class="postmortem-item">
            <div class="postmortem-header">
                <strong>${esc(p.incident_title || 'Incident #' + p.incident_id)}</strong>
                ${severityBadge(p.severity || 'info')}
                <span class="item-meta">${timeAgo(p.generated_at)}</span>
            </div>
            <div class="postmortem-summary">${esc(p.summary || '')}</div>
        </div>
    `).join('');
}

function updateHealthcare(metrics) {
    const el = (id, val) => {
        const e = document.getElementById(id);
        if (e) e.textContent = val ?? '--';
    };

    el('metric-claims', metrics.claims_today ?? '--');
    el('metric-rejection', metrics.rejection_rate != null ? metrics.rejection_rate : '--');
    el('metric-generic', metrics.generic_rate != null ? metrics.generic_rate : '--');
    el('metric-pdc', metrics.avg_pdc != null ? metrics.avg_pdc : '--');

    // Color rejection rate card by threshold
    const rejCard = document.getElementById('card-rejection');
    if (rejCard) {
        rejCard.classList.remove('status-warning', 'status-critical');
        const rate = metrics.rejection_rate || 0;
        if (rate >= 15) rejCard.classList.add('status-critical');
        else if (rate >= 5) rejCard.classList.add('status-warning');
    }

    // Color PDC card (low is bad)
    const pdcCard = document.getElementById('card-pdc');
    if (pdcCard) {
        pdcCard.classList.remove('status-warning', 'status-critical');
        const pdc = metrics.avg_pdc || 0;
        if (pdc > 0 && pdc < 0.80) pdcCard.classList.add('status-warning');
    }
}

// --- Actions ---

async function triggerChaos(name) {
    const result = await fetchJSON('/api/chaos/trigger', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ scenario: name }),
    });
    if (result) refreshDashboard();
}

async function triggerRandomChaos() {
    const result = await fetchJSON('/api/chaos/random', { method: 'POST' });
    if (result) refreshDashboard();
}

async function runValidation() {
    await fetchJSON('/api/validation/run', { method: 'POST' });
    refreshDashboard();
}

// --- Main refresh loop ---

async function refreshDashboard() {
    const data = await fetchJSON('/api/dashboard');
    if (!data) return;

    updateHealth(data.health || {});
    updateIncidents(data.open_incidents || [], data.recent_incidents || []);
    updateJobs(data.jobs || [], data.recent_job_runs || []);
    updateValidation(data.validation || {});
    updateChaos(data.chaos_scenarios || []);
    updateHealthcare(data.healthcare || {});
    updatePostmortems(data.postmortems || []);

    document.getElementById('last-updated').textContent =
        `Updated: ${new Date().toLocaleTimeString()}`;
}

// Initial load + auto-refresh
refreshDashboard();
setInterval(refreshDashboard, REFRESH_INTERVAL);
