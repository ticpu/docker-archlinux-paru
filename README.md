# Arch Linux with paru

An Arch Linux container image with [paru](https://github.com/Morganamilo/paru), the AUR helper, pre-installed, for building and installing AUR packages in CI or a throwaway container.

- Rust toolchain included: rust, cargo, git and base-devel are installed, so the growing number of AUR packages written in Rust build without downloading a toolchain first.
- Platforms: linux/amd64 (official archlinux:base-devel) and linux/arm64 (Arch Linux ARM).
- Rebuilt every Tuesday from the current Arch base, and on every push to master.
- Published as `ticpu/paru` and `ticpu/archlinux-paru` on Docker Hub, and `ghcr.io/ticpu/docker-archlinux-paru`. All three carry the same image.

## Tags

- `latest`: the most recent build.
- `YYYYMMDD-HHMMSS`: each build, stamped with its UTC build time, for pinning a known-good image.

Builds older than six months are deleted. Pin a recent build and move forward, rather than pinning one forever.

## Usage

The image runs as root. makepkg refuses root, so run paru as the `paru` user, which has passwordless sudo:

```sh
docker run --rm -it ticpu/paru sudo -u paru paru -S --noconfirm <aur-package>
```

In a Containerfile, clean up in the same `RUN`, or the files stay in the layer. paru keeps its clones and build trees under `~/.cache/paru`, and `pacman -Scc --noconfirm` empties nothing, since `--noconfirm` answers its prompt with the default, No:

```Dockerfile
FROM docker.io/ticpu/paru:latest
RUN sudo -u paru paru -S --noconfirm <aur-package> && \
    rm -rf /home/paru/.cache/paru /var/cache/pacman/pkg/*
```

## Source

https://github.com/ticpu/docker-archlinux-paru, MIT licensed.
