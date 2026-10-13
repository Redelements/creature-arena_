# Running a dedicated server

The game itself is the server: the ordinary Linux build started with `--server` runs
headless, with no window or sound. Players don't host; they pick **Online**, then
**Quick match 1v1 / 2v2 / 3v3** (whoever is waiting for that size) or **Create room** (with
a room size) / **Join room** (a short code for friends). Those use the game's server,
`server` in `data/online.json`, or the one set in **Settings > Game > Online server**. Any
server can also be joined by address under **More**. The server groups 2, 4 or 6 players,
relays their match and referees it with its own copy of the game (design:
[NETCODE.md](NETCODE.md#dedicated-server-built)). A 2v2 needs four players waiting and a
3v3 six; until then each player sees how many are there.

A full step-by-step home setup (Ubuntu Server install, static IP, router, firewall, a
free domain name, updates) is in the **Creature Arena home server guide** doc. This page
is the short reference.

## Command line

```sh
./CreatureArena.x86_64 --headless -- --server            # UDP port 7777
./CreatureArena.x86_64 --headless -- --server=7800 --max-players=16 --net-delay=2
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--server[=PORT]` | 7777 | run as a server on this UDP port |
| `--max-players=N` | 32 | players connected at once (16 matches); more are told the server is full |
| `--net-delay=N` | picked per match | force every match's input delay (frames) |
| `--cpu-fill=SECONDS` | 20 | a Quick match 2v2/3v3 that has waited this long starts with CPUs in the empty slots (0: never) |
| `--room-fill=SECONDS` | 45 | the same for a room (longer: friends are typing the code) |
| `--cpu-level=N` | 1 | how well those CPUs play: 0 Easy, 1 Normal, 2 Hard |

Players join `ADDRESS` or `ADDRESS:PORT`. Adding `/ROOM` (`game.example.net/kev`, not
case sensitive) pairs them only with someone who typed the same room; without one,
players are paired oldest first. Create room is the same thing with a made-up code.

**CPU players.** In a team battle the server plays CPUs itself, on its referee's copy of
the match, and sends their inputs to everyone like a player's. It uses them in two cases:

- empty slots, once the first player has waited `--cpu-fill` (Quick match) or
  `--room-fill` (a room);
- a player who leaves mid-match: a CPU takes their slot and the others play on.

With two of you, both press **Quick match 2v2**: after 20 seconds the match starts, with
a CPU on each team.

**Players at the server's own house.** Many routers can't loop their public address back
inside, so the public name fails from the server's own network. Before joining its
server, the game broadcasts a question on the local network, and the server answers on
**UDP port + 1** (7778 by default) with its game port; the game then joins that local
address. Let the question in from your network only (match your network's range):

```sh
sudo ufw allow from 192.168.0.0/24 to any port 7778 proto udp
```

Without the rule, players at home just join the public name (and may get no answer).
Never forward 7778 on the router: it's only for the local network.

**Same build everywhere.** The server and both players need the same build (the same
game data). The first log line shows `game data <hash>`; a player with another build is
told "The server runs a different version of the game". Update the server whenever you
hand out a new build.

## What it logs

One line per event, to standard output (so `journalctl -u creature-arena -f` under
systemd):

```
[2026-10-11 13:21:08] Creature Arena server on UDP port 7777 (protocol 3, game data 67e12f686788fffb), up to 32 players
[2026-10-11 13:21:08] players on this network join 192.168.0.103:7777
[2026-10-11 13:21:08] games on this network find the server by itself (UDP port 7778; allow it in the firewall)
[2026-10-11 13:21:08] player 1 connected from 203.0.113.9:53086
[2026-10-11 13:21:08] player 1 (digby) is waiting in room 'kev'
[2026-10-11 13:21:08] match 1 started: player 1 (digby) vs player 2 (sno), round trip 41 ms, input delay 1
[2026-10-11 13:22:51] match 1 over: player 2 (sno) won (48 fingerprints checked)
[2026-10-11 13:30:02] match 2 started: player 3 (cairn) + player 5 (barkley) vs player 4 (culvert) + player 6 (pete), round trip 52 ms, input delay 1
[2026-10-11 13:31:40] match 2 over: the right team won (96 fingerprints checked)
```

Every 10 minutes it prints how many players and matches there are. A line saying a
player's game "went out of sync" is a bug: that player's desync report (in their game's
`desyncs` folder) replays it exactly.

## Resources

About 5% of one CPU core idle and ~150 MB of memory; each match adds one copy of the
simulation stepping at 60 Hz (well under 1 ms a frame). Bandwidth is tiny: a few KB/s per
player. Any always-on PC, mini PC or Raspberry Pi-class x86 box is plenty. The binary
needs only glibc, so a minimal Ubuntu Server install runs it.

## systemd service

`/etc/systemd/system/creature-arena.service`:

```ini
[Unit]
Description=Creature Arena dedicated server
After=network-online.target
Wants=network-online.target

[Service]
User=arena
Group=arena
WorkingDirectory=/opt/creature-arena
ExecStart=/opt/creature-arena/CreatureArena.x86_64 --headless -- --server=7777
Restart=on-failure
RestartSec=5
# Hardening: the server only needs its own folder and its home (Godot's user://).
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/creature-arena
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

`systemctl stop` ends it at once: Godot doesn't let scripts catch the signal, so players
mid-match see the connection drop within 5 seconds. Restart between matches (the log
shows when nobody's playing).

## Updating to the latest main build

Builds are GitHub Actions artifacts (kept 30 days; downloading needs a GitHub login, so
run `gh auth login` once). `/opt/creature-arena/update.sh`:

```sh
#!/bin/sh
# Downloads the newest successful main build and restarts the server on it.
set -e
REPO=Redelements/creature-arena_
RUN=$(gh run list -R $REPO -w playable-build.yml -b main -s success -L 1 --json databaseId -q '.[0].databaseId')
TMP=$(mktemp -d)
gh run download "$RUN" -R $REPO -p 'CreatureArena-linux-*' -D "$TMP"
BIN=$(find "$TMP" -name CreatureArena.x86_64 | head -n 1)
sudo install -m 755 -o root -g root "$BIN" /opt/creature-arena/CreatureArena.x86_64
rm -rf "$TMP"
sudo systemctl restart creature-arena
journalctl -u creature-arena -n 3 --no-pager
```

Players get the Windows build of the same run from that PR's or commit's build comment.

## Trying it on one machine

```sh
godot --headless --path . -- --server=7799 &
godot --path . -- --online-join=127.0.0.1:7799/test --cpu-vs-cpu --net-report=a.json &
godot --path . -- --online-join=127.0.0.1:7799/test --cpu-vs-cpu --net-report=b.json
```

Both reports should show `"desync_frame": -1`, and the server logs the result.
