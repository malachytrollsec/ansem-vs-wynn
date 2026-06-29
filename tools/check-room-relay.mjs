import { spawn } from "node:child_process";

const root = new URL("..", import.meta.url).pathname;
const port = Number(process.env.AVW_TEST_PORT || 8899);
const room = `T${Date.now().toString(36).toUpperCase().slice(-6)}`;

const server = spawn(process.execPath, ["serve-web.mjs", `--port=${port}`], {
  cwd: root,
  stdio: ["ignore", "pipe", "pipe"],
});

let serverOutput = "";
server.stdout.on("data", (chunk) => (serverOutput += chunk));
server.stderr.on("data", (chunk) => (serverOutput += chunk));

try {
  await waitForHttp(`http://127.0.0.1:${port}/room-kit?room=${room}`);
  const host = await openWs({ role: "host", from: "host", label: "ANSEM", king: "ansem" });
  const joiner = await openWs({ role: "join", from: "join", label: "WYNN", king: "wynn" });

  await host.waitFor((msg) => msg.type === "hello" && msg.from === "join");
  host.send({ type: "hello-ack", identity: { label: "ANSEM", king: "ansem" } });
  await joiner.waitFor((msg) => msg.type === "hello-ack" && msg.from === "host");

  host.send({ type: "snapshot", snapshot: snapshotPayload(false) });
  await joiner.waitFor((msg) => msg.type === "snapshot");
  host.send({ type: "snapshot", snapshot: snapshotPayload(true) });
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
  assert(eventRoom?.events?.some((event) => event.type === "intent" && event.action === "attack"), "room-events missing attack intent");
  assert(eventRoom?.events?.some((event) => event.type === "intent-result" && event.accepted), "room-events missing accepted result");
  assert(proof.ok && proofRoom?.ok, "room-proof should be ok");
  assert(proofRoom.checks?.every((check) => check.ok), "room-proof ok must require every proof check");
  assert(proofRoom.snapshotCount >= 1, "room-proof missing snapshot count");
  assert(proofRoom.finishedSnapshotCount >= 1 && proofRoom.result === "won", "room-proof missing final result");
  assert(proofRoom.finishedSnapshot?.rivalResources?.food === 90, "room-proof missing finished rival resources");
  assert(proofRoom.finishedSnapshot?.rivalPop?.live === 2, "room-proof missing finished rival population");
  assert(proofRoom.finishedSnapshot?.rivalUpgrades?.forge === true, "room-proof missing finished rival upgrades");
  assert(proofRoom.acceptedCount >= 1, "room-proof missing accepted count");

  const leaderboardEntry = {
    id: `${room}-result`,
    kingId: "ansem",
    king: "ANSEM",
    rivalId: "wynn",
    rival: "WYNN",
    result: "won",
    wave: 99,
    kills: 999,
    seconds: 123,
    arena: "meadow",
    pressure: "standard",
  };
  const submitted = await postJson("/leaderboard", { entry: leaderboardEntry });
  const leaderboard = await fetchJson("/leaderboard");
  assert(submitted.submitted?.id === leaderboardEntry.id, "leaderboard did not echo submitted entry");
  assert(leaderboard.entries?.some((entry) => entry.id === leaderboardEntry.id && entry.score > 0), "leaderboard missing submitted entry");

  host.close();
  joiner.close();

  console.log(`[avw-room] relay/status/events/proof/leaderboard verified for ${room}`);
} finally {
  await stopServer();
}

function snapshotPayload(done) {
  return {
    started: true,
    over: done,
    result: done ? "won" : "",
    time: done ? "00:42" : "00:07",
    seconds: done ? 42 : 7,
    wave: done ? 1 : 0,
    kills: done ? 3 : 1,
    player: "ANSEM",
    playerId: "ansem",
    rival: "WYNN",
    rivalId: "wynn",
    resources: { food: done ? 310 : 260, timber: done ? 205 : 180, memp: done ? 75 : 50 },
    rivalResources: { food: done ? 90 : 240, timber: done ? 45 : 120, memp: done ? 10 : 30 },
    pop: { live: done ? 5 : 4, queued: done ? 0 : 1, cap: done ? 26 : 20 },
    rivalPop: { live: done ? 2 : 3, queued: 0, cap: 20 },
    upgrades: { atk: done ? 2 : 1, armor: done ? 1 : 0, eco: done ? 3 : 2, forge: true },
    rivalUpgrades: { atk: done ? 1 : 0, armor: 1, eco: 1, forge: done },
    units: [{ id: 1 }, { id: 2 }],
    structures: [{ id: 3 }],
  };
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
  const socket = new WebSocket(`ws://127.0.0.1:${port}/room`);
  const pending = [];
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", () => reject(new Error("websocket open failed")), { once: true });
  });
  socket.addEventListener("message", (event) => {
    try {
      pending.push(JSON.parse(String(event.data)));
    } catch {
      // Ignore malformed messages.
    }
  });
  const client = {
    send(payload) {
      socket.send(JSON.stringify({ code: roomCode, role, from, ...payload }));
    },
    async waitFor(predicate, ms = 5000) {
      const deadline = Date.now() + ms;
      while (Date.now() < deadline) {
        const idx = pending.findIndex(predicate);
        if (idx >= 0) return pending.splice(idx, 1)[0];
        await delay(30);
      }
      throw new Error(`timed out waiting for room message. pending=${JSON.stringify(pending)} server=${serverOutput}`);
    },
    close() {
      socket.close();
    },
  };
  client.send({ type: "join", identity: { label, king } });
  await client.waitFor((msg) => msg.type === "relay-ready");
  return client;
}

async function stopServer() {
  server.kill("SIGTERM");
  await new Promise((resolve) => server.once("exit", resolve)).catch(() => {});
}

function assert(ok, message) {
  if (!ok) throw new Error(message);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
