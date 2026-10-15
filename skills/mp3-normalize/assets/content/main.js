// main.js - Webview UI logic for MP3 normalizer

// DOM refs
const form = document.getElementById("normalize-form");
const sourceDirInput = document.getElementById("source-dir");
const targetDbInput = document.getElementById("target-db");
const startBtn = document.getElementById("start-btn");
const cancelBtn = document.getElementById("cancel-btn");
const formSection = document.getElementById("form-section");
const progressSection = document.getElementById("progress-section");
const progressBar = document.getElementById("progress-bar");
const progressLabel = document.getElementById("progress-label");
const progressPct = document.getElementById("progress-pct");
const logContent = document.getElementById("log-content");
const resultSection = document.getElementById("result-section");
const resultMessage = document.getElementById("result-message");
const normalizeAgainBtn = document.getElementById("normalize-again-btn");

// Initialize
window.addEventListener("DOMContentLoaded", async () => {
    const setup = await copilot.verifySetup();
    if (!setup.ready) {
        const banner = document.createElement("div");
        banner.className = "warning";
        banner.textContent = `⚠️ ${setup.message}`;
        formSection.insertBefore(banner, form);
    }
});

// Form submit
form.addEventListener("submit", async (e) => {
    e.preventDefault();

    const sourceDir = sourceDirInput.value.trim();
    const targetDb = Number(targetDbInput.value) || 89;
    const mode = document.querySelector('input[name="mode"]:checked').value;

    if (!sourceDir) {
        alert("Please enter a source folder path.");
        return;
    }
    if (targetDb < 70 || targetDb > 105) {
        alert("Target dB must be between 70 and 105.");
        return;
    }

    await startNormalization(sourceDir, mode, targetDb);
});

// Cancel
cancelBtn.addEventListener("click", async () => {
    await copilot.cancelNormalization();
});

// Normalize again
normalizeAgainBtn.addEventListener("click", () => {
    resetUI();
});

async function startNormalization(sourceDir, mode, targetDb) {
    setRunning(true);
    formSection.style.display = "none";
    resultSection.style.display = "none";
    progressSection.style.display = "block";

    // Reset progress UI
    progressBar.style.width = "0%";
    progressPct.textContent = "0%";
    progressLabel.textContent = "Starting...";
    logContent.innerHTML = "";
    appendLog(`Mode: ${mode} | Target: ${targetDb} dB | Folder: ${sourceDir}`);

    try {
        const result = await copilot.startNormalization(sourceDir, mode, targetDb);

        if (result.success) {
            showSuccess(result);
        } else {
            showError(result.error || "Unknown error.");
        }
    } catch (err) {
        showError(`Error: ${err.message}`);
    } finally {
        setRunning(false);
    }
}

/**
 * Called from backend via webview.eval() for live progress updates.
 */
window.updateProgress = function ({ percent, status }) {
    if (percent !== null && percent !== undefined) {
        const pct = Math.min(100, Math.max(0, percent));
        progressBar.style.width = `${pct}%`;
        progressPct.textContent = `${Math.round(pct)}%`;
        progressLabel.textContent = pct >= 100 ? "Complete!" : pct < 15 ? "Copying files..." : "Normalizing...";
    }
    if (status) {
        appendLog(status);
    }
};

function appendLog(text) {
    const p = document.createElement("p");
    p.className = "log-entry";
    p.textContent = text;
    logContent.appendChild(p);
    logContent.parentElement.scrollTop = logContent.parentElement.scrollHeight;
}

function showSuccess(result) {
    progressSection.style.display = "none";
    resultSection.style.display = "block";
    resultMessage.className = "result success";
    resultMessage.innerHTML = `
        <strong>✅ Normalization Complete!</strong>
        <p>${result.count} file(s) normalized</p>
        <p>Output folder: <code>${escapeHtml(result.outputDir)}</code></p>
        <small>Original files are untouched. Normalized copies are in the output folder.</small>
    `;
}

function showError(error) {
    progressSection.style.display = "none";
    resultSection.style.display = "block";
    resultMessage.className = "result error";
    resultMessage.innerHTML = `
        <strong>❌ Normalization Failed</strong>
        <p>${escapeHtml(error)}</p>
    `;
}

function setRunning(on) {
    startBtn.disabled = on;
    cancelBtn.disabled = !on;
    sourceDirInput.disabled = on;
    targetDbInput.disabled = on;
    document.querySelectorAll('input[name="mode"]').forEach((r) => (r.disabled = on));
}

function resetUI() {
    formSection.style.display = "block";
    resultSection.style.display = "none";
    progressSection.style.display = "none";
    setRunning(false);
    sourceDirInput.focus();
}

function escapeHtml(text) {
    const map = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" };
    return String(text).replace(/[&<>"']/g, (c) => map[c]);
}
