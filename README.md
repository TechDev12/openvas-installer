# OpenVAS One-Command Installer

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)](install-openvas.sh)
[![Docker](https://img.shields.io/badge/runtime-Docker-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![OpenVAS](https://img.shields.io/badge/scanner-OpenVAS-1A7F37)](https://www.openvas.org/)
[![Upstream image](https://img.shields.io/badge/image-immauss%2Fopenvas-blue)](https://github.com/immauss/openvas)

A fresh-install Bash script for deploying the full
[`immauss/openvas`](https://github.com/immauss/openvas) Docker image with a
secure password prompt, persistent storage, automatic restart, readiness
checks, and authenticated post-install verification.

> [!IMPORTANT]
> This project is an independent installer and is not affiliated with or
> endorsed by the upstream `immauss/openvas` project. Credit for the OpenVAS
> container image and its maintenance belongs to
> [Scott "Immauss"](https://github.com/immauss) and its contributors.

## What it does

- Prompts for the OpenVAS administrator password without echoing it.
- Pulls the current `immauss/openvas:latest` full image.
- Creates a persistent Docker volume named `openvas`.
- Detects the host's primary LAN address automatically.
- Publishes the web interface on port `8080`.
- Publishes GMP/OSP-compatible ports `9390` and `9391`.
- Enables `--restart unless-stopped`.
- Applies Redis' recommended `vm.overcommit_memory=1` host setting.
- Uses bundled image feeds at startup to avoid an external feed outage
  preventing the service from starting.
- Waits for the UI and verifies the supplied administrator credentials through
  an authenticated GMP request.

## Requirements

- A Linux host with Bash
- Docker Engine
- `curl`
- `sudo` access
- Around 15 GB of free disk space is recommended for the image, database,
  feeds, and working data

The script is intended for a **fresh installation**. It exits without changing
anything if an `openvas` container or volume already exists.

## Quick start

```bash
curl -fsSLO https://raw.githubusercontent.com/TechDev12/openvas-installer/master/install-openvas.sh
chmod +x install-openvas.sh
./install-openvas.sh
```

Enter and confirm the OpenVAS administrator password when prompted. The
password is not printed and is not added to your shell history.

When installation finishes, open:

```text
http://HOST_IP:8080
```

Sign in with:

```text
Username: admin
Password: the password entered during installation
```

> [!NOTE]
> Docker stores container environment variables in container metadata. Anyone
> with root or Docker-daemon access on the host can inspect them. Treat Docker
> access as privileged access.

## Configuration

Set environment variables before running the script to override its defaults:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENVAS_BIND_IP` | First address from `hostname -I` | Address used for the web interface |
| `OPENVAS_WEB_PORT` | `8080` | Host port mapped to GSAD port `9392` |
| `OPENVAS_IMAGE` | `immauss/openvas:latest` | Container image or pinned image tag |
| `OPENVAS_CONTAINER` | `openvas` | Docker container name |
| `OPENVAS_VOLUME` | `openvas` | Persistent Docker volume name |
| `OPENVAS_STARTUP_TIMEOUT` | `1800` | Maximum readiness wait in seconds |

Example:

```bash
OPENVAS_BIND_IP=192.168.21.241 \
OPENVAS_WEB_PORT=8080 \
./install-openvas.sh
```

To pin an upstream version:

```bash
OPENVAS_IMAGE=immauss/openvas:26.07.27.01 ./install-openvas.sh
```

## Verify the installation

```bash
sudo docker ps --filter name='^/openvas$'
sudo docker inspect openvas --format '{{.State.Health.Status}}'
curl -I http://HOST_IP:8080/
sudo docker logs --tail 100 openvas
```

The container should report `healthy`, and the web request should return HTTP
status `200`.

## Update community feeds

Startup feed synchronization is disabled so an unavailable or rate-limited
rsync endpoint cannot block the scanner from starting. The full upstream image
already includes bundled feeds. Update them later with:

```bash
sudo docker exec openvas /scripts/sync.sh
```

If Greenbone's community rsync service resets the connection, wait and run the
same command again. Existing feeds remain available.

## Useful operations

```bash
# Follow logs
sudo docker logs -f openvas

# Restart OpenVAS
sudo docker restart openvas

# Stop and start it manually
sudo docker stop openvas
sudo docker start openvas

# Inspect persistent storage
sudo docker volume inspect openvas
```

## Troubleshooting

### Port 8080 is already in use

Choose a different host port:

```bash
OPENVAS_WEB_PORT=8088 ./install-openvas.sh
```

### Wrong IP address detected

Specify the LAN address explicitly:

```bash
OPENVAS_BIND_IP=192.168.1.50 ./install-openvas.sh
```

### Initialization takes a long time

The full image is large, and the first PostgreSQL restore and VT-cache load can
take several minutes. Follow progress with:

```bash
sudo docker logs -f openvas
```

### Installation timed out

Increase the readiness timeout:

```bash
OPENVAS_STARTUP_TIMEOUT=3600 ./install-openvas.sh
```

## Security notes

- The default GSAD endpoint created by the upstream image uses HTTP. Restrict
  access to a trusted network or place it behind a TLS-enabled reverse proxy.
- Do not expose ports `9390` and `9391` to untrusted networks.
- Use a long, unique administrator password.
- Back up the `openvas` Docker volume before major upgrades.
- Review the upstream image documentation and release notes before deploying in
  production.

## Upstream project

This repository automates deployment; it does not build or maintain OpenVAS.
For the container image, release notes, advanced options, and upstream support,
visit:

- [`immauss/openvas` on GitHub](https://github.com/immauss/openvas)
- [`immauss/openvas` on Docker Hub](https://hub.docker.com/r/immauss/openvas)
- [Greenbone Community Documentation](https://greenbone.github.io/docs/)

Please direct image-specific issues and feature requests to the appropriate
upstream project after confirming they are not caused by this installer.

## License

The installer script and documentation in this repository are released under
the [MIT License](LICENSE). The OpenVAS software and upstream container image
retain their own licenses.
