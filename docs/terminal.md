# Terminal build (prototype)

The original CHING terminal client, kept because it still runs and because
its multiplayer daemon is the reference for how a server owns the RNG. The
shipping game is the iOS app, see the [root README](../README.md).

Names here predate the beach theme: coins are pearls, tiles are shells.

## Install

```
npm install
```

## Play

```
npm run ching
```

That's the only command players need. On first run it asks for your display name (persisted under `~/.ching/session.json`). On every run it shows:

- `[1] Single player` — solo vs AI, no network, no daemon.
- `[2] Multiplayer` — local or LAN; see below.
- `[N]` rename you. `[Q]` quit.

For a different solo difficulty: `npm run ching -- --discipline=0.3` (greedier, easier to beat) or `0.9` (more disciplined, harder). Default is `0.6`.

`npm run play` (solo) and `npm run join` (multiplayer) are kept as aliases for the old entry points and still work.

## Controls

Single keypress, no Enter.

| Key       | Action                                                       |
| --------- | ------------------------------------------------------------ |
| `R`       | Roll the dice in your hand                                   |
| `1`-`5`   | Set aside all dice of that face value                        |
| `C`       | Set aside all coins (the `$` face, worth 5)                  |
| `S`       | Stop and try to bank                                         |
| `Q`       | Quit                                                         |

The prompt only shows keys that are legal in the current state.

## How a turn works

1. Press `R` to roll your 8 dice.
2. Pick a face value with `1`-`5` or `C`. All dice of that value get set aside, and you can't pick that face again this turn.
3. Re-roll the remaining dice (`R`) or bank (`S`).
4. To bank, your set-aside must contain at least one coin. Your sum picks the highest center tile less than or equal to that sum, or steals from a rival on an exact match.
5. **Bust** if your next roll lands on no new faces, you stop without a coin, or no tile fits. You lose your top tile, and the highest center tile is burned permanently.

The center starts with tiles 21-36, worth 1, 2, 3, or 4 coins each (40 coins total before any are burned). Most coins when the center empties wins.

## Architecture

```
src/engine.ts     pure reducer: (state, action, rng) => newState
src/ai.ts         depends only on engine
src/render.ts     pure: state -> ANSI strings
src/term.ts       terminal I/O (alt-screen, raw mode, animations)
src/cli.ts        thin solo-vs-AI loop
src/client.ts     thin network shell (uses render + term)
src/net/          protocol, daemon, room
```

- **Renderer** is pure. State plus viewer perspective in, ANSI strings out. ANSI is emitted unconditionally so snapshot tests are stable across `TERM` and `FORCE_COLOR`.
- **Terminal** owns alt-screen, raw mode, animation pacing. Teardown is idempotent so signal handlers and BYE paths can call it safely.
- **Daemon** is the source of truth in multiplayer: it holds room state, calls the engine reducer, and owns the RNG (server-authoritative, fair dice). Clients are thin and never run `engine.step` themselves.

## Multiplayer

CHING multiplayer is designed for trusted environments: a laptop on a home LAN, or a Pi reached over ssh. A daemon process owns every room and every dice roll; clients are thin TUIs that connect either over a local unix socket or plain TCP. Same wire protocol over both.

Players never need to start the daemon manually — the launcher does it. Just `npm run ching` → `[2] Multiplayer`:

- `[H]ost` — creates a room on this machine. If no daemon is running, the launcher auto-starts one in the background and connects to it.
- `[J]oin remote` — prompts for the host's IP / hostname (last one is remembered, so `J` then Enter reconnects), then for the 4-character room code.
- `[B]ack` returns to the top menu.

So a typical session: the host runs `npm run ching` → `2` → `H` → the launcher mints a room code and shows it in the lobby. Each friend runs `npm run ching` → `2` → `J` → types the host's IP → types the code.

Find the host's LAN IP with `ipconfig getifaddr en0` (macOS) or `hostname -I | awk '{print $1}'` (Linux).

### Auto-spawned daemon lifecycle

When `[H]ost` starts a daemon for you, that daemon is a **managed child** of the launcher: it shares the launcher's process group and exits when the launcher does (Ctrl-C, `[Q]uit`, normal termination, SIGTERM). Quitting the host therefore tears the room down for everyone — there's no orphan daemon for you to remember to kill later.

If you want a daemon that survives the host quitting (for an always-on Pi, for example), see "Hosting (always-on)" below.

### Hosting (always-on)

For a Pi or any persistent host where the daemon should outlive any single client:

```
npm run daemon
```

(Inside `tmux` or `screen` if you want it to survive your ssh session.)

The daemon listens on both transports:

- **Unix socket** `/tmp/ching.sock` (mode `0660`) for same-machine players. On startup it detects a stale socket file from an unclean restart, unlinks it, and rebinds, so Ctrl-C plus immediate restart is a no-op for the operator.
- **TCP** on `0.0.0.0:4321` for LAN players. `CHING_PORT` overrides the port; `CHING_PORT=0` disables TCP. `CHING_BIND` overrides the bind host.

The launcher's `[H]ost` will detect this standalone daemon on the socket and just connect to it instead of spawning its own.

> **Security**: there is no auth or TLS on the TCP port. This is intended for a **trusted home LAN** (the kind where you'd hand someone the wifi password). Anyone who can reach `host:4321` on the network can join or create rooms. Do not expose the port to the public internet without a VPN, firewall, or reverse proxy in front.

The daemon logs one line per event to stdout (`HH:MM:SS LEVEL room=XXXX seat=N MSG key=val`). Set `LOG_LEVEL=debug` to also see grace-timer ticks and per-connection lifecycle.

### Testing on one machine

For exercising both sides of a multiplayer session on a single host, set these env vars to bypass the interactive prompts:

- `CHING_NAME` overrides the display name (skips the first-run name prompt).
- `CHING_HOST` (and optional `CHING_PORT`) skip the menus and connect directly over TCP. Useful for headless / CI clients.
- `CHING_SESSION` points at a different session-token file so two clients on the same OS account don't clobber each other's reconnect tokens.

```
CHING_SESSION=/tmp/ching-a.json CHING_NAME=alice npm run join   # terminal A
CHING_SESSION=/tmp/ching-b.json CHING_NAME=bob   npm run join   # terminal B
```

The session file is keyed by transport target (`/tmp/ching.sock` or `tcp://host:port`) so one file can hold tokens for several daemons at once.

### Lobby flow

- One player picks `[C]reate room` and the daemon mints a 4-char code (letters and digits, excluding the easily-confused `0`, `O`, `I`, `L`, `1`).
- The others pick `[J]oin by code` and type those four characters.
- The host can `[A]dd AI` seats (default discipline `0.6`) to round out the room when only one friend is online.
- Everyone presses `[R]eady`. The host presses `[S]tart`.

### Disconnect and reconnect

- If a player's ssh session drops outside their turn, their seat goes "disconnected" and the game continues unaffected. They can reconnect at any time and reclaim the seat.
- If they drop on their turn, the other players see a 15-second countdown (`AI takes over in 15s…`, then `10s`, `5s`). If they reconnect before the timer expires, control goes back to them with no AI action played. If the timer expires, the AI plays the rest of their turn at `discipline 0.6`.
- Reconnecting during AI takeover is allowed; the AI finishes the current turn and the human resumes at the next turn boundary.
- Identity is bound to an opaque session token, persisted at `~/.ching/session.json`. Names are display-only; the token is what reclaims your seat. Reconnect from a different machine works the same way.

Rooms with no connected humans for 30 minutes (including ones with AI seats actively playing) are reaped. This catches the AFK-and-forgotten case.

### Persistence

There is no persistence in v1. A daemon restart loses all in-flight rooms. The game design (Heckmeck-style burn-on-bust) guarantees games end on the order of minutes, so this trade-off is fine to start with.

