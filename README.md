# Arch Linux with paru

An Arch Linux container image with [paru](https://github.com/Morganamilo/paru), the AUR helper, pre-installed, for building and installing AUR packages in CI or a throwaway container.

- Platforms: linux/amd64 (official archlinux:base-devel) and linux/arm64 (Arch Linux ARM).
- Rebuilt every Tuesday from the current Arch base, and on every push to master.
- Published as `ticpu/paru:latest` and `ticpu/archlinux-paru:latest` on Docker Hub, and `ghcr.io/ticpu/docker-archlinux-paru:latest`. All three are the same image.

## Usage

The image runs as root. makepkg refuses root, so run paru as the `paru` user, which has passwordless sudo:

```sh
docker run --rm -it ticpu/paru sudo -u paru paru -S --noconfirm <aur-package>
```

In a Containerfile:

```Dockerfile
FROM docker.io/ticpu/paru:latest
RUN sudo -u paru paru -S --noconfirm <aur-package> && pacman -Scc --noconfirm
```

## Source

https://github.com/ticpu/docker-archlinux-paru, MIT licensed.
