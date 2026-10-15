// main.mjs - Extension entry point
// Defines callbacks, tool registration, and slash command for YouTube downloading

import { joinSession } from "@github/copilot-sdk/extension";
import { join } from "node:path";
import { homedir } from "node:os";
import { CopilotWebview } from "./lib/copilot-webview.js";
import { downloadVideo, listFormats, verifyPrerequisites, downloadBinary } from "./backend.js";

let session = null;

// Track active downloads (in production, use a proper queue manager)
let currentDownload = null;

// Create webview instance
const webview = new CopilotWebview({
    extensionName: "youtube_dl_ui",
    contentDir: join(import.meta.dirname, "..", "assets", "content"),
    callbacks: {
        /**
         * Start a YouTube download
         */
        startDownload: async (url, format, outputPath, metadata, transcriptEnabled, transcriptOnly, transcriptOutput, removeTimestamps) => {
            if (currentDownload) {
                return { error: "Download already in progress. Cancel it first." };
            }
            
            if (!url || !url.trim()) {
                return { error: "YouTube URL is required" };
            }
            
            if (!outputPath || !outputPath.trim()) {
                return { error: "Output path is required" };
            }
            
            const progressUpdates = [];
            
            try {
                // Start download with progress tracking
                const result = await downloadVideo({
                    url: url.trim(),
                    format: format || "best",
                    outputPath: outputPath.trim(),
                    metadata: metadata !== false,
                    transcriptEnabled: transcriptEnabled === true,
                    transcriptOnly: transcriptOnly === true,
                    transcriptOutput: transcriptOutput || "md",
                    removeTimestamps: removeTimestamps !== false,
                    onProgress: (percent, status) => {
                        const update = { percent, status, timestamp: Date.now() };
                        progressUpdates.push(update);
                        // Push progress to webview via eval
                        webview
                            .eval(
                                `window.updateDownloadProgress && window.updateDownloadProgress(${JSON.stringify(update)})`,
                            )
                            .catch(() => {}); // Ignore if webview is closed
                    },
                });
                
                if (result.success) {
                    await session.log(`✅ Download completed: ${result.filename || url}`);
                    return {
                        success: true,
                        filename: result.filename,
                        progress: progressUpdates,
                        transcript: result.transcript,
                    };
                } else {
                    await session.log(`❌ Download failed: ${result.error}`);
                    return { error: result.error, progress: progressUpdates, transcript: result.transcript };
                }
            } catch (err) {
                await session.log(`❌ Download error: ${err.message}`);
                return { error: err.message };
            } finally {
                currentDownload = null;
            }
        },
        
        /**
         * Cancel the current download
         */
        cancelDownload: async () => {
            if (currentDownload) {
                // In a more robust implementation, track process IDs and kill them
                currentDownload = null;
                return { success: true, message: "Download cancelled" };
            }
            return { error: "No active download to cancel" };
        },
        
        /**
         * List available formats for a URL
         */
        listFormats: async (url) => {
            if (!url || !url.trim()) {
                return { error: "URL is required" };
            }
            
            try {
                const formats = await listFormats(url.trim());
                return {
                    success: true,
                    formats: formats.slice(0, 50), // Limit to 50 for UI
                };
            } catch (err) {
                return { error: `Failed to fetch formats: ${err.message}` };
            }
        },
        
        /**
         * Select output directory
         * In a real implementation, this would open a file picker
         * For now, return a default path
         */
        selectOutputDirectory: async () => {
            // Use home directory as default
            const defaultPath = join(homedir(), "Downloads", "YouTube");
            return { path: defaultPath };
        },
        
        /**
         * Log message from webview
         */
        log: (msg, opts) => session.log(msg, opts),
        
        /**
         * Verify that yt-dlp is installed
         */
        verifySetup: async () => {
            const hasPrereqs = await verifyPrerequisites();
            if (!hasPrereqs) {
                return {
                    ready: false,
                    message: "yt-dlp not found. Use downloadBinary or install with: pip install yt-dlp",
                };
            }
            return { ready: true, message: "Ready to download" };
        },
        
        /**
         * Download yt-dlp binary for Linux/Mac
         */
        downloadBinarySetup: async () => {
            try {
                await downloadBinary();
                return { success: true, message: "yt-dlp binary downloaded successfully" };
            } catch (err) {
                return { error: `Failed to download binary: ${err.message}` };
            }
        },
    },
});

// Join session and register tools
try {
    session = await joinSession({
        tools: [
            ...webview.tools,
            {
                name: "youtube_download",
                description:
                    "Download a YouTube video or extract audio. Optionally convert transcript to Markdown/text, including transcript-only mode.",
                parameters: {
                    type: "object",
                    properties: {
                        url: {
                            type: "string",
                            description: "YouTube video URL",
                        },
                        format: {
                            type: "string",
                            enum: ["best", "audio", "mp4", "mkv", "360p", "720p", "1080p"],
                            description: "Download format (default: best)",
                        },
                        outputPath: {
                            type: "string",
                            description: "Directory to save downloaded files",
                        },
                        metadata: {
                            type: "boolean",
                            description: "Save metadata files (JSON, thumbnail, subtitles)",
                            default: true,
                        },
                        transcriptEnabled: {
                            type: "boolean",
                            description: "Download transcript subtitles and convert them to a file",
                            default: false,
                        },
                        transcriptOnly: {
                            type: "boolean",
                            description: "Skip media download and create transcript output only",
                            default: false,
                        },
                        transcriptOutput: {
                            type: "string",
                            enum: ["md", "txt"],
                            description: "Converted transcript output format (default: md)",
                            default: "md",
                        },
                        removeTimestamps: {
                            type: "boolean",
                            description: "Remove subtitle timestamps from converted transcript output",
                            default: true,
                        },
                    },
                    required: ["url", "outputPath"],
                },
                handler: async ({
                    url,
                    format,
                    outputPath,
                    metadata,
                    transcriptEnabled,
                    transcriptOnly,
                    transcriptOutput,
                    removeTimestamps,
                }) => {
                    try {
                        const result = await downloadVideo({
                            url,
                            format: format || "best",
                            outputPath,
                            metadata: metadata !== false,
                            transcriptEnabled: transcriptEnabled === true,
                            transcriptOnly: transcriptOnly === true,
                            transcriptOutput: transcriptOutput || "md",
                            removeTimestamps: removeTimestamps !== false,
                            onProgress: (percent, status) => {
                                if (percent !== null) {
                                    session.log(`[${Math.round(percent)}%] ${status}`);
                                } else {
                                    session.log(status);
                                }
                            },
                        });
                        
                        if (result.success) {
                            const transcriptPath = result.transcript?.outputPath;
                            const transcriptWarning = result.transcript?.warning;
                            if (transcriptPath) {
                                if (transcriptOnly) {
                                    return `✅ Transcript generated: ${transcriptPath}`;
                                }
                                return `✅ Download completed: ${result.filename || "Video saved"}\nTranscript: ${transcriptPath}`;
                            }
                            if (transcriptEnabled && transcriptWarning) {
                                return `✅ Download completed: ${result.filename || "Video saved"}\nTranscript warning: ${transcriptWarning}`;
                            }
                            return `✅ Download completed: ${result.filename || "Video saved"}`;
                        } else {
                            return `❌ Download failed: ${result.error}`;
                        }
                    } catch (err) {
                        return `❌ Error: ${err.message}`;
                    }
                },
            },
        ],
        commands: [
            {
                name: "youtube-download",
                description: "Open the YouTube downloader window",
                handler: async (args) => {
                    // Optional: parse URL from args
                    let url = "";
                    if (args && args.length > 0) {
                        url = args.join(" ").trim();
                    }
                    
                    try {
                        await webview.show();
                        if (url) {
                            // Pre-fill URL in webview
                            await webview.eval(
                                `document.getElementById('url-input') && (document.getElementById('url-input').value = ${JSON.stringify(url)})`,
                            );
                        }
                    } catch (err) {
                        await session.log(`Error opening webview: ${err.message}`);
                    }
                },
            },
        ],
        hooks: {
            onSessionEnd: webview.close,
        },
    });

    await session.log("YouTube Download loaded. Use /youtube-download or youtube_download tool.");
} catch (err) {
    if (String(err?.message || "").includes("joinSession() is intended for extensions running as child processes")) {
        console.error(
            "youtube-download must be launched by Copilot CLI as an extension process. Start Copilot CLI and load this skill instead of running this file directly.",
        );
        process.exitCode = 1;
    } else {
        throw err;
    }
}
