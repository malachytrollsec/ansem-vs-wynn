import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { generateKeyPairSync, sign } from "node:crypto";

const root = new URL("..", import.meta.url).pathname;
const room = `W${Date.now().toString(36).toUpperCase().slice(-6)}`;
const port = await freePort();
const origin = `http://127.0.0.1:${port}`;
const timeoutMs = 12000;

const server = spawn(process.execPath, ["serve-web.mjs", `--port=${port}`], {
  cwd: root,
  stdio: ["ignore", "pipe", "pipe"],
});

let serverOutput = "";
server.stdout.on("data", (chunk) => (serverOutput += chunk));
server.stderr.on("data", (chunk) => (serverOutput += chunk));

try {
  await withTimeout(waitForHttp(`${origin}/room-kit?room=${room}`), timeoutMs, "server did not start");

  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const address = base58Encode(publicKey.export({ format: "der", type: "spki" }).subarray(-32));

  const challenge = await postJson("/wallet-challenge", { address });
  assert(challenge.ok && challenge.address === address && challenge.message.includes("Israel vs Palestine wallet login"), "wallet challenge unusable");

  const badLogin = await postJson("/wallet-login", { address, nonce: challenge.nonce, signature: "bad" }, false);
  assert(badLogin.status === 401 && badLogin.body?.error === "bad-signature", "bad signature should be rejected");

  const signature = sign(null, Buffer.from(challenge.message, "utf8"), privateKey).toString("base64");
  const login = await postJson("/wallet-login", { address, nonce: challenge.nonce, signature });
  assert(login.ok && login.verified && login.token, "wallet login should return verified token");

  const manual = await postJson("/leaderboard", {
    entry: leaderboardEntry(`${room}-manual`, address, { verified: true, walletLabel: "Manual Claim", wagerUnit: "ticket" }),
  });
  assert(manual.submitted?.wallet === address, "manual leaderboard wallet was not preserved");
  assert(manual.submitted?.verified === false, "manual leaderboard row must not self-verify");
  assert(manual.submitted?.wagerUnit === "ticket", "manual leaderboard row should remain ticket-mode");

  const verified = await postJson("/leaderboard", {
    walletToken: login.token,
    entry: leaderboardEntry(`${room}-verified`, address, { walletLabel: "Signed Wallet", wagerUnit: "SOL" }),
  });
  assert(verified.submitted?.verified === true, "token-backed leaderboard row should be verified");
  assert(verified.submitted?.walletLabel === "Signed Wallet", "verified leaderboard wallet label missing");
  assert(verified.submitted?.wagerUnit === "SOL", "verified leaderboard row should preserve SOL wager unit");

  const leaderboard = await fetchJson(`${origin}/leaderboard`);
  assert(leaderboard.entries?.some((entry) => entry.id === `${room}-manual` && !entry.verified), "leaderboard missing unverified manual row");
  assert(leaderboard.entries?.some((entry) => entry.id === `${room}-verified` && entry.verified), "leaderboard missing verified wallet row");
  assert(leaderboard.entries?.some((entry) => entry.id === `${room}-verified` && entry.wagerUnit === "SOL"), "leaderboard missing verified SOL wager unit");
  assert(leaderboard.wagers?.some((entry) => entry.id === `${room}-verified` && entry.verified), "wager leaderboard missing verified row");

  console.log(`[memepire-wallet] challenge/login/verified leaderboard verified for ${room}`);
} finally {
  server.kill("SIGTERM");
  await new Promise((resolve) => server.once("exit", resolve)).catch(() => {});
}

function leaderboardEntry(id, wallet, extra = {}) {
  return {
    id,
    wallet,
    kingId: "doge",
    king: "ISRAEL",
    rivalId: "pepe",
    rival: "PALESTINE",
    result: "won",
    wave: 99,
    kills: 999,
    seconds: 144,
    arena: "ruins",
    pressure: "standard",
    stake: 500,
    tax: 25,
    payout: 1000000,
    ...extra,
  };
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { accept: "application/json" } });
  if (!response.ok) throw new Error(`${url} HTTP ${response.status}: ${await response.text()}`);
  return response.json();
}

async function postJson(path, body, requireOk = true) {
  const response = await fetch(`${origin}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => null);
  if (requireOk && !response.ok) throw new Error(`${path} HTTP ${response.status}: ${JSON.stringify(payload)}`);
  return requireOk ? payload : { status: response.status, body: payload };
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

function base58Encode(bytes) {
  const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  let num = 0n;
  for (const byte of bytes) num = (num << 8n) + BigInt(byte);
  let encoded = "";
  while (num > 0n) {
    const remainder = Number(num % 58n);
    encoded = alphabet[remainder] + encoded;
    num /= 58n;
  }
  for (const byte of bytes) {
    if (byte !== 0) break;
    encoded = "1" + encoded;
  }
  return encoded || "1";
}

function assert(ok, message) {
  if (!ok) throw new Error(message);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
