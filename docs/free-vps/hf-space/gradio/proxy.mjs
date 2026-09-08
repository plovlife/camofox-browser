// Camofox Gradio-Space Reverse-Proxy (null Abhaengigkeiten): eine Tuer (:7860),
// routet / -> camofox-REST, /mcp -> MCP-Streamable-HTTP, /sse+/message -> MCP-SSE.
// Auth: /mcp per Bearer-Header ODER ?key=, /sse+/message nur per Bearer
// (die /message-URL kommt vom Server ohne Query zurueck — nur der Header ueberlebt).
import http from "node:http";

const APP_PORT = parseInt(process.env.APP_PORT || "7860", 10);
const KEY = process.env.CAMOFOX_ACCESS_KEY || "";

function authed(req, url, bearerOnly) {
  if (!KEY) return false;
  const h = req.headers.authorization || "";
  if (h === `Bearer ${KEY}`) return true;
  if (!bearerOnly && url.searchParams.get("key") === KEY) return true;
  return false;
}

function proxy(req, res, target, timeoutMs) {
  const proxyReq = http.request(
    { host: target.host, port: target.port, path: req.url, method: req.method, headers: req.headers },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res, { end: true });
    }
  );
  proxyReq.on("error", (e) => {
    if (!res.headersSent) res.writeHead(502);
    res.end("bad gateway: " + e.message);
  });
  if (timeoutMs > 0) {
    proxyReq.setTimeout(timeoutMs, () => proxyReq.destroy(new Error("upstream timeout")));
  }
  req.pipe(proxyReq, { end: true });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (url.pathname === "/mcp") {
    if (!authed(req, url, false)) {
      res.writeHead(401);
      res.end("mcp key required\n");
      return;
    }
    return proxy(req, res, { host: "127.0.0.1", port: 8001 }, 300000);
  }
  if (url.pathname === "/sse" || url.pathname === "/message") {
    if (!authed(req, url, true)) {
      res.writeHead(401);
      res.end("mcp key required\n");
      return;
    }
    // /sse ist ein ewig offener Stream → kein Upstream-Timeout (0 = aus)
    return proxy(req, res, { host: "127.0.0.1", port: 8002 }, url.pathname === "/sse" ? 0 : 300000);
  }
  return proxy(req, res, { host: "127.0.0.1", port: 9377 }, 300000);
});

server.timeout = 0; // SSE lebt ewig; Timeouts regelt der Proxy pro Upstream
server.listen(APP_PORT, "0.0.0.0", () => console.log(`[proxy] hört auf :${APP_PORT} ✅`));
