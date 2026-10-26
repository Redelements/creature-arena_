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
free domain name, updates) is in the **home server guide** doc (titled "Creature Arena
home server guide", from before the rename). This page is the short reference.

## Command line

The Linux binary keeps its old name, `CreatureArena.x86_64` (and so do the service, its
paths and the CI artifact `update.sh` downloads), so the server updates as before.

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
| `--max-per-ip=N` | 6 | connections at once from one address (a household behind one router still fits a 2v2 and spectators); 0: no limit |
| `--ranked-same-ip` | off | let two games behind one address play each other ranked (a LAN party, or testing on one machine) |
| `--reset-player=ID` | | forget the secret bound to that player id in `ratings.json`, then exit (see "Ranked identity") |

**Limits.** The server keeps any one connection from costing more than a player does
(the numbers are named constants at the top of `src/net/relay_server.gd`, `referee.gd` and
`enet_hub.gd`):

- every message's fields must have the right types, or the message is ignored; packets
  are checked before they're decoded, and a packet over 8 KB after hello (256 KB before
  it, for a Daily replay) closes the connection;
- a connection sending more than about 240 messages a second (480 at once) is dropped;
- only a seated player sends inputs, fingerprints, rematch and pick for their own slot
  (spectators only watch);
- a match is refereed no faster than the clock and at most 8 frames per loop, stops being
  simulated 10 s after its result (inputs still pass, so the match-over keeps running)
  and after 30 minutes at most; fingerprints and inputs it can't use aren't relayed;
- Daily scores are checked one at a time, 120 frames per loop (a few ms added to each
  loop while one runs, so matches keep being relayed; a full fight takes about a third of
  a second), at most 4 waiting and 30 a minute; one request per connection, and that
  connection is let go after 15 s;
- anyone quiet for 10 s is pinged (every game answers), and dropped after 60 s;
- the newest `server_replays_keep` match replays are kept (500, `data/online.json`).

The log says why a connection was dropped ("sent too many messages", "sent a packet too
big", "went quiet", ...).

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

**Update the server with the clients.** The protocol (`NET_VERSION` in
`src/net/netplay.gd`, printed in the first log line) changes with most releases: a server
on an older build refuses newer games ("a different version of the game"), and a newer
server refuses older games the same way, so update both together.

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
Never forward 7778 on the router: it's only for the local network. The game only takes
an answer from a server of exactly its own build (the same protocol and game data); any
other answer on the network (an older server, or a stranger's on a shared network) is
ignored and the public name is used instead, so keep the server up to date.

**Same build everywhere.** The server and both players need the same build (the same
game data). The first log line shows `game data <hash>`; a player with another build is
told "The server runs a different version of the game". Update the server whenever you
hand out a new build.

## Ranked identity and the ratings file

Ratings and Daily scores live in the server's `user://ratings.json` (under systemd,
`~arena/.local/share/godot/app_userdata/Creature Arena/ratings.json`; the folder keeps the
game's old name on purpose, see `custom_user_dir_name` in project.godot).

- **Who a player is.** Each game makes a player id and a secret once and keeps them in its
  settings (`settings.cfg` in the game's user folder: `[online] id` and `secret`). The
  secret is never shown or sent to other players; only ranked and Daily connections send
  it, to the server. The server stores just a hash of id and secret (`keys` in
  `ratings.json`), never the secret.
- **Existing ratings.** Nothing is lost on the update. An id that already has a rating or
  a Daily score but no key is bound to the first game that claims it with a secret
  (normally its owner's, on their first ranked game or Daily after updating). From then
  on a game with the same id and another secret is refused ("The server knows your
  player id from another copy of the game"), and its rating and name are left alone.
- **Losing the settings loses the ranked identity.** A player who deletes their settings
  or moves to another computer gets a new id (a fresh rating). To give them their old
  one back, they copy `id` and `secret` from the old `settings.cfg`; if the secret is gone
  too, reset their player and they copy only the old `id`: their next ranked game or
  Daily binds the new secret, rating and scores kept. Find the id by their name in
  `ratings.json` (`players`), then:

  ```sh
  sudo systemctl stop creature-arena
  sudo -u arena /opt/creature-arena/CreatureArena.x86_64 --headless -- --server --reset-player=0123456789abcdef
  sudo systemctl start creature-arena
  ```

- **One game per player.** One ranked connection and one Daily connection per id at a
  time: a second is turned away ("You're already in ranked from another game") until the
  first leaves or times out (60 s). Ranked never pairs two games from the same address
  (`--ranked-same-ip` allows it).
- **Daily scores** are taken for the server's UTC date and the day either side only, and
  the server replays each one against the day's CPU itself: a replay its CPU doesn't play
  the same way is refused (and logged). The last 60 days are kept, up to 5000 players a day.
- **A safe file.** Every save writes `ratings.json.tmp` and renames it over
  `ratings.json`, keeping the previous one as `ratings.json.bak`, so a crash or a full disk
  mid-save never loses the book. A `ratings.json` that can't be read at start-up is moved
  to `ratings.json.corrupt-<time>` (never overwritten), the log says so in capitals
  (`RATINGS FILE UNREADABLE`), and the `.bak` is loaded instead.

## What it logs

One line per event, to standard output (so `journalctl -u creature-arena -f` under
systemd):

```
[2026-10-11 13:21:08] Ready 4 Rambles server on UDP port 7777 (protocol 3, game data 67e12f686788fffb), up to 32 players
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
Description=Ready 4 Rambles dedicated server
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

### Tighter limits (a drop-in)

The game port faces the internet, so the service should be able to do as little as
possible and never take the whole box down with it. Add these on top of the unit with
`sudo systemctl edit creature-arena` (it writes
`/etc/systemd/system/creature-arena.service.d/override.conf`):

```ini
[Unit]
# Restarted at most 5 times in 5 minutes; after that it stays down (a crash loop).
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
# Restart on a crash, not on a clean stop.
Restart=on-failure
RestartSec=5
# A runaway server is killed at 4 GB instead of pushing the box into swap.
MemoryMax=4G
TasksMax=256
# Nothing to gain: no setuid, no new privileges, no capabilities.
NoNewPrivileges=true
CapabilityBoundingSet=
AmbientCapabilities=
RestrictSUIDSGID=true
# The file system is read-only except its own data folder (Godot's user://, where the
# ratings, daily scores and saved replays live); /tmp is private; no home folders.
ProtectSystem=strict
ReadWritePaths=/var/lib/creature-arena
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
UMask=0077
# No kernel, clock, hostname or control-group changes.
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
# Only the sockets a game server needs.
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictNamespaces=true
RestrictRealtime=true
LockPersonality=true
SystemCallArchitectures=native
```

Then:

```sh
sudo systemctl daemon-reload && sudo systemctl restart creature-arena
journalctl -u creature-arena -n 5 --no-pager        # "Ready 4 Rambles server on UDP port 7777"
systemctl show creature-arena -p MemoryMax -p ProtectSystem -p ReadWritePaths -p Restart
systemd-analyze security creature-arena | tail -1   # lower is better
```

Join it once from a game to check. If it won't start, `journalctl -u creature-arena -n 30`
says why: remove the last lines you added and try again. `MemoryDenyWriteExecute` is
left out on purpose (Godot's script engine may need it). If the data folder is somewhere
else (`getent passwd arena` shows the home), use that path in `ReadWritePaths`.

### Keep the logs from filling the disk

Every log line goes to journald. Cap it in `/etc/systemd/journald.conf`, under
`[Journal]`:

```ini
SystemMaxUse=1G
```

then `sudo systemctl restart systemd-journald`, and check with `journalctl --disk-usage`.

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

and make Netdata listen on the server's LAN address only and refuse everyone else
(`sudo /etc/netdata/edit-config netdata.conf`, then `sudo systemctl restart netdata`;
use the server's own address and your network's range):

```ini
[web]
    bind to = localhost 192.168.0.103
    allow connections from = localhost 192.168.*
    allow connections by dns = no
```

`sudo ss -tlpn | grep 19999` should then show `192.168.0.103:19999` and `127.0.0.1:19999`,
not `*:19999`. The dashboard has no login: anyone on your Wi-Fi (guests too) can see it.

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

The webhook URL is a secret (anyone with it can post to the channel). Keep the file
readable by Netdata only:

```sh
sudo chown root:netdata /etc/netdata/health_alarm_notify.conf
sudo chmod 640 /etc/netdata/health_alarm_notify.conf
sudo stat -c '%U:%G %a' /etc/netdata/health_alarm_notify.conf   # root:netdata 640
```

If it ever leaks (a screenshot, a pasted config), delete the webhook in Discord and make
a new one.

The dashboard is for checking from home: away from the home network it doesn't load.

## Updating to the latest main build

Builds are GitHub Actions artifacts (kept 30 days; downloading needs a GitHub token).
The script is [`tools/server/update.sh`](../tools/server/update.sh) in the repository.
It installs only the build GitHub made for a **push to main, of the commit main points
at now**, built in this repository. A pull request's build is never installed (a fork's
branch can also be called `main`), and if main's newest build hasn't finished or
failed, it refuses and changes nothing:

```
update.sh: no successful push build of main 3f04189... yet (still running, failed, or main just moved): try again later
update.sh: nothing was installed; the server keeps running its current build.
```

It prints the binary's SHA-256, the same figure the run's "Export builds" step prints,
and then the server's log lines since the restart.

**Install or update the script** (from a checkout, or download the file from GitHub and
read it first):

```sh
sudo install -m 755 -o root -g root tools/server/update.sh /opt/creature-arena/update.sh
diff tools/server/update.sh /opt/creature-arena/update.sh && echo same
```

Root owns it and nobody else can write it, since it runs `sudo`. Run it as your own user
(`/opt/creature-arena/update.sh`), not as `arena`.

### A read-only GitHub token for the box

`gh auth login`'s default token can write to every repository you own. The server's
game port faces the internet, so give the box a token that can only read this one
repository's builds:

1. On github.com: **Settings > Developer settings > Personal access tokens >
   Fine-grained tokens > Generate new token**.
2. Name it `creature-arena server`, expiration 90 days (a reminder to rotate it), resource
   owner Redelements, **Only select repositories**: `Redelements/creature-arena_`.
3. Repository permissions: **Actions: Read-only** and **Contents: Read-only** (Metadata:
   Read-only is added by itself). Nothing else, no account permissions.
4. Generate it and copy it once into a file on the box, as the user who runs update.sh:
   ```sh
   gh auth logout                        # drops the old full-access login, if any
   umask 077; cat > ~/gh-token.txt       # paste the token, Enter, then Ctrl+D
   gh auth login --with-token < ~/gh-token.txt && shred -u ~/gh-token.txt
   gh auth status                        # a github_pat_ token, and no "Token scopes: 'repo'"
   ```
5. Check: `/opt/creature-arena/update.sh` still downloads and installs. After 90 days
   GitHub emails a reminder; make a new token the same way.

Then revoke the old token on github.com (**Settings > Applications > Authorized OAuth
Apps > GitHub CLI**, if the box was the only place it was used).

**GitHub settings that go with it** (repository **Settings > Actions > General**): under
"Approval for running fork pull request workflows from contributors", choose **Require
approval for all external contributors**, and keep main's branch protection.

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
