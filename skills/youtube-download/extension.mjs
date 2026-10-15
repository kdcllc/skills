// Bootstrapper: Install npm deps if needed, then dynamically import main.mjs
// This pattern ensures npm packages are available before importing them
import { bootstrap } from "./scripts/lib/copilot-webview.js";

await bootstrap(import.meta.dirname);
await import("./scripts/main.mjs");
