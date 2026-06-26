import { spawn } from "node:child_process";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

class Cdp {
  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      ws.addEventListener("open", resolve, { once: true });
      ws.addEventListener("error", reject, { once: true });
    });
    return new Cdp(ws);
  }

  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    ws.addEventListener("message", (event) => this.onMessage(event));
  }

  send(method, params = {}, sessionId = "", timeoutMs = 15000) {
    const id = this.nextId++;
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    this.ws.send(JSON.stringify(payload));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (this.pending.delete(id)) reject(new Error(`CDP ${method} timed out`));
      }, timeoutMs).unref();
    });
  }

  onMessage(event) {
    const message = JSON.parse(String(event.data));
    if (!message.id) return;
    const pending = this.pending.get(message.id);
    if (!pending) return;
    this.pending.delete(message.id);
    if (message.error) pending.reject(new Error(JSON.stringify(message.error)));
    else pending.resolve(message.result || {});
  }

  close() {
    this.ws.close();
  }
}

const root = new URL("..", import.meta.url).pathname;
const runId = `${Date.now()}-${process.pid}`;
const appPort = Number(process.env.MEMEPIRE_VISUAL_APP_PORT || (18000 + (process.pid % 10000)));
const debugPort = Number(process.env.MEMEPIRE_VISUAL_DEBUG_PORT || (28000 + (process.pid % 10000)));
const chrome = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const profile = join("/tmp", `memepire-chrome-${runId}`);
const shotDir = join("/tmp", "memepire-visual");
const menuShotPath = join(shotDir, "menu-cdp.png");
const matchShotPath = join(shotDir, "match-cdp.png");
const resultShotPath = join(shotDir, "result-cdp.png");
const memeSpritesShotPath = join(shotDir, "meme-sprites-cdp.png");
const mobileMenuShotPath = join(shotDir, "mobile-menu-cdp.png");
const mobileMatchShotPath = join(shotDir, "mobile-match-cdp.png");
const portraitMenuShotPath = join(shotDir, "portrait-menu-cdp.png");
const portraitMatchShotPath = join(shotDir, "portrait-match-cdp.png");
const fractionalDprShotPath = join(shotDir, "fractional-dpr-cdp.png");

const server = spawn(process.execPath, ["serve-web.mjs", `--port=${appPort}`], {
  cwd: root,
  stdio: ["ignore", "pipe", "pipe"],
});
let serverOutput = "";
server.stdout.on("data", (chunk) => (serverOutput += chunk));
server.stderr.on("data", (chunk) => (serverOutput += chunk));

let browser;
let cdp;
let browserOutput = "";
const watchdog = setTimeout(() => {
  console.error(`[memepire-web] visual check timed out on appPort=${appPort} debugPort=${debugPort}\n${browserOutput}`);
  stopProcess(browser);
  stopProcess(server);
  process.exit(1);
}, 120000);
try {
  await waitForHttp(`http://127.0.0.1:${appPort}/`);
  await rm(profile, { recursive: true, force: true });
  await mkdir(shotDir, { recursive: true });
  browser = spawn(chrome, [
    "--headless=new",
    "--enable-unsafe-swiftshader",
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--ignore-gpu-blocklist",
    "--no-first-run",
    "--no-default-browser-check",
    `--user-data-dir=${profile}`,
    `--remote-debugging-address=127.0.0.1`,
    `--remote-debugging-port=${debugPort}`,
    "--window-size=1280,720",
    "about:blank",
  ], { stdio: ["ignore", "pipe", "pipe"] });
  browser.stdout.on("data", (chunk) => (browserOutput += chunk));
  browser.stderr.on("data", (chunk) => (browserOutput += chunk));

  const wsUrl = await waitForDebugUrl();
  cdp = await Cdp.connect(wsUrl);

  const menuSession = await openScenario(cdp, {
    viewport: { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false },
    url: `http://127.0.0.1:${appPort}/?king=doge&rival=pepe&pressure=rush&arena=creek&stake=500&case=menu`,
  });
  const state = await waitForGodotScene(cdp, menuSession, "menu");
  const errorText = await evaluate(cdp, menuSession, "document.body.innerText || ''");
  assert(!String(errorText).includes("WebGL2"), "browser visual check hit the WebGL2 error screen");
  assert(state.scene === "menu", `expected menu scene, got ${JSON.stringify(state)}`);
  assert(state.selectedKing === "doge", `URL king param did not apply: ${JSON.stringify(state)}`);
  assert(state.rivalKing === "pepe", `URL rival param did not apply: ${JSON.stringify(state)}`);
  assert(Number(state.wagerStake) === 500, `URL stake param did not apply: ${JSON.stringify(state)}`);
  await assertCanvasFitsViewport(cdp, menuSession, 1280, 720);
  await captureNonTrivialScreenshot(cdp, menuSession, menuShotPath);

  const matchSession = await openScenario(cdp, {
    viewport: { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false },
    url: `http://127.0.0.1:${appPort}/?king=doge&rival=pepe&pressure=siege&arena=ruins&stake=350&start=1&selectionSummaryPreview=1&case=match`,
  });
  const matchState = await waitForGodotScene(cdp, matchSession, "main");
  assert(matchState.scene === "main", `expected main scene, got ${JSON.stringify(matchState)}`);
  assert(matchState.playerKing === "doge", `start URL king did not reach match: ${JSON.stringify(matchState)}`);
  assert(matchState.rivalKing === "pepe", `start URL rival did not reach match: ${JSON.stringify(matchState)}`);
  assert(Number(matchState.wagerStake) === 350, `start URL stake did not reach match: ${JSON.stringify(matchState)}`);
  assert(Number(matchState.units) >= 8, `live match did not spawn enough opening units: ${JSON.stringify(matchState)}`);
  assert(Number(matchState.structures) >= 2, `live match did not spawn keeps/structures: ${JSON.stringify(matchState)}`);
  assert(Number(matchState.food) === 420 && Number(matchState.timber) === 360 && Number(matchState.memp) === 90, `live match starting resources wrong: ${JSON.stringify(matchState)}`);
  assert(Number(matchState.pop) >= 6 && Number(matchState.popCap) >= 24, `live match opening population wrong: ${JSON.stringify(matchState)}`);
  const selectionSummaryState = await waitForSelectionSummaryPreview(cdp, matchSession);
  assert(Number(selectionSummaryState.selectionSummaryCount) === 2, `selection summary did not select preview units: ${JSON.stringify(selectionSummaryState)}`);
  assert(String(selectionSummaryState.selectionSummaryComposition || "").includes("ISR WORK") && String(selectionSummaryState.selectionSummaryComposition || "").includes("ISR INF"), `selection composition missing expected unit labels: ${JSON.stringify(selectionSummaryState)}`);
  assert(selectionSummaryState.selectionSummaryOrder === "MIXED", `selection order summary wrong: ${JSON.stringify(selectionSummaryState)}`);
  await captureNonTrivialScreenshot(cdp, matchSession, matchShotPath);

  const memeSpritesSession = await openScenario(cdp, {
    viewport: { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false },
    url: `http://127.0.0.1:${appPort}/?king=doge&rival=pepe&pressure=standard&arena=meadow&stake=0&start=1&memeSpritePreview=1&case=meme-sprites`,
  });
  const memeSpritesState = await waitForMemeSpritePreview(cdp, memeSpritesSession);
  assert(memeSpritesState.playerKing === "doge", `meme sprite preview did not force player king: ${JSON.stringify(memeSpritesState)}`);
  assert(Number(memeSpritesState.memeSpriteUnits) === 10, `meme sprite preview did not spawn all custom role units: ${JSON.stringify(memeSpritesState)}`);
  assert(Array.isArray(memeSpritesState.memeSpriteKings) && ["doge", "pepe"].every((king) => memeSpritesState.memeSpriteKings.includes(king)), `meme sprite preview missing a king: ${JSON.stringify(memeSpritesState)}`);
  assert(Array.isArray(memeSpritesState.memeSpriteKinds) && ["villager", "swordsman", "archer", "lancer", "siege"].every((kind) => memeSpritesState.memeSpriteKinds.includes(kind)), `meme sprite preview missing a role: ${JSON.stringify(memeSpritesState)}`);
  await captureNonTrivialScreenshot(cdp, memeSpritesSession, memeSpritesShotPath);

  const resultSession = await openScenario(cdp, {
    viewport: { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false },
    url: `http://127.0.0.1:${appPort}/?king=doge&rival=pepe&pressure=rush&arena=creek&stake=450&start=1&webResultSmoke=1&case=result`,
  });
  const resultState = await waitForLeaderboardPost(cdp, resultSession);
  assert(resultState.webResultSmoke === true, `web result trigger did not run: ${JSON.stringify(resultState)}`);
  assert(resultState.matchOver === true && resultState.matchResult === "won", `web result did not finish victory: ${JSON.stringify(resultState)}`);
  assert(resultState.leaderboardPosted === true, `web result did not post leaderboard: ${JSON.stringify(resultState)}`);
  assert(resultState.leaderboardSubmittedKing === "doge" && resultState.leaderboardSubmittedRival === "pepe" && resultState.leaderboardSubmittedResult === "won" && Number(resultState.leaderboardSubmittedStake) === 450, `leaderboard submitted unexpected row: ${JSON.stringify(resultState)}`);
  await captureNonTrivialScreenshot(cdp, resultSession, resultShotPath);

  const mobileMenuSession = await openScenario(cdp, {
    viewport: { width: 844, height: 390, deviceScaleFactor: 2, mobile: true },
    url: `http://127.0.0.1:${appPort}/?king=pepe&rival=doge&pressure=standard&arena=pond&stake=150&case=mobile-menu`,
  });
  const mobileMenuState = await waitForGodotScene(cdp, mobileMenuSession, "menu");
  assert(mobileMenuState.selectedKing === "pepe", `mobile URL king param did not apply: ${JSON.stringify(mobileMenuState)}`);
  assert(mobileMenuState.rivalKing === "doge", `mobile URL rival param did not apply: ${JSON.stringify(mobileMenuState)}`);
  assert(Number(mobileMenuState.wagerStake) === 150, `mobile URL stake param did not apply: ${JSON.stringify(mobileMenuState)}`);
  await assertCanvasFitsViewport(cdp, mobileMenuSession, 844, 390);
  await captureNonTrivialScreenshot(cdp, mobileMenuSession, mobileMenuShotPath, 12000);

  const portraitMenuSession = await openScenario(cdp, {
    viewport: { width: 390, height: 844, deviceScaleFactor: 2, mobile: true },
    url: `http://127.0.0.1:${appPort}/?king=doge&rival=pepe&pressure=siege&arena=mesa&stake=300&case=portrait-menu`,
  });
  const portraitMenuState = await waitForGodotScene(cdp, portraitMenuSession, "menu");
  assert(portraitMenuState.selectedKing === "doge", `portrait menu URL king param did not apply: ${JSON.stringify(portraitMenuState)}`);
  assert(portraitMenuState.rivalKing === "pepe", `portrait menu URL rival param did not apply: ${JSON.stringify(portraitMenuState)}`);
  assert(Number(portraitMenuState.wagerStake) === 300, `portrait menu URL stake param did not apply: ${JSON.stringify(portraitMenuState)}`);
  await assertCanvasFitsViewport(cdp, portraitMenuSession, 390, 844);
  await captureNonTrivialScreenshot(cdp, portraitMenuSession, portraitMenuShotPath, 12000);

  const mobileMatchSession = await openScenario(cdp, {
    viewport: { width: 844, height: 390, deviceScaleFactor: 2, mobile: true },
    url: `http://127.0.0.1:${appPort}/?king=pepe&rival=doge&pressure=rush&arena=festival&stake=200&start=1&case=mobile-match`,
  });
  const mobileMatchState = await waitForGodotScene(cdp, mobileMatchSession, "main");
  assert(mobileMatchState.playerKing === "pepe", `mobile start URL king did not reach match: ${JSON.stringify(mobileMatchState)}`);
  assert(mobileMatchState.rivalKing === "doge", `mobile start URL rival did not reach match: ${JSON.stringify(mobileMatchState)}`);
  assert(Number(mobileMatchState.wagerStake) === 200, `mobile start URL stake did not reach match: ${JSON.stringify(mobileMatchState)}`);
  assert(Number(mobileMatchState.units) >= 5, `mobile live match did not spawn enough units: ${JSON.stringify(mobileMatchState)}`);
  await assertCanvasFitsViewport(cdp, mobileMatchSession, 844, 390);
  await captureNonTrivialScreenshot(cdp, mobileMatchSession, mobileMatchShotPath, 12000);

  const portraitMatchSession = await openScenario(cdp, {
    viewport: { width: 390, height: 844, deviceScaleFactor: 2, mobile: true },
    url: `http://127.0.0.1:${appPort}/?king=doge&rival=pepe&pressure=standard&arena=meadow&stake=100&start=1&case=portrait-match`,
  });
  const portraitMatchState = await waitForGodotScene(cdp, portraitMatchSession, "main");
  assert(portraitMatchState.playerKing === "doge", `portrait start URL king did not reach match: ${JSON.stringify(portraitMatchState)}`);
  assert(portraitMatchState.rivalKing === "pepe", `portrait start URL rival did not reach match: ${JSON.stringify(portraitMatchState)}`);
  assert(Number(portraitMatchState.units) >= 5, `portrait live match did not spawn enough units: ${JSON.stringify(portraitMatchState)}`);
  await assertCanvasFitsViewport(cdp, portraitMatchSession, 390, 844);
  await captureNonTrivialScreenshot(cdp, portraitMatchSession, portraitMatchShotPath, 12000);
  await assertNoPortraitLetterbox(portraitMatchShotPath);

  const fractionalDprSession = await openScenario(cdp, {
    viewport: { width: 1600, height: 900, deviceScaleFactor: 0.8, mobile: false },
    url: `http://127.0.0.1:${appPort}/?king=doge&rival=pepe&pressure=standard&arena=meadow&stake=0&start=1&memeSpritePreview=1&case=fractional-dpr`,
  });
  await waitForMemeSpritePreview(cdp, fractionalDprSession);
  const fractionalMetrics = await canvasMetrics(cdp, fractionalDprSession);
  assert(Number(fractionalMetrics.dpr) >= 1, `fractional DPR guard did not activate: ${JSON.stringify(fractionalMetrics)}`);
  assert(Number(fractionalMetrics.canvasBitmapWidth) >= Number(fractionalMetrics.canvasWidth), `canvas backing store is smaller than CSS width, likely to tile: ${JSON.stringify(fractionalMetrics)}`);
  assert(Number(fractionalMetrics.canvasBitmapHeight) >= Number(fractionalMetrics.canvasHeight), `canvas backing store is smaller than CSS height, likely to tile: ${JSON.stringify(fractionalMetrics)}`);
  await captureNonTrivialScreenshot(cdp, fractionalDprSession, fractionalDprShotPath, 12000);

  console.log(`[memepire-web] exported app reached desktop, meme sprite preview, fractional DPR, landscape mobile, and portrait mobile menu/match/result in Chrome; screenshots ${menuShotPath}, ${matchShotPath}, ${memeSpritesShotPath}, ${fractionalDprShotPath}, ${resultShotPath}, ${mobileMenuShotPath}, ${portraitMenuShotPath}, ${mobileMatchShotPath}, ${portraitMatchShotPath}`);
} finally {
  clearTimeout(watchdog);
  if (cdp) cdp.close();
  stopProcess(browser);
  stopProcess(server);
}
process.exit(0);

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

async function waitForDebugUrl() {
  const deadline = Date.now() + 10000;
  let last = "";
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${debugPort}/json/version`);
      const data = await response.json();
      if (data.webSocketDebuggerUrl) return data.webSocketDebuggerUrl;
      last = JSON.stringify(data);
    } catch (error) {
      last = error.message;
    }
    await delay(100);
  }
  throw new Error(`Chrome debugging did not become ready: ${last}\n${browserOutput}`);
}

async function openScenario(cdp, { viewport, url }) {
  const { targetId } = await cdp.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
  await cdp.send("Page.enable", {}, sessionId);
  await cdp.send("Runtime.enable", {}, sessionId);
  await setViewport(cdp, sessionId, viewport);
  await navigate(cdp, sessionId, url);
  return sessionId;
}

async function navigate(cdp, sessionId, url) {
  await cdp.send("Runtime.evaluate", {
    expression: "window.__memepireState = {}; window.__memepireEvents = [];",
    awaitPromise: true,
  }, sessionId).catch(() => {});
  await cdp.send("Page.navigate", { url }, sessionId);
}

async function setViewport(cdp, sessionId, { width, height, deviceScaleFactor, mobile }) {
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width,
    height,
    deviceScaleFactor,
    mobile,
  }, sessionId);
}

async function assertCanvasFitsViewport(cdp, sessionId, expectedWidth, expectedHeight) {
  const metrics = await evaluate(cdp, sessionId, `(() => {
    const canvas = document.getElementById('canvas');
    const rect = canvas ? canvas.getBoundingClientRect() : { width: 0, height: 0, left: 0, top: 0 };
    return {
      innerWidth,
      innerHeight,
      dpr: devicePixelRatio,
      canvasWidth: rect.width,
      canvasHeight: rect.height,
      canvasBitmapWidth: canvas ? canvas.width : 0,
      canvasBitmapHeight: canvas ? canvas.height : 0,
      canvasLeft: rect.left,
      canvasTop: rect.top,
      canvasClass: canvas ? canvas.className : '',
    };
  })()`);
  assert(metrics.innerWidth === expectedWidth && metrics.innerHeight === expectedHeight, `unexpected viewport metrics: ${JSON.stringify(metrics)}`);
  assert(Math.abs(metrics.canvasWidth - expectedWidth) <= 2 && Math.abs(metrics.canvasHeight - expectedHeight) <= 2, `canvas does not fill viewport: ${JSON.stringify(metrics)}`);
  assert(Math.abs(metrics.canvasLeft) <= 2 && Math.abs(metrics.canvasTop) <= 2, `canvas is offset from viewport: ${JSON.stringify(metrics)}`);
}

async function canvasMetrics(cdp, sessionId) {
  return evaluate(cdp, sessionId, `(() => {
    const canvas = document.getElementById('canvas');
    const rect = canvas ? canvas.getBoundingClientRect() : { width: 0, height: 0, left: 0, top: 0 };
    return {
      innerWidth,
      innerHeight,
      dpr: devicePixelRatio,
      canvasWidth: rect.width,
      canvasHeight: rect.height,
      canvasBitmapWidth: canvas ? canvas.width : 0,
      canvasBitmapHeight: canvas ? canvas.height : 0,
      canvasLeft: rect.left,
      canvasTop: rect.top,
      canvasClass: canvas ? canvas.className : '',
    };
  })()`);
}

async function waitForGodotScene(cdp, sessionId, scene) {
  const deadline = Date.now() + 30000;
  let last = {};
  while (Date.now() < deadline) {
    last = await evaluate(cdp, sessionId, "window.__memepireState || {}");
    if (last && last.scene === scene) return last;
    await delay(500);
  }
  throw new Error(`Godot ${scene} scene did not publish web state: ${JSON.stringify(last)}`);
}

async function waitForLeaderboardPost(cdp, sessionId) {
  const deadline = Date.now() + 60000;
  let last = {};
  while (Date.now() < deadline) {
    last = await evaluate(cdp, sessionId, "window.__memepireState || {}");
    if (last && last.scene === "main" && last.leaderboardPosted === true) return last;
    await delay(500);
  }
  throw new Error(`Browser result did not post leaderboard: ${JSON.stringify(last)}`);
}

async function waitForMemeSpritePreview(cdp, sessionId) {
  const deadline = Date.now() + 30000;
  let last = {};
  while (Date.now() < deadline) {
    last = await evaluate(cdp, sessionId, "window.__memepireState || {}");
    if (last && last.scene === "main" && last.memeSpritePreview === true) return last;
    await delay(500);
  }
  throw new Error(`Meme sprite preview did not publish web state: ${JSON.stringify(last)}`);
}

async function waitForSelectionSummaryPreview(cdp, sessionId) {
  const deadline = Date.now() + 30000;
  let last = {};
  while (Date.now() < deadline) {
    last = await evaluate(cdp, sessionId, "window.__memepireState || {}");
    if (last && last.scene === "main" && last.selectionSummaryPreview === true) return last;
    await delay(500);
  }
  throw new Error(`Selection summary preview did not publish web state: ${JSON.stringify(last)}`);
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} HTTP ${response.status}`);
  return response.json();
}

async function captureNonTrivialScreenshot(cdp, sessionId, path, minSize = 30000) {
  const { data } = await cdp.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false }, sessionId, 45000);
  await writeFile(path, Buffer.from(data, "base64"));
  const size = (await readFile(path)).length;
  assert(size > minSize, `browser screenshot too small; app may still be loading (${size} bytes at ${path})`);
}

async function assertNoPortraitLetterbox(path) {
  const topMean = await imageEdgeMean(path, "North");
  const centerMean = await imageEdgeMean(path, "Center");
  const bottomMean = await imageEdgeMean(path, "South");
  assert(topMean > 0.03 && centerMean > 0.08 && bottomMean > 0.03, `portrait screenshot is letterboxed or has a dead viewport band: top=${topMean.toFixed(4)} center=${centerMean.toFixed(4)} bottom=${bottomMean.toFixed(4)} path=${path}`);
}

async function imageEdgeMean(path, gravity) {
  const magick = process.env.MAGICK_BIN || "magick";
  const out = await runCapture(magick, [path, "-gravity", gravity, "-crop", "100%x12%+0+0", "-colorspace", "sRGB", "-format", "%[fx:mean]", "info:"]);
  const mean = Number(String(out).trim());
  assert(Number.isFinite(mean), `could not measure screenshot edge mean with ImageMagick: ${out}`);
  return mean;
}

function runCapture(cmd, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    let err = "";
    child.stdout.on("data", (chunk) => (out += chunk));
    child.stderr.on("data", (chunk) => (err += chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve(out);
      else reject(new Error(`${cmd} ${args.join(" ")} failed with ${code}\n${out}${err}`));
    });
  });
}

async function evaluate(cdp, sessionId, expression) {
  const response = await cdp.send("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
  }, sessionId, 30000);
  if (response.exceptionDetails) {
    throw new Error(`Runtime.evaluate failed: ${JSON.stringify(response.exceptionDetails)}`);
  }
  return response.result?.value;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function stopProcess(child) {
  if (child && !child.killed) child.kill("SIGTERM");
}
