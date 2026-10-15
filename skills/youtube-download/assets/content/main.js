// main.js - Webview UI logic and callback wiring

// State
let isDownloading = false;
let currentUrl = "";

// Cache DOM elements
const form = document.getElementById("download-form");
const urlInput = document.getElementById("url-input");
const formatSelect = document.getElementById("format-select");
const metadataCheckbox = document.getElementById("metadata-checkbox");
const transcriptCheckbox = document.getElementById("transcript-checkbox");
const transcriptOptions = document.getElementById("transcript-options");
const transcriptOutput = document.getElementById("transcript-output");
const transcriptOnlyCheckbox = document.getElementById("transcript-only-checkbox");
const removeTimestampsCheckbox = document.getElementById("remove-timestamps-checkbox");
const outputPath = document.getElementById("output-path");
const browseBtnEl = document.getElementById("browse-btn");
const downloadBtn = document.getElementById("download-btn");
const cancelBtn = document.getElementById("cancel-btn");
const progressSection = document.getElementById("progress-section");
const progressBar = document.getElementById("progress-bar");
const progressText = document.getElementById("progress-text");
const statusLogContent = document.getElementById("status-log-content");
const resultSection = document.getElementById("result-section");
const resultMessage = document.getElementById("result-message");
const downloadAgainBtn = document.getElementById("download-again-btn");

// Initialize
window.addEventListener("DOMContentLoaded", async () => {
    // Set default output path
    const defaultPath = (await copilot.selectOutputDirectory()).path || "./downloads";
    outputPath.value = defaultPath;

    // Verify setup
    const setup = await copilot.verifySetup();
    if (!setup.ready) {
        const warning = document.createElement("div");
        warning.className = "warning";
        warning.textContent = `⚠️ ${setup.message}`;
        form.parentElement.insertBefore(warning, form);
    }
});

// Form submission
form.addEventListener("submit", async (e) => {
    e.preventDefault();
    
    const url = urlInput.value.trim();
    const format = formatSelect.value;
    const outPath = outputPath.value.trim();
    const saveMeta = metadataCheckbox.checked;
    const transcriptEnabled = transcriptCheckbox.checked;
    const transcriptOnly = transcriptOnlyCheckbox.checked;
    const transcriptFormat = transcriptOutput.value;
    const removeTimestamps = removeTimestampsCheckbox.checked;

    if (!url || !outPath) {
        alert("Please fill in all required fields");
        return;
    }

    currentUrl = url;
    startDownload(url, format, outPath, saveMeta, transcriptEnabled, transcriptOnly, transcriptFormat, removeTimestamps);
});

// Browse button - select output directory
browseBtnEl.addEventListener("click", async () => {
    const result = await copilot.selectOutputDirectory();
    if (result.path) {
        outputPath.value = result.path;
    } else if (result.error) {
        alert(`Error: ${result.error}`);
    }
});

// Cancel button
cancelBtn.addEventListener("click", async () => {
    const result = await copilot.cancelDownload();
    if (result.error) {
        alert(`Error: ${result.error}`);
    }
});

// Transcript options toggle
transcriptCheckbox.addEventListener("change", () => {
    transcriptOptions.style.display = transcriptCheckbox.checked ? "block" : "none";
    if (!transcriptCheckbox.checked) {
        transcriptOnlyCheckbox.checked = false;
    }
    syncTranscriptOnlyState();
});

transcriptOnlyCheckbox.addEventListener("change", () => {
    syncTranscriptOnlyState();
});

// Download again
downloadAgainBtn.addEventListener("click", () => {
    resetForm();
});

/**
 * Start download and show progress
 */
async function startDownload(url, format, outPath, saveMeta, transcriptEnabled, transcriptOnly, transcriptFormat, removeTimestamps) {
    isDownloading = true;
    updateUIState(true);

    // Hide previous sections
    form.style.display = "none";
    resultSection.style.display = "none";
    progressSection.style.display = "block";

    // Reset progress
    progressBar.style.width = "0%";
    progressText.textContent = "0%";
    statusLogContent.innerHTML = "<p class='log-entry'>Starting download...</p>";

    if (transcriptEnabled) {
        const outputLabel = transcriptFormat === "txt" ? "text" : "markdown";
        statusLogContent.innerHTML += `<p class='log-entry'>Transcript conversion enabled (${outputLabel}, timestamps ${removeTimestamps ? "removed" : "kept"}).</p>`;
        if (transcriptOnly) {
            statusLogContent.innerHTML += "<p class='log-entry'>Transcript-only mode enabled (media download skipped).</p>";
        }
    }

    try {
        const result = await copilot.startDownload(
            url,
            format,
            outPath,
            saveMeta,
            transcriptEnabled,
            transcriptOnly,
            transcriptFormat,
            removeTimestamps,
        );

        if (result.success) {
            showSuccess(result);
        } else {
            showError(result.error || "Unknown error during download");
        }
    } catch (err) {
        showError(`Error: ${err.message}`);
    } finally {
        isDownloading = false;
        updateUIState(false);
    }
}

/**
 * Update progress bar and log
 * Called from backend via webview.eval()
 */
window.updateDownloadProgress = function (update) {
    const { percent, status } = update;

    // Update progress bar
    if (percent !== null) {
        const pct = Math.min(100, Math.max(0, percent));
        progressBar.style.width = `${pct}%`;
        progressText.textContent = `${Math.round(pct)}%`;
    }

    // Add status to log
    const logEntry = document.createElement("p");
    logEntry.className = "log-entry";
    logEntry.textContent = status;
    statusLogContent.appendChild(logEntry);

    // Auto-scroll to bottom
    statusLogContent.parentElement.scrollTop = statusLogContent.parentElement.scrollHeight;
};

/**
 * Show success result
 */
function showSuccess(result) {
    progressSection.style.display = "none";
    resultSection.style.display = "block";

    const transcriptPath = result.transcript?.outputPath;
    const transcriptWarning = result.transcript?.warning;
    const mediaLine = result.filename
        ? `<p>Saved to: ${escapeHtml(result.filename)}</p>`
        : transcriptPath
          ? "<p>Media download skipped (transcript-only mode).</p>"
          : `<p>Saved to: ${escapeHtml(urlInput.value)}</p>`;
    const transcriptLine = transcriptPath
        ? `<p>Transcript: ${escapeHtml(transcriptPath)}</p>`
        : transcriptWarning
          ? `<p>Transcript warning: ${escapeHtml(transcriptWarning)}</p>`
          : "";

    resultMessage.className = "result success";
    resultMessage.innerHTML = `
        <strong>✅ Download Successful!</strong>
        ${mediaLine}
        ${transcriptLine}
        <small>Check your output directory for the file and metadata</small>
    `;
}

/**
 * Show error result
 */
function showError(error) {
    progressSection.style.display = "none";
    resultSection.style.display = "block";

    resultMessage.className = "result error";
    resultMessage.innerHTML = `
        <strong>❌ Download Failed</strong>
        <p>${escapeHtml(error)}</p>
    `;
}

/**
 * Update UI state (enable/disable buttons)
 */
function updateUIState(downloading) {
    downloadBtn.disabled = downloading;
    cancelBtn.disabled = !downloading;
    urlInput.disabled = downloading;
    formatSelect.disabled = downloading;
    transcriptCheckbox.disabled = downloading;
    transcriptOutput.disabled = downloading;
    removeTimestampsCheckbox.disabled = downloading;
    outputPath.disabled = downloading;
    browseBtnEl.disabled = downloading;
    syncTranscriptOnlyState();
}

/**
 * Reset form to initial state
 */
function resetForm() {
    form.style.display = "block";
    resultSection.style.display = "none";
    progressSection.style.display = "none";
    urlInput.value = "";
    transcriptCheckbox.checked = false;
    transcriptOptions.style.display = "none";
    transcriptOutput.value = "md";
    transcriptOnlyCheckbox.checked = false;
    removeTimestampsCheckbox.checked = true;
    urlInput.focus();
    updateUIState(false);
}

function syncTranscriptOnlyState() {
    const transcriptOnly = transcriptCheckbox.checked && transcriptOnlyCheckbox.checked;
    formatSelect.disabled = isDownloading || transcriptOnly;
}

/**
 * Escape HTML to prevent XSS
 */
function escapeHtml(text) {
    const map = {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;",
    };
    return text.replace(/[&<>"']/g, (m) => map[m]);
}
