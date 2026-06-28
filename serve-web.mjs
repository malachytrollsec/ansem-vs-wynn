import { createServer } from "node:http";
import { createHash, createPublicKey, randomBytes, verify } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const projectRoot = new URL(".", import.meta.url).pathname;
const root = process.env.MEMEPIRE_WEB_ROOT || join(projectRoot, "build/web");
const port = Number(process.argv.find((arg) => arg.startsWith("--port="))?.split("=")[1] || process.env.PORT || 8799);
const sockets = new Set();
const roomStreams = new Set();
const roomEvents = new Map();
const latestSnapshots = new Map();
const challenges = new Map();
const walletSessions = new Map();
const roomEventLimit = 80;
const challengeTtlMs = 5 * 60 * 1000;
const sessionTtlMs = 24 * 60 * 60 * 1000;
const ed25519SpkiPrefix = Buffer.from("302a300506032b6570032100", "hex");
const dataDir = process.env.MEMEPIRE_DATA_DIR || join(projectRoot, ".memepire-data");
const leaderboardFile = join(dataDir, "leaderboard.json");
const legacyLeaderboardFile = join(projectRoot, ".memepire-runtime/leaderboard.json");
const leaderboardLimit = 25;
const leaderboardStorageLimit = 80;
const factionsManifestPaths = new Set(["/mempires-factions.json", "/.well-known/mempires-factions.json"]);
const unitKinds = ["villager", "swordsman", "archer", "lancer", "siege"];
const types = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript",
  ".wasm": "application/wasm", ".pck": "application/octet-stream",
  ".png": "image/png", ".json": "application/json", ".ico": "image/x-icon",
};

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);
    if (req.method === "OPTIONS") return noContent(res);
    if (url.pathname === "/room-status") {
      return json(res, roomStatusPayload(sanitizeCode(url.searchParams.get("room"))));
    }
    if (url.pathname === "/room-events") {
      return json(res, roomEventsPayload(sanitizeCode(url.searchParams.get("room")), clampInt(url.searchParams.get("limit") || 40, 1, roomEventLimit)));
    }
    if (url.pathname === "/room-proof") {
      return json(res, roomProofPayload(sanitizeCode(url.searchParams.get("room"))));
    }
    if (url.pathname === "/room-kit") {
      const room = sanitizeCode(url.searchParams.get("room")) || "AVW";
      const player = sanitizeKing(url.searchParams.get("player") || url.searchParams.get("king") || "doge");
      const rival = sanitizeKing(url.searchParams.get("rival") || "pepe");
      return json(res, {
        room,
        game: "Ansem vs Wynn",
        brand: brandPayload(),
        player: kingProfile(player, req),
        rival: kingProfile(rival, req),
        factions: kingsPayload(req),
        arenas: arenasPayload(),
        relayUrl: relayUrl(req),
        roomStreamUrl: `${originUrl(req)}/room-stream?room=${encodeURIComponent(room)}`,
        mempiresFactionsUrl: `${originUrl(req)}/mempires-factions.json?room=${encodeURIComponent(room)}`,
        roomStatusUrl: `${originUrl(req)}/room-status?room=${encodeURIComponent(room)}`,
        roomEventsUrl: `${originUrl(req)}/room-events?room=${encodeURIComponent(room)}`,
        roomProofUrl: `${originUrl(req)}/room-proof?room=${encodeURIComponent(room)}`,
        leaderboardUrl: `${originUrl(req)}/leaderboard`,
        walletChallengeUrl: `${originUrl(req)}/wallet-challenge`,
        walletLoginUrl: `${originUrl(req)}/wallet-login`,
      });
    }
    if (url.pathname === "/room-stream") {
      return handleRoomStream(req, res, url);
    }
    if (factionsManifestPaths.has(url.pathname)) {
      return json(res, factionsPayload(req, url));
    }
    if (url.pathname === "/wallet-challenge") {
      if (req.method !== "POST") return json(res, { error: "method-not-allowed" }, 405);
      const payload = walletChallengePayload(await readJsonBody(req));
      return json(res, payload, payload.ok ? 200 : 400);
    }
    if (url.pathname === "/wallet-login") {
      if (req.method !== "POST") return json(res, { error: "method-not-allowed" }, 405);
      const payload = walletLoginPayload(await readJsonBody(req));
      return json(res, payload, payload.ok ? 200 : 401);
    }
    if (url.pathname === "/leaderboard") {
      if (req.method === "GET") {
        return json(res, leaderboardPayload(await readLeaderboard()));
      }
      if (req.method === "POST") {
        const body = await readJsonBody(req);
        cleanupAuthMaps();
        const rawEntry = body.entry || body;
        const entry = normalizeLeaderboardEntry(rawEntry, verifyLeaderboardWallet(rawEntry, body.walletToken || rawEntry.walletToken));
        const entries = normalizeLeaderboard([entry, ...(await readLeaderboard())]);
        await writeLeaderboard(entries);
        return json(res, { ...leaderboardPayload(entries), submitted: entry });
      }
      return json(res, { error: "method-not-allowed" }, 405);
    }
    let p = decodeURIComponent(url.pathname);
    if (p === "/") p = "/index.html";
    const staticRoot = p.startsWith("/assets/") ? projectRoot : root;
    const f = join(staticRoot, normalize(p));
    if (!f.startsWith(staticRoot)) { res.writeHead(403); return res.end("no"); }
    let body = await readFile(f);
    const headers = {
      "content-type": types[extname(f)] || "application/octet-stream",
      "cache-control": "no-store",
    };
    if (p.endsWith(".html")) {
      const relay = relayUrl(req);
      body = Buffer.from(String(body).replace("</head>", `<script>window.MEMPIRES_ROOM_RELAY=${JSON.stringify(relay)};</script></head>`));
    }
    res.writeHead(200, {
      ...headers,
    });
    res.end(body);
  } catch {
    res.writeHead(404); res.end("not found");
  }
});

server.on("upgrade", (req, socket) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "127.0.0.1"}`);
  if (url.pathname !== "/room") {
    socket.destroy();
    return;
  }
  const key = req.headers["sec-websocket-key"];
  if (!key) {
    socket.destroy();
    return;
  }
  const accept = createHash("sha1")
    .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
    .digest("base64");
  socket.write([
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${accept}`,
    "",
    "",
  ].join("\r\n"));
  socket.roomCode = "";
  socket.role = "";
  socket.from = "";
  socket.identity = {};
  socket.buffer = Buffer.alloc(0);
  sockets.add(socket);
  socket.on("data", (chunk) => readFrames(socket, chunk));
  socket.on("close", () => {
    sockets.delete(socket);
    if (socket.roomCode) {
      const bye = { type: "bye", code: socket.roomCode, role: socket.role, from: socket.from || socket.role };
      recordRoomEvent(socket, bye);
      broadcast(socket, bye);
    }
  });
  socket.on("error", () => sockets.delete(socket));
});

server.listen(port, "127.0.0.1", () => console.log(`memepire web build + room relay on ${port}`));

function json(res, payload, status = 200) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "content-type, accept",
  });
  res.end(JSON.stringify(payload));
}

function noContent(res) {
  res.writeHead(204, {
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "content-type, accept",
  });
  res.end();
}

function relayUrl(req) {
  const host = firstHeaderValue(req.headers["x-forwarded-host"]) || req.headers.host || `127.0.0.1:${port}`;
  const proto = firstHeaderValue(req.headers["x-forwarded-proto"]).toLowerCase() === "https" ? "wss" : "ws";
  return `${proto}://${host}/room`;
}

function originUrl(req) {
  const host = firstHeaderValue(req.headers["x-forwarded-host"]) || req.headers.host || `127.0.0.1:${port}`;
  const proto = firstHeaderValue(req.headers["x-forwarded-proto"]).toLowerCase() === "https" ? "https" : "http";
  return `${proto}://${host}`;
}

function firstHeaderValue(value) {
  if (Array.isArray(value)) return String(value[0] || "").split(",")[0].trim();
  return String(value || "").split(",")[0].trim();
}

function readFrames(socket, chunk) {
  socket.buffer = Buffer.concat([socket.buffer, chunk]);
  while (socket.buffer.length >= 2) {
    const first = socket.buffer[0];
    const second = socket.buffer[1];
    const opcode = first & 0x0f;
    const masked = Boolean(second & 0x80);
    let length = second & 0x7f;
    let offset = 2;
    if (length === 126) {
      if (socket.buffer.length < 4) return;
      length = socket.buffer.readUInt16BE(2);
      offset = 4;
    } else if (length === 127) {
      if (socket.buffer.length < 10) return;
      const high = socket.buffer.readUInt32BE(2);
      const low = socket.buffer.readUInt32BE(6);
      length = high * 2 ** 32 + low;
      offset = 10;
    }
    const maskOffset = masked ? offset : -1;
    const payloadOffset = masked ? offset + 4 : offset;
    if (socket.buffer.length < payloadOffset + length) return;
    const payload = socket.buffer.subarray(payloadOffset, payloadOffset + length);
    let data = payload;
    if (masked) {
      const mask = socket.buffer.subarray(maskOffset, maskOffset + 4);
      data = Buffer.from(payload.map((byte, index) => byte ^ mask[index % 4]));
    }
    socket.buffer = socket.buffer.subarray(payloadOffset + length);
    if (opcode === 0x8) {
      socket.end();
      return;
    }
    if (opcode === 0x1) handleText(socket, data.toString("utf8"));
  }
}

function handleText(socket, text) {
  try {
    const message = JSON.parse(text);
    if (!message || typeof message !== "object") return;
    if (message.type === "join") {
      socket.roomCode = sanitizeCode(message.code);
      socket.role = message.role === "join" ? "join" : "host";
      socket.from = String(message.from || socket.role).slice(0, 48);
      socket.identity = message.identity && typeof message.identity === "object" ? message.identity : {};
      recordRoomEvent(socket, { ...message, code: socket.roomCode, role: socket.role, from: socket.from }, "join");
      send(socket, { type: "relay-ready", code: socket.roomCode, role: socket.role, from: "relay" });
      broadcast(socket, {
        type: "hello",
        code: socket.roomCode,
        role: socket.role,
        from: message.from || socket.role,
        identity: message.identity,
      });
      return;
    }
    const code = sanitizeCode(message.code || socket.roomCode);
    if (!code) return;
    socket.roomCode = code;
    if (!socket.role) socket.role = message.role === "join" ? "join" : "host";
    socket.from = String(message.from || socket.from || socket.role).slice(0, 48);
    if (message.identity && typeof message.identity === "object") socket.identity = message.identity;
    const relayMessage = { ...message, code, role: message.role || socket.role };
    recordRoomEvent(socket, relayMessage);
    if (relayMessage.type === "snapshot" && socket.role === "host") {
      latestSnapshots.set(code, { at: new Date().toISOString(), atMs: Date.now(), snapshot: summarizeSnapshot(relayMessage.snapshot) });
    }
    broadcast(socket, relayMessage);
  } catch {
    send(socket, { type: "relay-error", code: socket.roomCode, reason: "bad-json" });
  }
}

function broadcast(sender, message) {
  for (const socket of sockets) {
    if (socket === sender || socket.destroyed || socket.roomCode !== message.code) continue;
    send(socket, message);
  }
}

function send(socket, message) {
  const payload = Buffer.from(JSON.stringify(message));
  let header;
  if (payload.length < 126) {
    header = Buffer.from([0x81, payload.length]);
  } else if (payload.length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeUInt32BE(0, 2);
    header.writeUInt32BE(payload.length, 6);
  }
  socket.write(Buffer.concat([header, payload]));
}

function sanitizeCode(code) {
  return String(code || "").toUpperCase().replace(/[^A-Z0-9-]/g, "").slice(0, 16);
}

function recordRoomEvent(socket, message, typeOverride = "") {
  const code = sanitizeCode(message.code || socket.roomCode);
  if (!code) return;
  const event = sanitizeRoomEvent(socket, message, typeOverride);
  const events = roomEvents.get(code) || [];
  events.push(event);
  roomEvents.set(code, events.slice(-roomEventLimit));
  publishRoomStreamEvent(code, event);
}

function sanitizeRoomEvent(socket, message, typeOverride = "") {
  const type = String(typeOverride || message.type || "").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 24);
  const identity = message.identity && typeof message.identity === "object" ? message.identity : socket.identity || {};
  const intent = message.intent && typeof message.intent === "object" ? message.intent : {};
  const snapshot = message.snapshot && typeof message.snapshot === "object" ? message.snapshot : {};
  const wager = message.wager && typeof message.wager === "object" ? message.wager : {};
  const wagerWallet = cleanWallet(wager.wallet);
  const wagerVerified = Boolean(wager.verified && wagerWallet);
  const wagerUnit = normalizeWagerUnit(wager.unit || wager.wagerUnit, wagerVerified);
  const safeWager = type.startsWith("wager-") ? {
    ticketId: String(wager.ticketId || "").replace(/[^A-Z0-9._:-]/gi, "").slice(0, 80),
    wagerStatus: String(wager.wagerStatus || "").replace(/[^a-z-]/gi, "").slice(0, 24),
    unit: wagerUnit,
    wagerUnit,
    ticketMode: wagerUnit === "SOL" ? "sol" : "ticket",
    verified: wagerVerified,
    wallet: wagerVerified ? wagerWallet : "",
    walletLabel: cleanString(wager.walletLabel || (wagerVerified ? shortWallet(wagerWallet) : "Ticket mode"), 48),
    stake: roundMoney(wager.stake, 0, 1000000),
    tax: roundMoney(wager.tax, 0, 1000000),
    net: roundMoney(wager.net, 0, 1000000),
    winPayout: roundMoney(wager.winPayout, 0, 2000000),
    fromKing: String(wager.fromKing || "").replace(/[^a-z0-9_-]/gi, "").slice(0, 32),
    fromLabel: String(wager.fromLabel || "").slice(0, 48),
  } : undefined;
  return {
    at: new Date().toISOString(),
    atMs: Date.now(),
    type,
    code: sanitizeCode(message.code || socket.roomCode),
    role: message.role === "join" || socket.role === "join" ? "join" : "host",
    from: String(message.from || socket.from || socket.role || "").slice(0, 48),
    label: String(identity.label || message.from || socket.from || socket.role || "peer").slice(0, 48),
    king: String(identity.king || snapshot.kingId || snapshot.playerId || "").slice(0, 32),
    side: String(message.side || intent.side || identity.side || "").slice(0, 24),
    action: String(intent.action || message.action || "").slice(0, 32),
    unit: String(intent.unit || "").slice(0, 32),
    structure: String(intent.structure || "").slice(0, 32),
    intentId: String(message.intentId || intent.id || "").slice(0, 80),
    accepted: message.type === "intent-result" ? Boolean(message.accepted) : undefined,
    reason: String(message.reason || "").slice(0, 120),
    summary: String(message.thought?.summary || message.summary || "").slice(0, 180),
    wager: safeWager,
    snapshot: type === "snapshot" ? summarizeSnapshot(snapshot) : undefined,
  };
}

function summarizeSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    started: Boolean(snapshot.started),
    over: Boolean(snapshot.over),
    result: String(snapshot.result || "").replace(/[^a-z-]/gi, "").slice(0, 24),
    time: String(snapshot.time || "00:00").slice(0, 16),
    seconds: clampInt(snapshot.seconds || 0, 0, 86400),
    wave: clampInt(snapshot.wave || 0, 0, 999),
    kills: clampInt(snapshot.kills || 0, 0, 99999),
    units: Array.isArray(snapshot.units) ? snapshot.units.length : 0,
    structures: Array.isArray(snapshot.structures) ? snapshot.structures.length : 0,
    player: String(snapshot.player || "").slice(0, 48),
    playerId: String(snapshot.playerId || "").slice(0, 32),
    rival: String(snapshot.rival || "").slice(0, 48),
    rivalId: String(snapshot.rivalId || "").slice(0, 32),
    resources: summarizeResources(snapshot.resources),
    rivalResources: summarizeResources(snapshot.rivalResources),
    pop: summarizePop(snapshot.pop),
    rivalPop: summarizePop(snapshot.rivalPop),
    upgrades: summarizeUpgrades(snapshot.upgrades),
    rivalUpgrades: summarizeUpgrades(snapshot.rivalUpgrades),
    wager: summarizeWager(snapshot.wager),
  };
}

function summarizeResources(resources) {
  const data = resources && typeof resources === "object" ? resources : {};
  return {
    food: clampInt(data.food || 0, 0, 1000000),
    timber: clampInt(data.timber || 0, 0, 1000000),
    memp: clampInt(data.memp || 0, 0, 1000000),
  };
}

function summarizePop(pop) {
  const data = pop && typeof pop === "object" ? pop : {};
  return {
    live: clampInt(data.live || 0, 0, 10000),
    queued: clampInt(data.queued || 0, 0, 10000),
    cap: clampInt(data.cap || 0, 0, 10000),
  };
}

function summarizeUpgrades(upgrades) {
  const data = upgrades && typeof upgrades === "object" ? upgrades : {};
  return {
    atk: clampInt(data.atk || 0, 0, 999),
    armor: clampInt(data.armor || 0, 0, 999),
    eco: clampInt(data.eco || 0, 0, 999),
    forge: Boolean(data.forge),
  };
}

function summarizeWager(wager) {
  const data = wager && typeof wager === "object" ? wager : {};
  const wallet = cleanWallet(data.wallet);
  const verified = Boolean(data.verified && wallet);
  const wagerUnit = normalizeWagerUnit(data.unit || data.wagerUnit, verified);
  return {
    unit: wagerUnit,
    wagerUnit,
    ticketMode: wagerUnit === "SOL" ? "sol" : "ticket",
    verified,
    wallet: verified ? wallet : "",
    walletLabel: cleanString(data.walletLabel || (verified ? shortWallet(wallet) : "Ticket mode"), 48),
    stake: roundMoney(data.stake, 0, 1000000),
    tax: roundMoney(data.tax, 0, 1000000),
    net: roundMoney(data.net, 0, 1000000),
    winPayout: roundMoney(data.winPayout, 0, 2000000),
  };
}

function roomStatusPayload(filterCode = "") {
  const codes = filterCode ? [filterCode] : Array.from(new Set([...roomEvents.keys(), ...Array.from(sockets).map((s) => s.roomCode).filter(Boolean)])).sort();
  const rooms = codes.map((code) => {
    const peers = Array.from(sockets)
      .filter((socket) => socket.roomCode === code && !socket.destroyed)
      .map((socket) => ({
        role: socket.role || "",
        from: socket.from || socket.role || "",
        label: String(socket.identity?.label || socket.from || socket.role || "peer").slice(0, 48),
        king: String(socket.identity?.king || "").slice(0, 32),
      }));
    return {
      code,
      peerCount: peers.length,
      hostOnline: peers.some((peer) => peer.role === "host"),
      joinerCount: peers.filter((peer) => peer.role === "join").length,
      peers,
      latestSnapshot: latestSnapshots.get(code)?.snapshot || null,
    };
  }).filter((room) => filterCode || room.peerCount > 0);
  return { updatedAt: new Date().toISOString(), roomCount: rooms.length, rooms };
}

function roomEventsPayload(filterCode = "", limit = 40) {
  const codes = filterCode ? [filterCode] : Array.from(roomEvents.keys()).sort();
  const now = Date.now();
  const rooms = codes.map((code) => {
    const events = (roomEvents.get(code) || []).slice(-limit).map(({ atMs, ...event }) => ({
      ...event,
      age: clampInt((now - atMs) / 1000, 0, 86400),
    }));
    return { code, eventCount: events.length, events };
  }).filter((room) => filterCode || room.eventCount > 0);
  return { updatedAt: new Date(now).toISOString(), roomCount: rooms.length, rooms };
}

function handleRoomStream(req, res, url) {
  const room = sanitizeCode(url.searchParams.get("room")) || "MEMES";
  const limit = clampInt(url.searchParams.get("limit") || roomEventLimit, 0, roomEventLimit);
  const replay = (roomEvents.get(room) || []).slice(-limit);
  res.writeHead(200, {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-store",
    "connection": "keep-alive",
    "access-control-allow-origin": "*",
  });
  writeSse(res, "room-ready", { room, replayed: replay.length, updatedAt: new Date().toISOString() });
  for (const event of replay) writeSse(res, event.type || "message", event);
  const stream = { room, res };
  roomStreams.add(stream);
  req.on("close", () => roomStreams.delete(stream));
}

function publishRoomStreamEvent(room, event) {
  for (const stream of Array.from(roomStreams)) {
    if (stream.room !== room || stream.res.destroyed) {
      if (stream.res.destroyed) roomStreams.delete(stream);
      continue;
    }
    writeSse(stream.res, event.type || "message", event);
  }
}

function writeSse(res, event, payload) {
  res.write(`event: ${String(event || "message").replace(/[^a-zA-Z0-9_-]/g, "") || "message"}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function roomProofPayload(filterCode = "") {
  const status = roomStatusPayload(filterCode);
  const codes = filterCode ? [filterCode] : Array.from(new Set([...status.rooms.map((room) => room.code), ...roomEvents.keys()])).sort();
  const rooms = codes.map((code) => {
    const statusRoom = status.rooms.find((room) => room.code === code) || { peerCount: 0, peers: [] };
    const events = roomEvents.get(code) || [];
    const snapshots = events.filter((event) => event.type === "snapshot");
    const intents = events.filter((event) => event.type === "intent");
    const results = events.filter((event) => event.type === "intent-result" && event.role === "host");
    const accepted = results.filter((event) => event.accepted);
    const wagerOffers = events.filter((event) => event.type === "wager-offer");
    const wagerReceipts = events.filter((event) => event.type === "wager-receipt");
    const acceptedWagers = wagerReceipts.filter((event) => event.wager?.wagerStatus === "accepted");
    const finishedSnapshots = snapshots.filter((event) => event.snapshot?.over);
    const latestFinishedSnapshot = finishedSnapshots.at(-1)?.snapshot || null;
    const hostReady = statusRoom.hostOnline || events.some((event) => event.type === "snapshot" && event.role === "host");
    const joinReady = statusRoom.joinerCount > 0 || events.some((event) => event.type === "join" && event.role === "join");
    const checks = [
      { id: "host-ready", ok: hostReady },
      { id: "join-ready", ok: joinReady },
      { id: "snapshot", ok: snapshots.length > 0 },
      { id: "final-result", ok: finishedSnapshots.length === 0 || Boolean(latestFinishedSnapshot?.result) },
      { id: "wager-ticket", ok: wagerOffers.length === 0 || acceptedWagers.length > 0 },
      { id: "intent-result", ok: intents.length === 0 || accepted.length > 0 },
    ];
    const ok = checks.every((check) => check.ok);
    return {
      code,
      ok,
      hostReady,
      joinReady,
      peerCount: statusRoom.peerCount || 0,
      snapshotCount: snapshots.length,
      intentCount: intents.length,
      resultCount: results.length,
      acceptedCount: accepted.length,
      wagerOfferCount: wagerOffers.length,
      wagerReceiptCount: wagerReceipts.length,
      acceptedWagerCount: acceptedWagers.length,
      finishedSnapshotCount: finishedSnapshots.length,
      result: latestFinishedSnapshot?.result || "",
      latestSnapshot: latestSnapshots.get(code)?.snapshot || snapshots.at(-1)?.snapshot || null,
      finishedSnapshot: latestFinishedSnapshot,
      checks,
    };
  }).filter((room) => filterCode || room.peerCount > 0 || room.snapshotCount > 0 || room.intentCount > 0 || room.wagerOfferCount > 0);
  return { updatedAt: new Date().toISOString(), ok: rooms.some((room) => room.ok), roomCount: rooms.length, rooms };
}

function factionsPayload(req, url) {
  return {
    version: "mempires-factions-v1",
    game: "Ansem vs Wynn",
    brand: brandPayload(),
    walletAuth: walletAuthPayload(req),
    verifiedLeaderboard: verifiedLeaderboardPayload(req),
    factions: kingsPayload(req),
    arenas: arenasPayload(),
    endpoints: {
      self: `${originUrl(req)}${url.pathname}`,
      roomKitUrl: `${originUrl(req)}/room-kit?room=${encodeURIComponent(sanitizeCode(url.searchParams.get("room")) || "AVW")}`,
      roomStatusUrl: `${originUrl(req)}/room-status?room=${encodeURIComponent(sanitizeCode(url.searchParams.get("room")) || "AVW")}`,
      roomEventsUrl: `${originUrl(req)}/room-events?room=${encodeURIComponent(sanitizeCode(url.searchParams.get("room")) || "AVW")}`,
      roomProofUrl: `${originUrl(req)}/room-proof?room=${encodeURIComponent(sanitizeCode(url.searchParams.get("room")) || "AVW")}`,
      leaderboardUrl: `${originUrl(req)}/leaderboard`,
    },
  };
}

function brandPayload() {
  return {
    version: "mempires-brand-v1",
    name: "Ansem vs Wynn",
    ticker: "AVW",
    chain: "Solana",
    description: "Godot web RTS wager wars with two factions, wallet-backed leaderboards, room relay, and proof streams.",
  };
}

function walletAuthPayload(req) {
  return {
    version: "mempires-wallet-auth-v1",
    challengeUrl: `${originUrl(req)}/wallet-challenge`,
    loginUrl: `${originUrl(req)}/wallet-login`,
    leaderboardUrl: `${originUrl(req)}/leaderboard`,
    challenge: {
      method: "POST",
      body: { address: "<solana-wallet-address>" },
      response: ["address", "nonce", "message", "expiresAt"],
    },
    login: {
      method: "POST",
      body: { address: "<solana-wallet-address>", nonce: "<challenge-nonce>", signature: "<base64-signature>" },
      response: ["address", "token", "verified", "issuedAt", "expiresAt"],
    },
    leaderboard: {
      method: "POST",
      body: { entry: "<leaderboard-entry>", walletToken: "<verified-wallet-token>" },
      tokenField: "walletToken",
      manualFallback: "omit walletToken to submit as an unverified row",
    },
  };
}

function verifiedLeaderboardPayload(req) {
  return {
    version: "mempires-verified-leaderboard-v1",
    leaderboardUrl: `${originUrl(req)}/leaderboard`,
    challengeUrl: `${originUrl(req)}/wallet-challenge`,
    loginUrl: `${originUrl(req)}/wallet-login`,
    walletFlag: "--wallet",
    walletTokenFlag: "--wallet-token",
    walletEnv: "MEMPIRES_KING_WALLET",
    walletTokenEnv: "MEMPIRES_KING_WALLET_TOKEN",
    tokenField: "walletToken",
    submit: {
      method: "POST",
      body: { entry: "<leaderboard-entry>", walletToken: "WALLET_LOGIN_TOKEN" },
    },
  };
}

function kingsPayload(req) {
  return ["doge", "pepe"].map((id) => kingProfile(id, req));
}

function kingProfile(id, req) {
  const clean = sanitizeKing(id);
  const labels = {
    doge: ["ANSEM", "Alien Tape"],
    pepe: ["WYNN", "Predator Bid"],
  };
  const [name, kingdom] = labels[clean] || labels.doge;
  const assetId = clean === "pepe" ? "palestine" : "israel";
  const portrait = `assets/portraits/faction_portrait_${assetId}.png`;
  return {
    id: clean,
    name,
    kingdom,
    portrait,
    portraitUrl: `${originUrl(req)}/${portrait}`,
    units: unitKinds,
    bonus: {
      doge: "alien pressure and tougher frontline trades",
      pepe: "hunter speed and sharper market rotations",
    }[clean],
  };
}

function arenasPayload() {
  return Object.entries({
    meadow: "Market Flats",
    creek: "Liquidity Wadi",
    garden: "Green Candle Grove",
    ruins: "Chart Ruins",
    grove: "Whale Hill",
    crossroads: "Leverage Road",
    pond: "Stoploss Basin",
    courtyard: "Exchange Courtyard",
    orchard: "Exit Liquidity",
    quarry: "Liquidation Pit",
    wildflower: "Pump Field",
    millpond: "Dump Wadi",
    isle: "Perp Dunes",
    festival: "CTO Street",
    causeway: "Bridge Bid",
    bannerfield: "Ticker Line",
  }).map(([id, label]) => ({ id, label }));
}

function sanitizeKing(value) {
  const id = String(value || "").toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 32);
  if (["ansem", "alien", "blknoiz06"].includes(id)) return "doge";
  if (["wynn", "predator", "jameswynnreal"].includes(id)) return "pepe";
  return ["doge", "pepe"].includes(id) ? id : "doge";
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function clampInt(value, min, max) {
  const number = Math.trunc(Number(value) || 0);
  return Math.min(max, Math.max(min, number));
}

function walletChallengePayload(body = {}) {
  cleanupAuthMaps();
  const address = cleanWallet(body.address);
  if (!address) return { ok: false, error: "bad-wallet" };
  const nonce = randomBytes(16).toString("hex");
  const issuedAt = new Date().toISOString();
  const message = [
    "Ansem vs Wynn wallet login",
    `Wallet: ${address}`,
    `Nonce: ${nonce}`,
    `Issued: ${issuedAt}`,
    "Only sign this message for Ansem vs Wynn leaderboard identity.",
  ].join("\n");
  const expiresAtMs = Date.now() + challengeTtlMs;
  challenges.set(nonce, { address, message, expiresAtMs });
  return {
    ok: true,
    address,
    nonce,
    message,
    expiresAt: new Date(expiresAtMs).toISOString(),
  };
}

function walletLoginPayload(body = {}) {
  cleanupAuthMaps();
  const address = cleanWallet(body.address);
  const nonce = cleanString(body.nonce, 64);
  const signature = cleanString(body.signature, 256);
  const challenge = challenges.get(nonce);
  if (!address || !challenge || challenge.address !== address || challenge.expiresAtMs < Date.now()) {
    return { ok: false, error: "challenge-expired" };
  }
  if (!verifySolanaSignature(address, challenge.message, signature)) {
    return { ok: false, error: "bad-signature" };
  }
  challenges.delete(nonce);
  const token = randomBytes(24).toString("base64url");
  const issuedAt = new Date().toISOString();
  const expiresAtMs = Date.now() + sessionTtlMs;
  walletSessions.set(token, { address, token, issuedAt, expiresAtMs });
  return {
    ok: true,
    address,
    token,
    verified: true,
    issuedAt,
    expiresAt: new Date(expiresAtMs).toISOString(),
  };
}

function verifyLeaderboardWallet(entry, token) {
  cleanupAuthMaps();
  const wallet = cleanWallet(entry?.wallet);
  const session = walletSessions.get(cleanString(token, 128));
  if (!wallet || !session || session.expiresAtMs < Date.now() || session.address !== wallet) {
    return { verified: false, address: wallet };
  }
  return { verified: true, address: wallet };
}

function verifySolanaSignature(address, message, signature) {
  try {
    const publicKeyBytes = base58Decode(address);
    const signatureBytes = Buffer.from(String(signature || ""), "base64");
    if (publicKeyBytes.length !== 32 || signatureBytes.length !== 64) return false;
    const key = createPublicKey({ key: Buffer.concat([ed25519SpkiPrefix, publicKeyBytes]), format: "der", type: "spki" });
    return verify(null, Buffer.from(message, "utf8"), key, signatureBytes);
  } catch {
    return false;
  }
}

function cleanupAuthMaps() {
  const now = Date.now();
  for (const [nonce, challenge] of challenges) {
    if (challenge.expiresAtMs < now) challenges.delete(nonce);
  }
  for (const [token, session] of walletSessions) {
    if (session.expiresAtMs < now) walletSessions.delete(token);
  }
}

function cleanWallet(value) {
  const wallet = cleanString(value, 64);
  return /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(wallet) ? wallet : "";
}

function shortWallet(wallet) {
  const clean = cleanWallet(wallet);
  if (clean.length <= 12) return clean;
  return `${clean.slice(0, 4)}...${clean.slice(-4)}`;
}

function normalizeWagerUnit(value, verified = false) {
  return String(value || (verified ? "SOL" : "ticket")).toUpperCase() === "SOL" ? "SOL" : "ticket";
}

function cleanString(value, max = 120) {
  return String(value || "").trim().slice(0, max);
}

function base58Decode(value) {
  const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  let num = 0n;
  for (const char of String(value || "")) {
    const index = alphabet.indexOf(char);
    if (index < 0) throw new Error("bad-base58");
    num = num * 58n + BigInt(index);
  }
  const bytes = [];
  while (num > 0n) {
    bytes.unshift(Number(num & 0xffn));
    num >>= 8n;
  }
  for (const char of String(value || "")) {
    if (char !== "1") break;
    bytes.unshift(0);
  }
  return Buffer.from(bytes);
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const text = Buffer.concat(chunks).toString("utf8");
  if (!text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

async function readLeaderboard() {
  for (const file of [leaderboardFile, legacyLeaderboardFile]) {
    try {
      const data = JSON.parse(await readFile(file, "utf8"));
      return normalizeLeaderboard(data.entries || []);
    } catch (error) {
      if (error?.code && error.code !== "ENOENT") console.warn(`[memepire] leaderboard read skipped: ${error.message}`);
    }
  }
  return [];
}

async function writeLeaderboard(entries) {
  await mkdir(dataDir, { recursive: true });
  await writeFile(
    leaderboardFile,
    `${JSON.stringify({ updatedAt: new Date().toISOString(), entries: entries.slice(0, leaderboardStorageLimit) }, null, 2)}\n`,
  );
}

function leaderboardPayload(entries) {
  const sorted = normalizeLeaderboard(entries);
  return {
    updatedAt: new Date().toISOString(),
    entries: sorted.slice(0, leaderboardLimit),
    wagers: sorted.filter((entry) => Number(entry.stake) > 0 || Number(entry.payout) > 0).slice(0, leaderboardLimit),
  };
}

function normalizeLeaderboard(entries) {
  const unique = new Map();
  for (const item of entries) {
    const entry = normalizeLeaderboardEntry(item);
    if (!entry.id) continue;
    const old = unique.get(entry.id);
    if (!old || scoreSort(entry, old) < 0) unique.set(entry.id, entry);
  }
  return Array.from(unique.values()).sort(scoreSort).slice(0, leaderboardStorageLimit);
}

function normalizeLeaderboardEntry(item = {}, walletAuth = null) {
  const result = String(item.result || (item.won ? "won" : "lost")).toLowerCase() === "won" ? "won" : "lost";
  const stake = roundMoney(item.stake, 0, 1000000);
  const payout = roundMoney(item.payout, 0, 1000000);
  const wave = clampInt(item.wave || 0, 0, 999);
  const kills = clampInt(item.kills || 0, 0, 99999);
  const seconds = clampInt(item.seconds || 0, 0, 86400);
  const score = clampInt(item.score || leaderboardScore({ result, wave, kills, seconds, payout }), 0, 9999999);
  const endedAt = String(item.endedAt || new Date().toISOString()).slice(0, 40);
  const kingId = cleanId(item.kingId || item.king || "doge", "doge");
  const rivalId = cleanId(item.rivalId || item.rivalKing || "pepe", "pepe");
  const id = String(item.id || `${kingId}-${rivalId}-${endedAt}-${result}`).replace(/[^a-zA-Z0-9:._-]/g, "").slice(0, 96);
  const wallet = cleanWallet(item.wallet);
  const verified = walletAuth
    ? Boolean(walletAuth.verified && walletAuth.address === wallet)
    : Boolean(item.verified && wallet);
  const wagerUnit = normalizeWagerUnit(item.wagerUnit || item.unit, verified);
  return {
    id,
    endedAt,
    kingId,
    king: String(item.king || item.kingName || kingId).slice(0, 48),
    rivalId,
    rival: String(item.rival || item.rivalName || rivalId).slice(0, 48),
    result,
    score,
    wave,
    kills,
    seconds,
    time: String(item.time || formatClock(seconds)).slice(0, 16),
    arena: String(item.arena || "meadow").slice(0, 32),
    pressure: String(item.pressure || "standard").slice(0, 32),
    wallet,
    walletLabel: String(item.walletLabel || "").slice(0, 48),
    verified,
    matchVerified: Boolean(item.matchVerified),
    stake,
    tax: roundMoney(item.tax, 0, stake),
    payout,
    wagerUnit,
    ticketMode: wagerUnit === "SOL" ? "sol" : "ticket",
  };
}

function leaderboardScore({ result, wave, kills, seconds, payout }) {
  const finish = result === "won" ? 1000 : 120;
  const timePenalty = Math.floor(seconds / 12);
  return Math.max(1, finish + wave * 80 + kills * 35 + Math.round(payout / 4) - timePenalty);
}

function scoreSort(a, b) {
  return (b.score - a.score) || String(b.endedAt).localeCompare(String(a.endedAt));
}

function roundMoney(value, min = 0, max = Number.MAX_SAFE_INTEGER) {
  const number = Math.round((Number(value) || 0) * 100) / 100;
  return Math.min(max, Math.max(min, number));
}

function cleanId(value, fallback) {
  const id = String(value || "").toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 32);
  return id || fallback;
}

function formatClock(seconds) {
  const total = clampInt(seconds, 0, 86400);
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}
