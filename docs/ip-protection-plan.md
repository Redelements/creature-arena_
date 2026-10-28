# Protecting the game before release, on a budget

Kevin's plan (2026-10-28) for keeping Ready 4 Rambles from being copied before it ships,
without spending money. Status marks: DONE, NEXT (ready to do), LATER (waits on a date or
a decision). The repository is public on purpose until the step that says otherwise.

## Now, while still public (free)

1. **DONE: a licence notice.** `LICENSE` at the root reserves all rights (PR #281);
   `LICENSES.md` keeps the bought-art terms. It is the legal basis. It stops nobody by itself.
2. **DONE: no playable builds for pull requests.** Every artifact of a public repository can
   be downloaded by anyone signed in to GitHub, so a stranger could play the current game in
   two clicks without building anything. `playable-build.yml` now runs on pushes to main and by
   hand (Actions > playable build > Run workflow, pick the branch; the bot comment then lands on
   that branch's PR) and keeps builds three days instead of thirty.
3. **DONE: CI trimmed for a private future.** The macOS determinism check moved to
   `nightly.yml` (a macOS minute is billed as ten Linux minutes), and the per-PR Linux versus
   Windows check moved to `determinism.yml`, run from the stock editor binaries, uploading only
   two one-line digest files. A push now costs about 8 billed minutes instead of 46.

## Before the Steam page goes up: go private

4. **LATER: flip the repository private** the day before anything public points at it
   (Settings > General > Danger zone > Change visibility). Zero cost. With the trimmed CI the
   free 2,000 Actions minutes a month cover roughly 250 pushes. What changes: artifact and
   PR-media links need a GitHub login (only Kevin uses them); stars, watchers and traffic reset
   (none today); the server's `update.sh` already downloads builds with a token, so it keeps
   working. Past clones stay out there; going private stops new ones.
5. **LATER, only if minutes run short: a self-hosted runner** on the home server or the dev
   PC runs the Linux tests for free, without limits. Steps (GitHub's own instructions are under
   Settings > Actions > Runners > New self-hosted runner; summary):
   - On the machine: create a user with no sudo, download the runner tarball GitHub shows,
     check its SHA256 against the one on that page, `./config.sh --url <repo> --token <token>`
     (the token on that page lives an hour), `sudo ./svc.sh install && sudo ./svc.sh start`.
   - Give it the labels `self-hosted, linux`. In `tests.yml` change `runs-on: ubuntu-latest` to
     `runs-on: [self-hosted, linux]` for the shard job only; keep the determinism Windows job
     and the builds on GitHub's runners.
   - A self-hosted runner must never run workflows from forks or from pull requests by
     strangers (it runs their code on your machine): keep the repository private, or set
     Settings > Actions > "Require approval for all outside collaborators" before using it.
   - GitHub Pro (4 dollars a month, 3,000 minutes) is the alternative that needs no machine.
6. **LATER: drop macOS entirely** unless the game ships on Mac. Linux versus Windows already
   catches the rounding differences rollback cares about; the nightly macOS job is the one
   remaining macOS cost and can be deleted from `nightly.yml` in one line.

## At release

7. **NEXT when a release build exists: encrypt the data pack.** Godot ships scripts as readable
   text inside the `.pck`, and decompilers exist, so a shipped build is otherwise the source.
   Godot supports PCK encryption (Project > Export > Encryption: a 256-bit key, "Encrypt
   exported PCK" and "Encrypt index") with the key baked into **custom export templates**
   built from the engine source with `SCRIPT_AES256_ENCRYPTION_KEY` set. Plan: a
   `release-build.yml` run by hand only, which compiles the Linux and Windows templates with the
   key from a repository secret (the only secret any workflow would hold), exports with
   encryption on, and uploads the builds for Kevin to download and upload to Steam. The
   templates compile in about an hour a platform on a GitHub runner; cache them by Godot
   version. The key never enters the repository, the dev builds or CI logs. Steam's own DRM
   wrapper adds little; skip it.
8. **Accept the rest.** After release, protection is being first and updating faster than any
   copy. Nothing stops a determined decompiler, and copies of games that aren't selling are not
   worth anyone's time.

## Money

| Item | Cost | Note |
| --- | --- | --- |
| GitHub, private repository with the trimmed CI | 0 | self-hosted runner if ever short |
| Steam Direct fee | 100 once | recouped from the first thousand dollars of sales |
| Google Play, if Android ships | 25 once | wait for PC sales |
| Apple developer | 99 a year | skip for now |
| Audio: Kenney CC0 plus one licensed music pack | 0 to 40 | the Kenney pass waits on a ruling |
| Server | 0 | the home box |
| Trailer, store art, captures | 0 | `tools/capture_gallery.py` and the showcases |

## Who does what

- Claude: items 2, 3 (done), the runner instructions (above), item 7 when asked.
- Kevin: the moment to flip private (4), the Steam account, installing a runner if we go that
  way (5), the macOS decision (6), the encryption key and the Steam upload (7).
