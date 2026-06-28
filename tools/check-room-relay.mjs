import { spawn } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { once } from "node:events";
import net from "node:net";

const root = new URL("..", import.meta.url).pathname;
const port = Number(process.env.MEMEPIRE_TEST_PORT || 8899);
const room = `T${Date.now().toString(36).toUpperCase().slice(-6)}`;
const hostWallet = "So11111111111111111111111111111111111111112";

const server = spawn(process.execPath, ["serve-web.mjs", `--port=${port}`], {
  cwd: root,
  stdio: ["ignore", "pipe", "pipe"],
});

let serverOutput = "";
server.stdout.on("data", (chunk) => (serverOutput += chunk));
server.stderr.on("data", (chunk) => (serverOutput += chunk));

try {
  await waitForHttp(`http://127.0.0.1:${port}/room-kit?room=${room}`);
  const host = await openWs({ role: "host", from: "host", label: "ANSEM", king: "doge" });
  const joiner = await openWs({ role: "join", from: "join", label: "WYNN", king: "pepe" });

  await host.waitFor((msg) => msg.type === "hello" && msg.from === "join");
  host.send({ type: "hello-ack", identity: { label: "ANSEM", king: "doge" } });
  await joiner.waitFor((msg) => msg.type === "hello-ack" && msg.from === "host");

  host.send({
    type: "wager-offer",
    wager: {
      ticketId: `${room}-ticket`,
      wagerStatus: "open",
      unit: "SOL",
      wagerUnit: "SOL",
      ticketMode: "sol",
      verified: true,
      wallet: hostWallet,
      walletLabel: "So11...1112",
      stake: 250,
      tax: 13,
      net: 237,
      winPayout: 450,
      fromKing: "doge",
      fromLabel: "ANSEM",
    },
  });
  const relayedOffer = await joiner.waitFor((msg) => msg.type === "wager-offer" && msg.wager?.ticketId === `${room}-ticket`);
  assert(relayedOffer.wager?.unit === "SOL" && relayedOffer.wager?.wagerUnit === "SOL", "relayed wager offer lost SOL unit");
  assert(relayedOffer.wager?.verified === true && relayedOffer.wager?.walletLabel === "So11...1112", "relayed wager offer lost verified wallet label");
  joiner.send({
    type: "wager-receipt",
    wager: {
      ticketId: `${room}-ticket`,
      wagerStatus: "accepted",
      unit: "SOL",
      wagerUnit: "SOL",
      ticketMode: "sol",
      verified: true,
      wallet: hostWallet,
      walletLabel: "So11...1112",
      stake: 250,
      tax: 13,
      net: 237,
      winPayout: 450,
      fromKing: "pepe",
      fromLabel: "WYNN",
    },
  });
  await host.waitFor((msg) => msg.type === "wager-receipt" && msg.wager?.wagerStatus === "accepted");

  host.send({
    type: "snapshot",
    snapshot: {
      started: true,
      over: false,
      result: "",
      time: "00:07",
      seconds: 7,
      wave: 0,
      kills: 1,
      player: "ANSEM",
      playerId: "doge",
      rival: "WYNN",
      rivalId: "pepe",
      resources: { food: 260, timber: 180, memp: 50 },
      rivalResources: { food: 240, timber: 120, memp: 30 },
      pop: { live: 4, queued: 1, cap: 20 },
      rivalPop: { live: 3, queued: 0, cap: 20 },
      upgrades: { atk: 1, armor: 0, eco: 2, forge: true },
      rivalUpgrades: { atk: 0, armor: 1, eco: 1, forge: false },
      wager: { unit: "SOL", wagerUnit: "SOL", ticketMode: "sol", verified: true, wallet: hostWallet, walletLabel: "So11...1112", stake: 250, tax: 13, net: 237, winPayout: 450 },
      units: [{ id: 1 }, { id: 2 }],
      structures: [{ id: 3 }],
    },
  });
  await joiner.waitFor((msg) => msg.type === "snapshot");

  host.send({
    type: "snapshot",
    snapshot: {
      started: true,
      over: true,
      result: "won",
      time: "00:42",
      seconds: 42,
      wave: 1,
      kills: 3,
      player: "ANSEM",
      playerId: "doge",
      rival: "WYNN",
      rivalId: "pepe",
      resources: { food: 310, timber: 205, memp: 75 },
      rivalResources: { food: 90, timber: 45, memp: 10 },
      pop: { live: 5, queued: 0, cap: 26 },
      rivalPop: { live: 2, queued: 0, cap: 20 },
      upgrades: { atk: 2, armor: 1, eco: 3, forge: true },
      rivalUpgrades: { atk: 1, armor: 1, eco: 1, forge: true },
      wager: { unit: "SOL", wagerUnit: "SOL", ticketMode: "sol", verified: true, wallet: hostWallet, walletLabel: "So11...1112", stake: 250, tax: 13, net: 237, winPayout: 450 },
      units: [{ id: 1 }, { id: 2 }],
      structures: [{ id: 3 }],
    },
  });
  await joiner.waitFor((msg) => msg.type === "snapshot" && msg.snapshot?.over);

  joiner.send({
    type: "intent",
    side: "rival",
    intent: { id: "intent-1", action: "attack", side: "rival" },
  });
  await host.waitFor((msg) => msg.type === "intent" && msg.intent?.id === "intent-1");

  host.send({
    type: "intent-result",
    intentId: "intent-1",
    action: "attack",
    side: "rival",
    accepted: true,
    reason: "accepted",
  });
  await joiner.waitFor((msg) => msg.type === "intent-result" && msg.intentId === "intent-1");

  const [status, events, proof] = await Promise.all([
    fetchJson(`/room-status?room=${room}`),
    fetchJson(`/room-events?room=${room}&limit=20`),
    fetchJson(`/room-proof?room=${room}`),
  ]);

  const statusRoom = status.rooms?.[0];
  const eventRoom = events.rooms?.[0];
  const proofRoom = proof.rooms?.[0];
  assert(statusRoom?.hostOnline, "room-status missing host");
  assert(statusRoom?.joinerCount >= 1, "room-status missing joiner");
  assert(statusRoom?.latestSnapshot?.units === 2, "room-status missing latest snapshot summary");
  assert(statusRoom?.latestSnapshot?.over && statusRoom.latestSnapshot.result === "won", "room-status missing final result snapshot");
  assert(statusRoom?.latestSnapshot?.resources?.food === 310, "room-status missing player resources");
  assert(statusRoom?.latestSnapshot?.rivalResources?.food === 90, "room-status missing rival resources");
  assert(statusRoom?.latestSnapshot?.pop?.cap === 26, "room-status missing player population");
  assert(statusRoom?.latestSnapshot?.rivalPop?.live === 2, "room-status missing rival population");
  assert(statusRoom?.latestSnapshot?.upgrades?.atk === 2, "room-status missing player upgrades");
  assert(statusRoom?.latestSnapshot?.rivalUpgrades?.forge === true, "room-status missing rival upgrades");
  assert(statusRoom?.latestSnapshot?.wager?.stake === 250, "room-status missing wager summary");
  assert(statusRoom?.latestSnapshot?.wager?.wagerUnit === "SOL", "room-status missing SOL wager unit");
  assert(statusRoom?.latestSnapshot?.wager?.walletLabel === "So11...1112", "room-status missing wager wallet label");
  assert(eventRoom?.events?.some((event) => event.type === "intent" && event.action === "attack"), "room-events missing attack intent");
  assert(eventRoom?.events?.some((event) => event.type === "intent-result" && event.accepted), "room-events missing accepted result");
  assert(eventRoom?.events?.some((event) => event.type === "wager-offer" && event.wager?.stake === 250 && event.wager?.wagerUnit === "SOL"), "room-events missing SOL wager offer");
  assert(eventRoom?.events?.some((event) => event.type === "wager-receipt" && event.wager?.wagerStatus === "accepted" && event.wager?.wagerUnit === "SOL"), "room-events missing accepted SOL wager receipt");
  assert(proof.ok && proofRoom?.ok, "room-proof should be ok");
  assert(proofRoom.checks?.every((check) => check.ok), "room-proof ok must require every proof check");
  assert(proofRoom.snapshotCount >= 1, "room-proof missing snapshot count");
  assert(proofRoom.finishedSnapshotCount >= 1 && proofRoom.result === "won", "room-proof missing final result");
  assert(proofRoom.finishedSnapshot?.rivalResources?.food === 90, "room-proof missing finished rival resources");
  assert(proofRoom.finishedSnapshot?.rivalPop?.live === 2, "room-proof missing finished rival population");
  assert(proofRoom.finishedSnapshot?.rivalUpgrades?.forge === true, "room-proof missing finished rival upgrades");
  assert(proofRoom.finishedSnapshot?.wager?.winPayout === 450, "room-proof missing finished wager payout");
  assert(proofRoom.finishedSnapshot?.wager?.wagerUnit === "SOL", "room-proof missing finished SOL wager unit");
  assert(proofRoom.acceptedCount >= 1, "room-proof missing accepted count");
  assert(proofRoom.acceptedWagerCount >= 1, "room-proof missing accepted wager count");

  const leaderboardEntry = {
    id: `${room}-result`,
    kingId: "doge",
    king: "ANSEM",
    rivalId: "pepe",
    rival: "WYNN",
    result: "won",
    wave: 99,
    kills: 999,
    seconds: 123,
    arena: "meadow",
    pressure: "standard",
    wagerUnit: "SOL",
    stake: 250,
    tax: 13,
    payout: 1000000,
  };
  const submitted = await postJson("/leaderboard", { entry: leaderboardEntry });
  const leaderboard = await fetchJson("/leaderboard");
  assert(submitted.submitted?.id === leaderboardEntry.id, "leaderboard did not echo submitted entry");
  assert(leaderboard.entries?.some((entry) => entry.id === leaderboardEntry.id && entry.score > 0), "leaderboard missing submitted entry");
  assert(leaderboard.wagers?.some((entry) => entry.id === leaderboardEntry.id), "leaderboard missing wager entry");

  host.close();
  joiner.close();

  const staleTicketRoom = `${room}X`;
  const staleHost = await openWs({ roomCode: staleTicketRoom, role: "host", from: "host", label: "ANSEM", king: "doge" });
  const staleJoiner = await openWs({ roomCode: staleTicketRoom, role: "join", from: "join", label: "WYNN", king: "pepe" });
  await staleHost.waitFor((msg) => msg.type === "hello" && msg.from === "join");
  staleHost.send({
    type: "wager-offer",
    wager: {
      ticketId: `${staleTicketRoom}-ticket`,
      wagerStatus: "open",
      stake: 999,
      tax: 50,
      net: 949,
      winPayout: 1803,
      fromKing: "doge",
      fromLabel: "ANSEM",
    },
  });
  await staleJoiner.waitFor((msg) => msg.type === "wager-offer" && msg.wager?.ticketId === `${staleTicketRoom}-ticket`);
  staleHost.send({
    type: "snapshot",
    snapshot: {
      started: true,
      over: false,
      result: "",
      time: "00:09",
      seconds: 9,
      wave: 0,
      player: "ANSEM",
      playerId: "doge",
      rival: "WYNN",
      rivalId: "pepe",
      units: [{ id: 1 }],
      structures: [{ id: 2 }],
    },
  });
  await staleJoiner.waitFor((msg) => msg.type === "snapshot");
  const staleProof = await fetchJson(`/room-proof?room=${staleTicketRoom}`);
  const staleProofRoom = staleProof.rooms?.[0];
  assert(staleProof.ok === false && staleProofRoom?.ok === false, "room-proof should reject unaccepted wager tickets");
  assert(staleProofRoom.checks?.some((check) => check.id === "wager-ticket" && check.ok === false), "room-proof missing failed wager-ticket check");
  staleHost.close();
  staleJoiner.close();

  console.log(`[memepire-room] relay/status/events/proof/leaderboard verified for ${room}`);
} finally {
  await stopServer();
}

async function fetchJson(path) {
  const response = await fetch(`http://127.0.0.1:${port}${path}`);
  if (!response.ok) throw new Error(`${path} HTTP ${response.status}`);
  return response.json();
}

async function postJson(path, body) {
  const response = await fetch(`http://127.0.0.1:${port}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${path} HTTP ${response.status}`);
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

async function openWs({ roomCode = room, role, from, label, king }) {
  const socket = net.createConnection(port, "127.0.0.1");
  await once(socket, "connect");
  const key = randomBytes(16).toString("base64");
  socket.write([
    "GET /room HTTP/1.1",
    `Host: 127.0.0.1:${port}`,
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Key: ${key}`,
    "Sec-WebSocket-Version: 13",
    "",
    "",
  ].join("\r\n"));

  let buffer = Buffer.alloc(0);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("websocket handshake timeout")), 5000);
    const onData = (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      const idx = buffer.indexOf("\r\n\r\n");
      if (idx < 0) return;
      const header = buffer.subarray(0, idx).toString("utf8");
      const expected = createHash("sha1").update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest("base64");
      if (!header.includes("101 Switching Protocols") || !header.includes(`Sec-WebSocket-Accept: ${expected}`)) {
        reject(new Error(`bad websocket handshake:\n${header}`));
        return;
      }
      clearTimeout(timer);
      socket.off("data", onData);
      buffer = buffer.subarray(idx + 4);
      resolve();
    };
    socket.on("data", onData);
  });

  const messages = [];
  const waiters = [];
  socket.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    for (;;) {
      const frame = readServerFrame();
      if (!frame) return;
      messages.push(frame);
      for (const waiter of waiters.splice(0)) waiter();
    }
  });
  if (buffer.length) {
    const queued = buffer;
    buffer = Buffer.alloc(0);
    socket.emit("data", queued);
  }

  const client = {
    send(payload) {
      writeClientFrame(socket, { ...payload, code: roomCode, role, from });
    },
    async waitFor(predicate, label = "message") {
      const deadline = Date.now() + 5000;
      while (Date.now() < deadline) {
        const match = messages.find(predicate);
        if (match) return match;
        await new Promise((resolve) => {
          const timer = setTimeout(resolve, 100);
          waiters.push(() => {
            clearTimeout(timer);
            resolve();
          });
        });
      }
      throw new Error(`${role} timed out waiting for ${label}; saw ${JSON.stringify(messages)}`);
    },
    close() {
      socket.destroy();
    },
  };
  client.send({ type: "join", identity: { label, king } });
  await client.waitFor((msg) => msg.type === "relay-ready", "relay-ready");
  return client;

  function readServerFrame() {
    if (buffer.length < 2) return null;
    const first = buffer[0];
    const opcode = first & 0x0f;
    let length = buffer[1] & 0x7f;
    let offset = 2;
    if (length === 126) {
      if (buffer.length < 4) return null;
      length = buffer.readUInt16BE(2);
      offset = 4;
    } else if (length === 127) {
      if (buffer.length < 10) return null;
      length = buffer.readUInt32BE(6);
      offset = 10;
    }
    if (buffer.length < offset + length) return null;
    const payload = buffer.subarray(offset, offset + length);
    buffer = buffer.subarray(offset + length);
    if (opcode !== 0x1) return null;
    return JSON.parse(payload.toString("utf8"));
  }
}

function writeClientFrame(socket, payload) {
  const data = Buffer.from(JSON.stringify(payload));
  const mask = randomBytes(4);
  let header;
  if (data.length < 126) {
    header = Buffer.from([0x81, 0x80 | data.length]);
  } else if (data.length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 0x80 | 126;
    header.writeUInt16BE(data.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 0x80 | 127;
    header.writeUInt32BE(0, 2);
    header.writeUInt32BE(data.length, 6);
  }
  const masked = Buffer.from(data.map((byte, index) => byte ^ mask[index % 4]));
  socket.write(Buffer.concat([header, mask, masked]));
}

function assert(ok, message) {
  if (!ok) throw new Error(message);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function stopServer() {
  if (server.exitCode !== null || server.signalCode !== null) return;
  server.kill("SIGTERM");
  const exited = await Promise.race([
    once(server, "exit").then(() => true).catch(() => true),
    delay(1500).then(() => false),
  ]);
  if (exited) return;
  server.kill("SIGKILL");
  await Promise.race([
    once(server, "exit").catch(() => {}),
    delay(1000),
  ]);
}
