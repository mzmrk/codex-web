# Downstream maintenance

This fork keeps main as an exact mirror of 0xcaff/codex-web:main.
The codex/docker branch contains a linear stack of compatibility, Docker,
and automation commits rebased on top of that upstream history.

## Automated updates

The Rebase downstream and publish workflow runs every six hours and can also
be started manually. When upstream changes, it:

1. fetches upstream/main;
2. rebases every downstream commit onto the new upstream tip;
3. builds the complete Docker image;
4. updates codex/docker with an exact force-with-lease;
5. fast-forwards the fork's main mirror; and
6. publishes latest and an upstream-SHA tag to GHCR.

The remote downstream branch is not modified until the full rebase and Docker
build succeed. A conflict or build failure leaves the last known-good branch
and image unchanged.

Immediately before replacing a successfully rebuilt downstream branch, the
workflow preserves its previous tip as
`codex/archive/YYYY-MM-DD_HHMMSSZ`. These immutable, UTC-dated branches keep
the history of earlier downstream stacks available after rebases.

## Optional passwordless sudo

The published image runs codex-web as the unprivileged `node` user by default.
Passwordless sudo is disabled by default. The container entrypoint accepts
`true`, `1`, or `yes` to enable it and accepts `false`, `0`, `no`, or an empty
value to disable it. Any other value stops the container with an error.

To enable passwordless sudo for the configured runtime user, change the value
in `compose.yml`:

```yaml
environment:
  CODEX_PASSWORDLESS_SUDO: true
  PGID: 1000
  PUID: 1000
```

Then pull the published image and recreate the container without building it
locally:

```sh
docker compose pull
docker compose up -d --force-recreate
docker compose exec --user 1000:1000 codex-web id
docker compose exec --user 1000:1000 codex-web sudo -n id
```

The first identity command reports the configured runtime user. With
passwordless sudo enabled, the second reports `root`. To disable it again, set
the value to `false`, then recreate the container. `sudo -n id` will fail while
passwordless sudo is disabled.

Enabling this option allows processes running as the selected runtime user to
become root inside the container. Keep it disabled unless a task specifically
requires package or system-level changes.

### Custom runtime user

Set `PUID` and `PGID` directly in `compose.yml` instead of using Compose's
`user` field when persisted files must use a specific numeric identity:

```yaml
environment:
  PGID: 1032
  PUID: 1032
```

The container starts as root so its entrypoint can create a local account,
update ownership of the persisted Codex state, and configure sudo. It then
launches codex-web through `gosu` as the selected runtime account. The host
directory `./codex-auth` is mounted at `/home/node/.codex` so Codex state is
stored alongside the Compose deployment while remaining outside Git. Project
files in `./workspace` are mounted at `/home/node/Documents`.

Because the image's configured user is root, a plain `docker compose exec`
opens an administrative shell. Specify the runtime identity when verifying or
running an unprivileged command:

```sh
docker compose exec --user 1032:1032 codex-web id
docker compose exec --user 1032:1032 codex-web sudo -n id
```

The first command reports UID and GID 1032. The second reports root only while
`CODEX_PASSWORDLESS_SUDO` is enabled. `docker top codex-web` can be used to
confirm that the long-running application processes use the selected identity.

The default `compose.yml` publishes only Caddy on port 8214; codex-web is
reachable only over the dedicated Compose network. Use `compose.direct.yml`
when an unencrypted, localhost-only direct port is explicitly preferred.

## Resolving a failed rebase

Fetch both remotes, reset the local downstream branch to origin/codex/docker,
and rebase it onto upstream/main. Resolve the conflicting commit, stage the
resolved files, and run git rebase --continue.

After validation, update the branch using an exact force-with-lease rather than
an unconditional force push.
