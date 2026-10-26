#!/bin/sh
# Installs the latest main build on the dedicated server and restarts it on it.
# Copy to /opt/creature-arena/update.sh (owned by root, mode 755); docs/SERVER.md has
# the setup, including the read-only GitHub token `gh` uses here.
#
# Only a build that GitHub Actions made for a push to main, of the commit main points
# at right now, from this repository, is installed. A pull request's build is never
# picked, even one from a fork whose branch is also called "main".
set -eu
REPO=Redelements/creature-arena_
WORKFLOW=playable-build.yml

fail() {
  echo "update.sh: $*" >&2
  echo "update.sh: nothing was installed; the server keeps running its current build." >&2
  exit 1
}

SHA=$(gh api "repos/$REPO/commits/main" -q .sha) || fail "couldn't read main's head commit from GitHub"
[ -n "$SHA" ] || fail "couldn't read main's head commit from GitHub"
echo "main is at $SHA"

RUN=$(gh run list -R "$REPO" -w "$WORKFLOW" -b main -e push -s success -L 20 \
  --json databaseId,headSha,event,headBranch \
  -q "map(select(.headSha == \"$SHA\" and .event == \"push\" and .headBranch == \"main\"))[0].databaseId // empty") \
  || fail "couldn't list the build runs"
[ -n "$RUN" ] || fail "no successful push build of main $SHA yet (still running, failed, or main just moved): try again later"

# Ask GitHub about that run directly as well: the same commit, a push to main, built
# in this repository (not a fork), and successful.
CHECK=$(gh api "repos/$REPO/actions/runs/$RUN" \
  -q '[.head_sha, .event, .head_branch, .head_repository.full_name, .conclusion] | join(" ")') \
  || fail "couldn't read run $RUN"
[ "$CHECK" = "$SHA push main $REPO success" ] || fail "run $RUN isn't a successful push build of main $SHA in $REPO ($CHECK)"
echo "installing the build from run $RUN"

SHORT=$(printf '%s' "$SHA" | cut -c1-7)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
gh run download "$RUN" -R "$REPO" -n "CreatureArena-linux-$SHORT" -D "$TMP" \
  || fail "couldn't download the Linux build of run $RUN"
BIN=$(find "$TMP" -name CreatureArena.x86_64 | head -n 1)
{ [ -n "$BIN" ] && [ -s "$BIN" ]; } || fail "the download has no CreatureArena.x86_64"
echo "sha256 (the run's \"Export builds\" step prints the same):"
sha256sum "$BIN"

sudo install -m 755 -o root -g root "$BIN" /opt/creature-arena/CreatureArena.x86_64
STARTED=$(date '+%Y-%m-%d %H:%M:%S')
sudo systemctl restart creature-arena
sleep 3
echo "server log since the restart:"
journalctl -u creature-arena --since "$STARTED" --no-pager | tail -n 5
