import { spawn } from "node:child_process";
import { createServer } from "node:net";

const root = new URL("..", import.meta.url).pathname;
const room = `S${Date.now().toString(36).toUpperCase().slice(-6)}`;
const port = await freePort();
const origin = `http://127.0.0.1:${port}`;
const relay = `ws://127.0.0.1:${port}/room`;
const timeoutMs = 12000;

if (typeof WebSocket !== "function") {
  throw new Error("Node WebSocket is unavailable. Use Node 22+.");
}

const server = spawn(process.execPath, ["serve-web.mjs", `--port=${port}`], {
  cwd: root,
  stdio: ["ignore", "pipe", "pipe"],
});

let serverOutput = "";
server.stdout.on("data", (chunk) => (serverOutput += chunk));
server.stderr.on("data", (chunk) => (serverOutput += chunk));

let streamAbort = null;
let host = null;

try {
  await withTimeout(waitForHttp(`${origin}/room-status?room=${room}`), timeoutMs, "server did not start");
  const streamUrl = `${origin}/room-stream?room=${room}`;
  const stream = readRoomStream(streamUrl, 4);
  await withTimeout(stream.ready, timeoutMs, "room-stream did not open");

  host = await connectHost(relay);
  sendHost(host, { type: "join", from: "stream-host", identity: { label: "Stream Host" } });
  sendHost(host, { type: "hello-ack", from: "stream-host", identity: { label: "Stream Host" } });
  sendHost(host, { type: "snapshot", snapshot: proofSnapshot() });

  const events = await withTimeout(stream.done, timeoutMs, "room-stream did not emit expected events");
  const types = events.map((event) => event.data?.type || event.event);
  assert(events.some((event) => event.event === "room-ready"), "room stream missing room-ready");
  assert(types.includes("join") && types.includes("hello-ack") && types.includes("snapshot"), `room stream missing expected event types: ${types.join(", ")}`);

  const proof = await fetchJson(`${origin}/room-proof?room=${room}`);
  const proofRoom = proof.rooms?.[0];
  assert(proofRoom?.hostReady, "room-proof missing host readiness");
  assert(proofRoom?.snapshotCount >= 1, "room-proof missing snapshot count");

  console.log(`[memepire-stream] room stream verified for ${room}`);
} finally {
  try {
    streamAbort?.abort();
  } catch {
    // Ignore cleanup failures.
  }
  try {
    host?.close();
  } catch {
    // Ignore cleanup failures.
  }
  server.kill("SIGTERM");
  await new Promise((resolve) => server.once("exit", resolve)).catch(() => {});
}

function readRoomStream(url, expectedCount) {
  const controller = new AbortController();
  streamAbort = controller;
  const events = [];
  let readyResolve;
  let readyReject;
  let doneResolve;
  let doneReject;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  const done = new Promise((resolve, reject) => {
    doneResolve = resolve;
    doneReject = reject;
  });
  (async () => {
    try {
      const response = await fetch(url, { headers: { accept: "text/event-stream" }, signal: controller.signal });
      if (!response.ok || !String(response.headers.get("content-type") || "").includes("text/event-stream")) {
        throw new Error(`room-stream HTTP ${response.status} ${response.headers.get("content-type") || ""}`);
      }
      readyResolve(true);
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      for (;;) {
        const { value, done: ended } = await reader.read();
        if (ended) break;
        buffer += decoder.decode(value, { stream: true });
        let splitIndex = buffer.indexOf("\n\n");
        while (splitIndex >= 0) {
          const raw = buffer.slice(0, splitIndex);
          buffer = buffer.slice(splitIndex + 2);
          const parsed = parseSseEvent(raw);
          if (parsed) {
            events.push(parsed);
            if (events.length >= expectedCount) {
              controller.abort();
              doneResolve(events);
              return;
            }
          }
          splitIndex = buffer.indexOf("\n\n");
        }
      }
    } catch (error) {
      if (error.name === "AbortError" && events.length >= expectedCount) return;
      readyReject(error);
      doneReject(error);
    }
  })();
  return { ready, done };
}

function parseSseEvent(raw) {
  const lines = String(raw || "").split(/\r?\n/);
  if (!lines.some((line) => line.startsWith("data:"))) return null;
  const event = lines.find((line) => line.startsWith("event:"))?.slice(6).trim() || "message";
  const data = lines
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trimStart())
    .join("\n");
  return { event, data: data ? JSON.parse(data) : null };
}

function connectHost(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.addEventListener("open", () => resolve(socket));
    socket.addEventListener("error", () => reject(new Error("host websocket failed")));
  });
}

function sendHost(socket, message) {
  socket.send(JSON.stringify({ code: room, role: "host", ...message }));
}

function proofSnapshot() {
  return {
    matchId: `stream-${room}`,
    started: true,
    over: false,
    player: "ANSEM",
    playerId: "doge",
    rival: "WYNN",
    rivalId: "pepe",
    time: "00:12",
    seconds: 12,
    wave: 1,
    kills: 0,
    resources: { food: 260, timber: 230, memp: 60 },
    rivalResources: { food: 260, timber: 230, memp: 60 },
    units: [{ id: 1 }, { id: 2 }],
    structures: [{ id: 3 }],
  };
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { accept: "application/json" } });
  if (!response.ok) throw new Error(`${url} HTTP ${response.status}: ${await response.text()}`);
  return response.json();
}

async function waitForHttp(url) {
  const deadline = Date.now() + 8000;
  let last = "";
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
      last = `HTTP ${response.status}`;
    } catch (error) {
      last = error.message;
    }
    await delay(100);
  }
  throw new Error(`server did not become ready: ${last}\n${serverOutput}`);
}

function freePort() {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.unref();
    probe.on("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const address = probe.address();
      probe.close(() => resolve(address.port));
    });
  });
}

function withTimeout(promise, ms, label) {
  let timer = null;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label}\nserver:\n${serverOutput.trim()}`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function assert(ok, message) {
  if (!ok) throw new Error(message);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
