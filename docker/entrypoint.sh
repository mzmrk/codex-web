#!/bin/sh
set -eu

fail() {
  printf 'codex-web entrypoint: %s\n' "$*" >&2
  exit 64
}

puid=${PUID:-1000}
pgid=${PGID:-1000}
passwordless_sudo=${CODEX_PASSWORDLESS_SUDO:-false}
sudoers_rule=/etc/sudoers.d/010-node-nopasswd

case "$puid" in
  ''|*[!0-9]*) fail "invalid PUID: $puid" ;;
esac
case "$pgid" in
  ''|*[!0-9]*) fail "invalid PGID: $pgid" ;;
esac
[ "$puid" -ne 0 ] || fail 'PUID must select a non-root user'

ensure_group() {
  requested_gid=$1
  existing_group=$(getent group "$requested_gid" | cut -d: -f1 || true)
  if [ -n "$existing_group" ]; then
    printf '%s\n' "$existing_group"
    return
  fi

  new_group="codex-runtime-$requested_gid"
  groupadd --gid "$requested_gid" "$new_group"
  printf '%s\n' "$new_group"
}

startup_groups=$(id -G)
runtime_group=$(ensure_group "$pgid")
runtime_user=$(getent passwd "$puid" | cut -d: -f1 || true)

if [ -z "$runtime_user" ]; then
  runtime_user="codex-runtime-$puid"
  useradd \
    --uid "$puid" \
    --gid "$runtime_group" \
    --home-dir /home/node \
    --no-create-home \
    --shell /bin/sh \
    "$runtime_user"
elif [ "$(id -g "$runtime_user")" -ne "$pgid" ]; then
  usermod --gid "$runtime_group" "$runtime_user"
fi

for supplemental_gid in $startup_groups; do
  if [ "$supplemental_gid" -eq 0 ] || [ "$supplemental_gid" -eq "$pgid" ]; then
    continue
  fi
  supplemental_group=$(ensure_group "$supplemental_gid")
  usermod --append --groups "$supplemental_group" "$runtime_user"
done

chown "$puid:$pgid" /home/node
if [ -d /home/node/.codex ]; then
  state_owner=$(stat -c '%u:%g' /home/node/.codex)
  if [ "$state_owner" != "$puid:$pgid" ]; then
    chown -R "$puid:$pgid" /home/node/.codex
  fi
fi

case "$passwordless_sudo" in
  true|1|yes)
    printf '%s\n' 'node ALL=(ALL) NOPASSWD: ALL' > "$sudoers_rule"
    if [ "$runtime_user" != node ]; then
      printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$runtime_user" >> "$sudoers_rule"
    fi
    chown root:root "$sudoers_rule"
    chmod 0440 "$sudoers_rule"
    if ! visudo -cf "$sudoers_rule" >/dev/null; then
      rm -f "$sudoers_rule"
      exit 1
    fi
    ;;
  false|0|no|'')
    rm -f "$sudoers_rule"
    ;;
  *)
    rm -f "$sudoers_rule"
    fail "invalid CODEX_PASSWORDLESS_SUDO value: $passwordless_sudo (expected true|1|yes|false|0|no or empty)"
    ;;
esac

exec gosu "$runtime_user" "$@"
