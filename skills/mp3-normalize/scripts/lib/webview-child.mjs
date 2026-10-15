// lib/webview-child.mjs - Child process that hosts the native webview window
// DO NOT EDIT - copy this file verbatim from copilot-webview-creator template

import { Application } from "@webviewjs/webview";

const { CW_URL, CW_TITLE, CW_WIDTH, CW_HEIGHT } = process.env;
const app = new Application();
const win = app.createBrowserWindow({ title: CW_TITLE, width: +CW_WIDTH, height: +CW_HEIGHT });
win.createWebview({ url: CW_URL, enableDevtools: true });
app.run();
