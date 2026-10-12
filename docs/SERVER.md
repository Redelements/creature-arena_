# Running a dedicated server

The game itself is the server: the ordinary Linux build started with `--server` runs
headless, with no window or sound. Players don't host; they pick **Online**, type the
server's address on the **Join** row and press Enter. Two players are paired, the server
relays their match and referees it with its own copy of the game (design:
[NETCODE.md](NETCODE.md#dedicated-server-built)).

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

Players join `ADDRESS` or `ADDRESS:PORT`. Adding `/ROOM` (`game.example.net/kev`, not
case sensitive) pairs them only with someone who typed the same room; without one,
players are paired oldest first.

**Same build everywhere.** The server and both players need the same build (the same
game data). The first log line shows `game data <hash>`; a player with another build is
told "The server runs a different version of the game". Update the server whenever you
hand out a new build.

## What it logs

One line per event, to standard output (so `journalctl -u creature-arena -f` under
systemd):

```
[2026-10-11 13:21:08] Creature Arena server on UDP port 7777 (protocol 2, game data 67e12f686788fffb), up to 32 players
[2026-10-11 13:21:08] player 1 connected from 203.0.113.9:53086
[2026-10-11 13:21:08] player 1 (digby) is waiting in room 'kev'
[2026-10-11 13:21:08] match 1 started: player 1 (digby) vs player 2 (sno), round trip 41 ms, input delay 1
[2026-10-11 13:22:51] match 1 over: player 2 (sno) won (48 fingerprints checked)
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
