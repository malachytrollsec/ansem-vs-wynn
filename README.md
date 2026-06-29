# Ansem vs Wynn

Godot RTS for ansemvswynn.com. Pick Ansem or Wynn, choose pressure and arena, build an economy, train units, crack the rival keep, and post wallet-backed results to the local leaderboard.

## Run

```sh
node serve-web.mjs --port=8799
```

Open `http://127.0.0.1:8799/`.

Shareable browser params are supported for game setup and multiplayer room entry:

```text
http://127.0.0.1:8799/?king=ansem&rival=wynn&pressure=rush&arena=creek&start=1
http://127.0.0.1:8799/?room=AVW&host=1&king=ansem&rival=wynn
http://127.0.0.1:8799/?room=AVW&join=1&king=wynn&rival=ansem
```

For a fresh web export:

```sh
npm run export:web
```

## Play Surface

- Two sides: Ansem and Wynn.
- Sixteen arid arenas with data-driven terrain dressing.
- Pressure modes: standard, rush, and siege.
- RTS loop: villagers, army units, housing, forge, towers, market income, upgrades, rally, minimap, waves, and win/loss results.
- Browser Phantom bridge with unsigned fallback, local leaderboard, and verified wallet leaderboard endpoints.
- Human multiplayer room relay over `/room`, with room status, events, proof, stream, and room-kit JSON.

## Checks

```sh
npm run check
```

This verifies the Godot export, web bridge, relay, room stream, wallet challenge/login, and leaderboard submission. The intentionally removed agent runner, browser duel, and legacy AIge discovery routes should remain absent.
