// backend.js - YouTube download orchestration using yt-dlp
// Handles subprocess management, progress parsing, and format discovery
// Supports both yt-dlp binary and Python module

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, chmodSync, readdirSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { resolve, join } from "node:path";
import { createWriteStream } from "node:fs";
import { get } from "node:https";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const SKILL_ROOT = join(__dirname, "..");
const BINARY_PATH = join(SKILL_ROOT, "bin", "yt-dlp");

/**
 * Detect the best way to run yt-dlp (binary, Python module, or venv)
 * @returns {Promise<Object>} { command, args } for spawn()
 */
async function getYtDlpCommand() {
    // Check for binary first
    if (existsSync(BINARY_PATH)) {
        return { command: BINARY_PATH, args: [] };
    }
    
    // Check for Python module
    try {
        const result = await testCommand("python3", ["-c", "import yt_dlp"]);
        if (result) {
            return { command: "python3", args: ["-m", "yt_dlp"] };
        }
    } catch (e) {
        // Fall through
    }
    
    // Check for venv
    const venvPython = join(SKILL_ROOT, ".venv", "bin", "python3");
    if (existsSync(venvPython)) {
        return { command: venvPython, args: ["-m", "yt_dlp"] };
    }
    
    throw new Error(
        "yt-dlp not found. Install with: pip install yt-dlp OR download binary from https://github.com/yt-dlp/yt-dlp/releases"
    );
}

/**
 * Test if a command works
 * @private
 */
function testCommand(command, args) {
    return new Promise((resolve) => {
        const proc = spawn(command, args);
        proc.on("close", (code) => {
            resolve(code === 0);
        });
        proc.on("error", () => {
            resolve(false);
        });
        setTimeout(() => {
            proc.kill();
            resolve(false);
        }, 3000);
    });
}

/**
 * Download the yt-dlp binary (Linux/Mac only)
 * @returns {Promise<void>}
 */
export async function downloadBinary() {
    const binDir = join(SKILL_ROOT, "bin");
    if (!existsSync(binDir)) {
        mkdirSync(binDir, { recursive: true });
    }
    
    if (existsSync(BINARY_PATH)) {
        console.log("yt-dlp binary already exists");
        return;
    }
    
    // Detect OS
    const platform = process.platform;
    let downloadUrl;
    
    if (platform === "linux") {
        downloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp";
    } else if (platform === "darwin") {
        downloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos";
    } else if (platform === "win32") {
        downloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";
    } else {
        throw new Error(`Unsupported platform: ${platform}`);
    }
    
    console.log(`Downloading yt-dlp binary from ${downloadUrl}...`);
    
    return new Promise((resolve, reject) => {
        const file = createWriteStream(BINARY_PATH);
        
        get(downloadUrl, (response) => {
            if (response.statusCode === 302 || response.statusCode === 301) {
                // Follow redirect
                get(response.headers.location, (redirectResponse) => {
                    redirectResponse.pipe(file);
                    file.on("finish", () => {
                        file.close();
                        if (platform !== "win32") {
                            chmodSync(BINARY_PATH, 0o755);
                        }
                        console.log("yt-dlp binary downloaded successfully");
                        resolve();
                    });
                }).on("error", reject);
            } else if (response.statusCode === 200) {
                response.pipe(file);
                file.on("finish", () => {
                    file.close();
                    if (platform !== "win32") {
                        chmodSync(BINARY_PATH, 0o755);
                    }
                    console.log("yt-dlp binary downloaded successfully");
                    resolve();
                });
            } else {
                reject(new Error(`HTTP ${response.statusCode}`));
            }
        }).on("error", reject);
    });
}

/**
 * Verify that yt-dlp is available (binary, Python, or venv)
 * @returns {Promise<boolean>}
 */
export async function verifyPrerequisites() {
    try {
        const { command, args } = await getYtDlpCommand();
        return await testCommand(command, [...args, "--version"]);
    } catch (err) {
        console.error("yt-dlp not available:", err.message);
        return false;
    }
}

/**
 * List available formats for a YouTube URL
 * @param {string} url - YouTube URL
 * @returns {Promise<Array>} Array of format objects
 */
export async function listFormats(url) {
    return new Promise(async (resolve, reject) => {
        try {
            const { command, args } = await getYtDlpCommand();
            const proc = spawn(command, [...args, "-F", "--dump-json", url]);
            
            let output = "";
            let error = "";
            
            proc.stdout.on("data", (data) => {
                output += data.toString();
            });
            
            proc.stderr.on("data", (data) => {
                error += data.toString();
            });
            
            proc.on("close", (code) => {
                if (code === 0 && output.trim()) {
                    try {
                        const data = JSON.parse(output);
                        const formats = (data.formats || []).map((fmt) => ({
                            id: fmt.format_id,
                            label: `${fmt.format} (${fmt.ext})`,
                            ext: fmt.ext,
                            vcodec: fmt.vcodec,
                            acodec: fmt.acodec,
                        }));
                        resolve(formats);
                    } catch (e) {
                        resolve([]); // Return empty on parse error
                    }
                } else {
                    reject(new Error(error || "Failed to fetch formats"));
                }
            });
            
            proc.on("error", (err) => {
                reject(err);
            });
            
            // Timeout after 15 seconds
            setTimeout(() => {
                proc.kill();
                reject(new Error("Format discovery timed out"));
            }, 15000);
        } catch (err) {
            reject(err);
        }
    });
}

/**
 * Download a YouTube video with progress tracking
 * @param {Object} options
 * @param {string} options.url - YouTube URL
 * @param {string} options.format - Format: 'best', 'audio', 'mp4', 'mkv', or format_id
 * @param {string} options.outputPath - Output directory
 * @param {boolean} options.metadata - Whether to save metadata (JSON, thumbnail, subs)
 * @param {boolean} options.transcriptEnabled - Whether to download and convert transcript
 * @param {boolean} options.transcriptOnly - Whether to skip media download and only process transcript
 * @param {string} options.transcriptOutput - Transcript output format: 'md' or 'txt'
 * @param {boolean} options.removeTimestamps - Whether timestamps should be removed during conversion
 * @param {Function} options.onProgress - Progress callback: (progress, status) => {}
 * @returns {Promise<Object>} Download result { success, filename, error }
 */
export async function downloadVideo(options) {
    const {
        url,
        format = "best",
        outputPath,
        metadata = true,
        transcriptEnabled = false,
        transcriptOnly = false,
        transcriptOutput = "md",
        removeTimestamps = true,
        onProgress,
    } = options;
    const effectiveTranscriptEnabled = transcriptEnabled || transcriptOnly;
    
    if (!url) {
        throw new Error("URL is required");
    }
    
    if (!outputPath) {
        throw new Error("Output path is required");
    }
    
    // Ensure output directory exists
    if (!existsSync(outputPath)) {
        mkdirSync(outputPath, { recursive: true });
    }
    
    let transcriptResult = {
        requested: effectiveTranscriptEnabled,
        converted: false,
        outputPath: "",
        warning: "",
        sourceVtt: "",
    };

    try {
        const { command, args } = await getYtDlpCommand();
        const beforeVttFiles = listSubtitleFiles(outputPath);
        
        // Build yt-dlp arguments
        const allArgs = [...args];
        allArgs.push("--js-runtimes", `node:${process.execPath}`);
        
        // Format selection
        if (!transcriptOnly) {
            const formatArgs = buildFormatArgs(format);
            allArgs.push(...formatArgs);
        }
        
        // Output template
        allArgs.push("-o", `${resolve(outputPath)}/%(title)s.%(ext)s`);
        
        // Metadata options
        if (metadata) {
            allArgs.push("--write-info-json"); // Save video info
            allArgs.push("--write-thumbnail"); // Save thumbnail
            allArgs.push("--write-auto-subs"); // Save auto-generated subtitles
        }

        // Transcript options
        if (effectiveTranscriptEnabled) {
            allArgs.push("--write-auto-subs");
            allArgs.push("--write-subs");
            allArgs.push("--sub-langs", "en.*");
            allArgs.push("--sub-format", "vtt");
        }

        if (transcriptOnly) {
            allArgs.push("--skip-download");
        }
        
        // Progress template for parsing
        allArgs.push("--progress-template", "%(progress.status)s at %(progress._percentage_str)s");
        
        // URL
        allArgs.push(url);
        
        return new Promise((resolve) => {
            const proc = spawn(command, allArgs);
            let lastLine = "";
            let filename = "";
            let error = "";
            
            // Track progress from stdout
            proc.stdout.on("data", (data) => {
                const lines = data.toString().split("\n");
                for (const line of lines) {
                    if (!line.trim()) continue;
                    lastLine = line;
                    
                    // Parse progress percentage
                    const percentMatch = line.match(/(\d+(?:\.\d+)?)/);
                    if (percentMatch) {
                        const percent = parseFloat(percentMatch[1]);
                        if (onProgress && !isNaN(percent)) {
                            onProgress(percent, line.substring(0, 80)); // Keep log concise
                        }
                    }
                    
                    // Capture filename
                    if (line.includes("Destination:")) {
                        const match = line.match(/Destination:\s*(.+)$/);
                        if (match) {
                            filename = match[1].trim();
                        }
                    }
                }
            });
            
            // Capture errors
            proc.stderr.on("data", (data) => {
                error += data.toString();
                if (onProgress) {
                    const lines = data.toString().split("\n").filter((l) => l.trim());
                    for (const line of lines) {
                        onProgress(null, `ERROR: ${line.substring(0, 70)}`);
                    }
                }
            });
            
            proc.on("close", (code) => {
                if (code === 0) {
                    if (effectiveTranscriptEnabled) {
                        transcriptResult = convertTranscriptFiles({
                            outputPath,
                            beforeVttFiles,
                            transcriptOutput,
                            removeTimestamps,
                            videoUrl: url,
                        });
                    }

                    resolve({
                        success: true,
                        filename,
                        message: "Download completed successfully",
                        transcript: transcriptResult,
                    });
                } else {
                    resolve({
                        success: false,
                        error: error || `yt-dlp exited with code ${code}`,
                        transcript: transcriptResult,
                    });
                }
            });
            
            proc.on("error", (err) => {
                resolve({
                    success: false,
                    error: err.message,
                    transcript: transcriptResult,
                });
            });
        });
    } catch (err) {
        return {
            success: false,
            error: err.message,
            transcript: transcriptResult,
        };
    }
}

/**
 * List current VTT subtitle files in the output directory.
 * @param {string} directory
 * @returns {Set<string>}
 */
function listSubtitleFiles(directory) {
    try {
        const files = readdirSync(directory);
        const subtitles = files.filter((file) => file.toLowerCase().endsWith(".vtt"));
        return new Set(subtitles);
    } catch {
        return new Set();
    }
}

/**
 * Convert newly downloaded VTT transcripts into text or markdown.
 * @param {Object} params
 * @returns {{requested:boolean, converted:boolean, outputPath:string, warning:string, sourceVtt:string}}
 */
function convertTranscriptFiles(params) {
    const { outputPath, beforeVttFiles, transcriptOutput, removeTimestamps, videoUrl } = params;

    try {
        const afterVttFiles = listSubtitleFiles(outputPath);
        const newFiles = [];

        for (const subtitleFile of afterVttFiles) {
            if (!beforeVttFiles.has(subtitleFile)) {
                newFiles.push(subtitleFile);
            }
        }

        const transcriptFile = chooseTranscriptFile(newFiles, outputPath) || chooseTranscriptFile([...afterVttFiles], outputPath);

        if (!transcriptFile) {
            return {
                requested: true,
                converted: false,
                outputPath: "",
                warning: "No VTT transcript file was generated for this video.",
                sourceVtt: "",
            };
        }

        const sourcePath = join(outputPath, transcriptFile);
        const vttContent = readFileSync(sourcePath, "utf8");
        const transcriptText = parseVttToPlainText(vttContent, removeTimestamps);

        if (!transcriptText.trim()) {
            return {
                requested: true,
                converted: false,
                outputPath: "",
                warning: "Transcript file was downloaded, but no text content was extracted.",
                sourceVtt: sourcePath,
            };
        }

        const outputFormat = transcriptOutput === "txt" ? "txt" : "md";
        const outputPathname = sourcePath.replace(/\.vtt$/i, `.${outputFormat}`);
        const outputContent =
            outputFormat === "md"
                ? buildMarkdownTranscript(transcriptText, videoUrl)
                : `${transcriptText}\n`;

        writeFileSync(outputPathname, outputContent, "utf8");

        return {
            requested: true,
            converted: true,
            outputPath: outputPathname,
            warning: "",
            sourceVtt: sourcePath,
        };
    } catch (error) {
        return {
            requested: true,
            converted: false,
            outputPath: "",
            warning: `Transcript conversion failed: ${error.message}`,
            sourceVtt: "",
        };
    }
}

/**
 * Prefer manual English transcripts, then auto English transcripts.
 * @param {Array<string>} candidates
 * @param {string} directory
 * @returns {string}
 */
function chooseTranscriptFile(candidates, directory) {
    if (!candidates || candidates.length === 0) {
        return "";
    }

    const sorted = [...candidates].sort((a, b) => getModifiedTime(directory, b) - getModifiedTime(directory, a));
    const manualEnglish = sorted.find(
        (file) => file.toLowerCase().includes(".en") && !file.toLowerCase().includes("auto"),
    );
    if (manualEnglish) {
        return manualEnglish;
    }

    const english = sorted.find((file) => file.toLowerCase().includes(".en"));
    if (english) {
        return english;
    }

    return sorted[0];
}

/**
 * Safely get a file's modified timestamp.
 * @param {string} directory
 * @param {string} filename
 * @returns {number}
 */
function getModifiedTime(directory, filename) {
    try {
        return statSync(join(directory, filename)).mtimeMs;
    } catch {
        return 0;
    }
}

/**
 * Convert VTT content to plain transcript text.
 * @param {string} vttContent
 * @param {boolean} removeTimestamps
 * @returns {string}
 */
function parseVttToPlainText(vttContent, removeTimestamps = true) {
    const lines = vttContent.split(/\r?\n/);
    const outputLines = [];
    let lastLine = "";
    const timestampRegex = /(?:\d{2}:)?\d{2}:\d{2}\.\d{3}\s+-->\s+(?:\d{2}:)?\d{2}:\d{2}\.\d{3}/;

    for (const rawLine of lines) {
        const line = rawLine.trim();

        if (!line) {
            continue;
        }

        if (line === "WEBVTT") {
            continue;
        }

        if (/^NOTE(\s|$)/.test(line) || /^STYLE(\s|$)/.test(line) || /^REGION(\s|$)/.test(line)) {
            continue;
        }

        if (/^\d+$/.test(line)) {
            continue;
        }

        if (timestampRegex.test(line)) {
            if (!removeTimestamps) {
                outputLines.push(line);
            }
            continue;
        }

        const cleanedLine = line
            .replace(/<[^>]+>/g, "")
            .replace(/&nbsp;/g, " ")
            .replace(/&amp;/g, "&")
            .replace(/\s+/g, " ")
            .trim();

        if (!cleanedLine) {
            continue;
        }

        // Avoid repeated adjacent caption lines.
        if (cleanedLine === lastLine) {
            continue;
        }

        outputLines.push(cleanedLine);
        lastLine = cleanedLine;
    }

    return outputLines.join("\n");
}

/**
 * Build markdown transcript output.
 * @param {string} transcriptText
 * @param {string} videoUrl
 * @returns {string}
 */
function buildMarkdownTranscript(transcriptText, videoUrl) {
    return `# YouTube Transcript\n\nSource: ${videoUrl}\n\n## Transcript\n\n${transcriptText}\n`;
}

/**
 * Build format arguments for yt-dlp based on user selection
 * @param {string} format
 * @returns {Array<string>}
 */
function buildFormatArgs(format) {
    const formatMap = {
        best: ["-f", "best"],
        "best-video": ["-f", "bv+ba/b"],
        audio: ["-f", "ba", "-x", "--audio-format", "mp3"],
        "audio-m4a": ["-f", "ba", "-x", "--audio-format", "m4a"],
        "audio-wav": ["-f", "ba", "-x", "--audio-format", "wav"],
        mp4: ["-f", "bv[ext=mp4]+ba[ext=m4a]/b[ext=mp4]", "--merge-output-format", "mp4"],
        mkv: ["-f", "bv+ba/b", "--merge-output-format", "mkv"],
        "360p": ["-f", "bv[height<=360]+ba/b[height<=360]"],
        "720p": ["-f", "bv[height<=720]+ba/b[height<=720]"],
        "1080p": ["-f", "bv[height<=1080]+ba/b[height<=1080]"],
    };
    
    return formatMap[format] || ["-f", "best"];
}

/**
 * Cancel a download by killing the process
 * (Note: This is simplified; in practice, you'd track process IDs)
 */
export function cancelDownload() {
    // This would be called from main.mjs with an actual process reference
    // For now, it's a placeholder
}
