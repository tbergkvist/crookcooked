import { readFile } from "node:fs/promises";
import http from "node:http";
import { WebSocketServer } from "ws";
import { RoomBroker } from "./broker.mjs";
import { APNsClient } from "./apns.mjs";

const port = Number.parseInt(process.env.PORT ?? "8787", 10);
const host = process.env.HOST ?? "127.0.0.1";
const apns = new APNsClient();
const broker = new RoomBroker({ onAlert: (tokens, kind) => apns.alert(tokens, kind) });

// The phone web client. Only these exact paths are served; nothing is read
// from a path taken from the request.
const publicDirectory = new URL("../public/", import.meta.url);
const modules = new URL("../node_modules/@noble/", import.meta.url);
const staticFiles = new Map([
  ["/", [new URL("index.html", publicDirectory), "text/html; charset=utf-8"]],
  ["/app.js", [new URL("app.js", publicDirectory), "text/javascript; charset=utf-8"]],
  ["/pairing.js", [new URL("pairing.js", publicDirectory), "text/javascript; charset=utf-8"]],
  ["/app.css", [new URL("app.css", publicDirectory), "text/css; charset=utf-8"]],
  ["/manifest.webmanifest", [new URL("manifest.webmanifest", publicDirectory), "application/manifest+json"]],
  ["/favicon.png", [new URL("favicon.png", publicDirectory), "image/png"]],
  ["/apple-touch-icon.png", [new URL("apple-touch-icon.png", publicDirectory), "image/png"]],
  ["/icon-512.png", [new URL("icon-512.png", publicDirectory), "image/png"]],
]);
const vendorModules = {
  ciphers: ["chacha.js", "_arx.js", "_poly1305.js", "utils.js"],
  hashes: ["sha2.js", "_md.js", "_u64.js", "utils.js"],
};
for (const [pkg, files] of Object.entries(vendorModules)) {
  for (const file of files) {
    staticFiles.set(`/vendor/${pkg}/${file}`, [new URL(`${pkg}/${file}`, modules), "text/javascript; charset=utf-8"]);
  }
}

const securityHeaders = {
  "content-security-policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob:; media-src blob:; connect-src 'self' ws: wss:; manifest-src 'self'; base-uri 'none'; frame-ancestors 'none'",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};

const server = http.createServer(async (request, response) => {
  const path = new URL(request.url ?? "/", "http://relay").pathname;
  if (path === "/health") {
    response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
    return response.end(JSON.stringify({ ok: true }));
  }
  const file = request.method === "GET" || request.method === "HEAD" ? staticFiles.get(path) : undefined;
  if (!file) return response.writeHead(404).end();
  try {
    const body = await readFile(file[0]);
    response.writeHead(200, { ...securityHeaders, "content-type": file[1], "cache-control": "no-store" });
    response.end(request.method === "HEAD" ? undefined : body);
  } catch {
    response.writeHead(500).end();
  }
});

const websocketServer = new WebSocketServer({ server, maxPayload: 32 * 1024 * 1024, perMessageDeflate: false });
websocketServer.on("connection", socket => broker.attach(socket));

server.listen(port, host, () => {
  console.log(`Crookcooked relay listening on http://${host}:${port}`);
  console.log(`APNs notifications ${apns.enabled ? "enabled" : "disabled (no credentials configured)"}`);
});

function shutdown() {
  websocketServer.clients.forEach(client => client.close(1001, "server shutdown"));
  server.close(() => process.exit(0));
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
