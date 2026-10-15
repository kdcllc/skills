// backend.js - mp3gain subprocess orchestration for mp3-normalize

import { spawn } from "node:child_process";
import { readdir, mkdir, copyFile } from "node:fs/promises";
import { join, extname } from "node:path";

/**
 * Check if mp3gain is available on PATH.
 * Returns true if found, false otherwise.
 */
export async function verifyPrerequisites() {
    return new Promise((resolve) => {
        const proc = spawn("which", ["mp3gain"], { stdio: "ignore" });
        proc.on("close", (code) => resolve(code === 0));
        proc.on("error", () => resolve(false));
    });
}

/**
 * List .mp3 files in a directory (flat, non-recursive).
 * Returns an array of filenames (not full paths).
 */
export async function listMp3Files(dir) {
    const entries = await readdir(dir, { withFileTypes: true });
    return entries
        .filter((e) => e.isFile() && extname(e.name).toLowerCase() === ".mp3")
        .map((e) => e.name);
}

/**
 * Copy MP3 files from sourceDir into sourceDir/normalized/, then run mp3gain on the copies.
 *
 * @param {object} opts
 * @param {string}   opts.sourceDir - Folder containing source MP3 files
 * @param {"track"|"album"} opts.mode - "track" (each file independently) or "album" (relative to each other)
 * @param {number}   opts.targetDb  - Desired loudness in dB (default 89, mp3gain's built-in default)
 * @param {function} opts.onProgress - Called as onProgress(percent|null, statusMessage)
 * @returns {Promise<{success:boolean, outputDir?:string, count?:number, error?:string}>}
 */
export async function normalizeFiles({ sourceDir, mode = "track", targetDb = 89, onProgress }) {
    const files = await listMp3Files(sourceDir);

    if (files.length === 0) {
        return { success: false, error: "No MP3 files found in the selected folder." };
    }

    const outputDir = join(sourceDir, "normalized");
    await mkdir(outputDir, { recursive: true });

    // --- Phase 1: Copy files ---
    onProgress?.(0, `Copying ${files.length} file(s) to normalized/...`);
    for (let i = 0; i < files.length; i++) {
        await copyFile(join(sourceDir, files[i]), join(outputDir, files[i]));
    }
    onProgress?.(10, `Copied ${files.length} file(s). Running mp3gain...`);

    // --- Phase 2: Run mp3gain on the copies ---
    // Offset from mp3gain's hardcoded default of 89 dB.
    // e.g. targetDb=95 → offset=6, passed as -d 6
    const offset = Math.round(targetDb - 89);

    // -c  ignore clipping warnings (don't prompt)
    // -p  preserve original file timestamps
    // -r  track gain: normalize each file independently
    // -a  album gain: normalize all files relative to each other
    // -d N  shift target by N dB from the 89 dB default
    const gainFlag = mode === "album" ? "-a" : "-r";
    const args = ["-c", "-p", gainFlag];
    if (offset !== 0) {
        args.push("-d", String(offset));
    }
    const copiedPaths = files.map((f) => join(outputDir, f));
    args.push(...copiedPaths);

    return new Promise((resolve) => {
        const proc = spawn("mp3gain", args, { stdio: ["ignore", "pipe", "pipe"] });

        let appliedCount = 0;
        let remainder = "";

        const handleData = (data) => {
            remainder += data.toString();
            const lines = remainder.split("\n");
            remainder = lines.pop(); // keep partial last line

            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;

                // "Applying gain change of X dB to filename" signals one file done
                if (trimmed.toLowerCase().includes("applying gain change")) {
                    appliedCount++;
                    const pct = 10 + (appliedCount / files.length) * 90;
                    onProgress?.(Math.min(pct, 99), trimmed);
                } else {
                    // Informational line (analysis header, filename being scanned, etc.)
                    onProgress?.(null, trimmed);
                }
            }
        };

        proc.stdout.on("data", handleData);
        proc.stderr.on("data", handleData);

        proc.on("close", (code) => {
            // Flush any remaining buffered output
            if (remainder.trim()) onProgress?.(null, remainder.trim());

            if (code === 0) {
                onProgress?.(100, `Done! ${files.length} file(s) normalized → ${outputDir}`);
                resolve({ success: true, outputDir, count: files.length });
            } else {
                resolve({ success: false, error: `mp3gain exited with code ${code}` });
            }
        });

        proc.on("error", (err) => {
            resolve({ success: false, error: `Failed to run mp3gain: ${err.message}. Is it installed? Run: sudo apt install mp3gain` });
        });
    });
}
