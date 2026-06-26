# Israel vs Palestine

Godot RTS wager-battle for israelvspalestine.org. Pick Israel or Palestine, choose pressure and arena, build an economy, train units, crack the rival keep, and post wallet-backed results to the local leaderboard.

## Run

```sh
node serve-web.mjs --port=8799
```

Open `http://127.0.0.1:8799/`.

Shareable browser params are supported for game setup and multiplayer room entry:

```text
http://127.0.0.1:8799/?king=israel&rival=palestine&pressure=rush&arena=creek&stake=500&start=1
http://127.0.0.1:8799/?room=IVP&host=1&king=israel&rival=palestine&stake=250
http://127.0.0.1:8799/?room=IVP&join=1&king=palestine&rival=israel&stake=250
```

For a fresh web export:

```sh
npm run export:web
```

## Play Surface

- Two sides: Israel and Palestine.
- Sixteen arid arenas with data-driven terrain dressing.
- Pressure modes: standard, rush, and siege.
- RTS loop: villagers, army units, housing, forge, towers, market income, upgrades, rally, minimap, waves, and win/loss results.
- Wager ticket display: stake, tax, net, and win payout show on the menu, HUD, result banner, room snapshots, leaderboard rows, and multiplayer offer/accept/decline receipts.
- Browser Phantom bridge with ticket-mode fallback, local leaderboard, and verified SOL leaderboard endpoints.
- Human multiplayer room relay over `/room`, with room status, events, proof, stream, and room-kit JSON.

## Checks

```sh
npm run check
```

This verifies the Godot export, web bridge, relay, room stream, wallet challenge/login, and leaderboard submission. The intentionally removed agent runner, browser duel, and legacy AIge discovery routes should remain absent.
