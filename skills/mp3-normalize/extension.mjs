// Bootstrapper: Install npm deps if needed, then dynamically import main.mjs
import { bootstrap } from "./scripts/lib/copilot-webview.js";

await bootstrap(import.meta.dirname);
await import("./scripts/main.mjs");
