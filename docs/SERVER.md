# Running a dedicated server

The game itself is the server: the ordinary Linux build started with `--server` runs
headless, with no window or sound. Players don't host; they pick **Online**, then
**Quick match** > **1 v 1 / 2 v 2 / 3 v 3** (whoever is waiting for that size) or **Rooms**
> **Create room** (with a room size) / **Join room** (a short code for friends), and then
their fighter. When a group is found, everyone must **Accept** within `--ready` seconds. Those use the game's server,
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
| `--cpu-fill=SECONDS` | 20 | a Quick match 2v2/3v3/4v4 that has waited this long starts with CPUs in the empty slots (0: never) |
| `--room-fill=SECONDS` | 45 | the same for a room (longer: friends are typing the code) |
| `--ready=SECONDS` | 15 | how long players have to accept a match found; those who accepted go back to waiting if someone doesn't |
| `--cpu-level=N` | 1 | how well those CPUs play: 0 Easy, 1 Normal, 2 Hard |

Players join `ADDRESS` or `ADDRESS:PORT`. Adding `/ROOM` (`game.example.net/kev`, not
case sensitive) pairs them only with someone who typed the same room; without one,
players are paired oldest first. Create room is the same thing with a made-up code.

**Rooms last between matches.** The server keeps a room for as long as a player is in
it: its maker's size, rules and arena hold throughout. After a match the players pick
fighters again (Next match) and the next one starts when all have locked in, with no
ready check; spectators stay on from match to match. One player leaving doesn't end it:
in a 1v1 room the other waits there for whoever types the code next; in a team room a
CPU finishes the match for the leaver, and someone joining the code meanwhile plays the
next one. A full room turns newcomers away (they can watch). The log shows it:

**A 1v1 rematch picks again too** (Quick match, tag Duels and ranked; not Quick match
2v2/3v3, which rematch with the same fighters). Once both players have asked, the server
holds the rematch while they pick (the finished match keeps being refereed), then starts
it with the new fighters as the next match number; spectators see the players picking
and follow into it. Nobody sees the other's pick until the match starts: the server
only says who has locked in. The pick has a countdown, `rematch_pick_seconds` in
`data/online.json` (20 s; the server reads it at start-up, the direct host too): when it
runs out, whoever hasn't locked in keeps their last fighter and the match starts. Once
both have locked in, the countdown drops to `rematch_locked_seconds` (3 s): both picks
show, they can't change any more, and the match starts when it ends. Each
Quick match rematch (ranked too, and team battles) is on a newly drawn arena, never the
one just played. Ranked rates every game. Someone leaving during the pick ends it for
the other ("Your opponent left") and its spectators, as leaving a Quick match does:

```
[2026-10-16 10:58:52] match 1: both want a rematch; picking fighters (20 s)
[2026-10-16 10:58:52] player 1 (cairn) locked in for the rematch
[2026-10-16 10:59:12] match 1: time's up for the rematch pick (1 of 2 locked in); the rest keep their fighters
[2026-10-16 10:59:12] match 2 started (rematch): player 1 (culvert) vs player 2 (sno) on floodgate, round trip 17 ms, input delay 1
```

Rooms:

```
[2026-10-15 20:02:11] match 3 started in room 'kx7p': player 4 (sno) vs player 5 (pete), round trip 38 ms, input delay 1
[2026-10-15 20:04:40] room 'kx7p' is picking fighters
[2026-10-15 20:04:52] player 5 (digby) locked in for room 'kx7p'
[2026-10-15 20:05:30] player 4 left
[2026-10-15 20:05:30] player 5 (digby) waits in room 'kx7p' again
[2026-10-15 20:09:02] room 'kx7p' closed
```

**Update the server with the clients.** This build's online protocol is NET_VERSION 11
(a 1v1 rematch picks again; ranked rematches): a server on an older build refuses these
games ("a different version of the game"), and this server refuses older games.

**CPU players.** In a team battle the server plays CPUs itself, on its referee's copy of
the match, and sends their inputs to everyone like a player's. It uses them in two cases:

- empty slots, once the first player has waited `--cpu-fill` (Quick match) or
  `--room-fill` (a room);
- a player who leaves mid-match: a CPU takes their slot and the others play on.

With two of you, both pick **Quick match** > **2 v 2**: after 20 seconds the match is
found (both accept), with a CPU on each team.

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

## Monitoring

[Netdata](https://www.netdata.cloud/) gives the box a live dashboard with history:
temperatures, CPU, memory, disks, network, and the `creature-arena` service's own CPU and
memory. It needs no setup beyond installing it, and has alerts built in.

```sh
sudo apt install -y lm-sensors smartmontools
sudo sensors-detect --auto       # finds the CPU and board temperature chips
sensors                          # should now print temperatures

wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
sh /tmp/netdata-kickstart.sh --stable-channel --disable-telemetry
```

Netdata Cloud is optional: skip it in the installer, and on the dashboard's sign-in
screen choose to use it without an account.

**Keep it on your own network.** Never forward port 19999 on the router. Let your network
in through the firewall (match its range, as for 7778):

```sh
sudo ufw allow from 192.168.0.0/24 to any port 19999 proto tcp
```

and make Netdata refuse everyone else (`sudo /etc/netdata/edit-config netdata.conf`,
then `sudo systemctl restart netdata`):

```ini
[web]
    allow connections from = localhost 192.168.* 100.*
```

Open `http://SERVER-IP:19999` from any device at home. Where to look:

| Section | What it shows |
| --- | --- |
| Sensors | CPU, board and drive temperatures |
| System Overview | CPU, load, memory, disk I/O, network |
| Systemd Services > creature-arena | the game server alone (see [Resources](#resources) for normal) |
| Disks / S.M.A.R.T. | drive health |

A temperature that creeps up over weeks while the load stays flat usually means dust or
a failing fan.

**Alerts in Discord.** Netdata already warns about overheating, a filling disk and memory
pressure; to get those on your phone, make a webhook (Discord channel settings >
Integrations > Webhooks > New Webhook > Copy URL), then
`sudo /etc/netdata/edit-config health_alarm_notify.conf`:

```sh
SEND_DISCORD="YES"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
DEFAULT_RECIPIENT_DISCORD="alerts"
```

```sh
sudo systemctl restart netdata
sudo -u netdata /usr/libexec/netdata/plugins.d/alarm-notify.sh test   # or /opt/netdata/usr/libexec/...
```

**From outside the house**, use [Tailscale](https://tailscale.com/) rather than opening a
port: it puts your phone on the home network privately (its addresses are the `100.*` in
the setting above).

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up                                     # log in with the link it prints
sudo ufw allow in on tailscale0 to any port 19999 proto tcp
```

Install the Tailscale app on the phone with the same account and open
`http://SERVER-NAME:19999`.

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

Both reports should show `"desync_frame": -1`, and the server logs the result. With
`--cpu-vs-cpu` they carry on by themselves: in a room into the room's next match, in
Quick match (no `/test`) a 1v1 asks for a rematch; either way each picks the next
fighter along. The report holds the latest match (`"match"`, `"teams"`); each earlier
one is kept beside it as `a_m1.json`, `a_m2.json`... `--net-no-pick[=N]` on one of them
leaves its first N rematch picks (or all) to the countdown. Add a spectator with
`godot --path . -- --online-watch=127.0.0.1:7799/test` (or without `/test` for Quick
match).
