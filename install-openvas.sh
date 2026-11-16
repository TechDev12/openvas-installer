#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${OPENVAS_IMAGE:-immauss/openvas:latest}"
CONTAINER="${OPENVAS_CONTAINER:-openvas}"
VOLUME="${OPENVAS_VOLUME:-openvas}"
WEB_PORT="${OPENVAS_WEB_PORT:-8080}"
BIND_IP="${OPENVAS_BIND_IP:-$(hostname -I | awk '{print $1}')}"
STARTUP_TIMEOUT="${OPENVAS_STARTUP_TIMEOUT:-1800}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || die "Docker is not installed."
command -v curl >/dev/null 2>&1 || die "curl is not installed."
[[ -n "$BIND_IP" ]] || die "Could not determine the host IP. Set OPENVAS_BIND_IP explicitly."

sudo docker info >/dev/null 2>&1 || die "Cannot access the Docker daemon with sudo."

if sudo docker container inspect "$CONTAINER" >/dev/null 2>&1; then
  die "Container '$CONTAINER' already exists; this script is for a fresh install."
fi

if sudo docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  die "Volume '$VOLUME' already exists; this script is for a fresh install."
fi

read -rsp "OpenVAS admin password: " OPENVAS_PASSWORD
printf '\n'
read -rsp "Confirm password: " OPENVAS_PASSWORD_CONFIRM
printf '\n'

[[ -n "$OPENVAS_PASSWORD" ]] || die "Password cannot be empty."
[[ "$OPENVAS_PASSWORD" == "$OPENVAS_PASSWORD_CONFIRM" ]] || die "Passwords do not match."
unset OPENVAS_PASSWORD_CONFIRM

ENV_FILE="$(mktemp)"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    shred -u "$ENV_FILE" 2>/dev/null || rm -f "$ENV_FILE"
  else
    rm -f "$ENV_FILE"
  fi
}
trap cleanup EXIT
chmod 600 "$ENV_FILE"
printf 'PASSWORD=%s\nSKIPSYNC=true\n' "$OPENVAS_PASSWORD" >"$ENV_FILE"

printf 'Installing OpenVAS on %s:%s...\n' "$BIND_IP" "$WEB_PORT"

# Redis recommends this setting for reliable background persistence.
printf 'vm.overcommit_memory = 1\n' |
  sudo tee /etc/sysctl.d/99-openvas.conf >/dev/null
sudo sysctl -w vm.overcommit_memory=1 >/dev/null

sudo docker pull "$IMAGE"
sudo docker volume create "$VOLUME" >/dev/null

sudo docker run --detach \
  --restart unless-stopped \
  --publish "${BIND_IP}:${WEB_PORT}:9392" \
  --publish 9390:9390 \
  --publish 9391:9391 \
  --env-file "$ENV_FILE" \
  --volume "${VOLUME}:/data" \
  --name "$CONTAINER" \
  "$IMAGE" >/dev/null

printf 'Waiting for the OpenVAS web service and manager...\n'
deadline=$((SECONDS + STARTUP_TIMEOUT))
while (( SECONDS < deadline )); do
  state="$(sudo docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null || true)"
  if [[ "$state" != "running" ]]; then
    sudo docker logs --tail 100 "$CONTAINER" >&2 || true
    die "Container stopped during initialization (state: ${state:-unknown})."
  fi

  http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    "http://${BIND_IP}:${WEB_PORT}/" 2>/dev/null || true)"

  if [[ "$http_code" == "200" ]] && sudo docker exec -u gvm "$CONTAINER" \
      gvm-cli --gmp-username admin --gmp-password "$OPENVAS_PASSWORD" \
      socket --socketpath /run/gvmd/gvmd.sock --xml '<get_version/>' \
      2>/dev/null | grep -q 'status="200"'; then
    health="$(sudo docker inspect "$CONTAINER" --format '{{.State.Health.Status}}')"
    version="$(sudo docker logs "$CONTAINER" 2>&1 |
      sed -n 's/^starting container ver \([^ ]*\).*/\1/p' | tail -n 1)"
    unset OPENVAS_PASSWORD
    printf '\nOpenVAS installation succeeded.\n'
    printf 'URL:      http://%s:%s\n' "$BIND_IP" "$WEB_PORT"
    printf 'Username: admin\n'
    printf 'Version:  %s\n' "${version:-latest}"
    printf 'Health:   %s\n' "$health"
    printf 'Feeds:    bundled image feeds (startup sync skipped)\n'
    exit 0
  fi

  sleep 10
done

sudo docker logs --tail 150 "$CONTAINER" >&2 || true
die "OpenVAS did not become ready within ${STARTUP_TIMEOUT} seconds."
