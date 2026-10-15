// main.mjs - Extension entry point
// Defines callbacks, tool registration, and slash command for MP3 normalization

import { joinSession } from "@github/copilot-sdk/extension";
import { join } from "node:path";
import { CopilotWebview } from "./lib/copilot-webview.js";
import { normalizeFiles, verifyPrerequisites } from "./backend.js";

let session = null;

// Guard against concurrent normalization runs
let running = false;

const webview = new CopilotWebview({
    extensionName: "mp3_normalize",
    contentDir: join(import.meta.dirname, "..", "assets", "content"),
    callbacks: {
        /**
         * Start normalization: copy files to normalized/ and run mp3gain.
         */
        startNormalization: async (sourceDir, mode, targetDb) => {
            if (running) {
                return { error: "Normalization already in progress." };
            }
            if (!sourceDir || !sourceDir.trim()) {
                return { error: "Source folder path is required." };
            }

            const db = Number(targetDb) || 89;
            if (db < 70 || db > 105) {
                return { error: "Target dB must be between 70 and 105." };
            }

            running = true;
            try {
                const result = await normalizeFiles({
                    sourceDir: sourceDir.trim(),
                    mode: mode === "album" ? "album" : "track",
                    targetDb: db,
                    onProgress: (percent, status) => {
                        const update = { percent, status, timestamp: Date.now() };
                        webview
                            .eval(`window.updateProgress && window.updateProgress(${JSON.stringify(update)})`)
                            .catch(() => {});
                    },
                });

                if (result.success) {
                    await session.log(`✅ Normalized ${result.count} file(s) → ${result.outputDir}`);
                } else {
                    await session.log(`❌ Normalization failed: ${result.error}`);
                }
                return result;
            } catch (err) {
                await session.log(`❌ Error: ${err.message}`);
                return { error: err.message };
            } finally {
                running = false;
            }
        },

        /**
         * Cancel: best-effort, mp3gain runs to completion per file.
         */
        cancelNormalization: async () => {
            running = false;
            return { success: true, message: "Cancel requested (current file will finish)." };
        },

        /**
         * Check that mp3gain is installed.
         */
        verifySetup: async () => {
            const ok = await verifyPrerequisites();
            if (!ok) {
                return {
                    ready: false,
                    message: "mp3gain not found. Install with: sudo apt install mp3gain",
                };
            }
            return { ready: true, message: "mp3gain is installed and ready." };
        },

        log: (msg, opts) => session.log(msg, opts),
    },
});

try {
    session = await joinSession({
        tools: [
            ...webview.tools,
            {
                name: "normalize_mp3",
                description:
                    "Normalize or equalize MP3 files in a folder using mp3gain. Copies files to a 'normalized/' subfolder — originals are never modified. Lossless: no re-encoding.",
                parameters: {
                    type: "object",
                    properties: {
                        sourceDir: {
                            type: "string",
                            description: "Absolute path to the folder containing MP3 files to normalize.",
                        },
                        mode: {
                            type: "string",
                            enum: ["track", "album"],
                            description:
                                "track: normalize each file independently to the target dB. album: normalize all files relative to each other (preserves relative loudness differences). Default: track.",
                        },
                        targetDb: {
                            type: "number",
                            description: "Target loudness in dB (70–105). Default is 89 dB (mp3gain standard).",
                        },
                    },
                    required: ["sourceDir"],
                },
                handler: async ({ sourceDir, mode, targetDb }) => {
                    const db = Number(targetDb) || 89;
                    try {
                        const result = await normalizeFiles({
                            sourceDir,
                            mode: mode === "album" ? "album" : "track",
                            targetDb: db,
                            onProgress: (percent, status) => {
                                if (percent !== null) {
                                    session.log(`[${Math.round(percent)}%] ${status}`);
                                } else {
                                    session.log(status);
                                }
                            },
                        });
                        if (result.success) {
                            return `✅ Normalized ${result.count} file(s) → ${result.outputDir}`;
                        } else {
                            return `❌ Failed: ${result.error}`;
                        }
                    } catch (err) {
                        return `❌ Error: ${err.message}`;
                    }
                },
            },
        ],
        commands: [
            {
                name: "mp3-normalize",
                description: "Open the MP3 normalizer window",
                handler: async (args) => {
                    let path = "";
                    if (args && args.length > 0) {
                        path = args.join(" ").trim();
                    }
                    try {
                        await webview.show();
                        if (path) {
                            await webview.eval(
                                `document.getElementById('source-dir') && (document.getElementById('source-dir').value = ${JSON.stringify(path)})`,
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

    await session.log("MP3 Normalize loaded. Use /mp3-normalize or the normalize_mp3 tool.");
} catch (err) {
    if (String(err?.message || "").includes("joinSession() is intended for extensions running as child processes")) {
        console.error(
            "mp3-normalize must be launched by Copilot CLI as an extension process. Start Copilot CLI and load this skill instead of running this file directly.",
        );
        process.exitCode = 1;
    } else {
        throw err;
    }
}
