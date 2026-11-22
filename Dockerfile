ARG TARGETARCH
ARG REGISTRY=docker.io/library

# Use official Arch Linux for amd64, which publishes no other architecture
# hadolint ignore=DL3029
FROM --platform=linux/amd64 ${REGISTRY}/archlinux:base-devel AS base-amd64

# Build Arch Linux ARM from official rootfs for arm64
# hadolint ignore=DL3007
FROM docker.io/library/alpine:latest AS arm64-downloader
ADD http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz /tmp/archlinuxarm.tar.gz
RUN mkdir -p /archlinuxarm && \
    tar -xzf /tmp/archlinuxarm.tar.gz -C /archlinuxarm

# Removals pick from what pacman -Qq reports installed, so a package missing
# from the rootfs is skipped; pipefail would turn that skip into a failure.
# linux-firmware is split into linux-firmware-*, hence the pattern.
FROM scratch AS base-arm64-prep
COPY --from=arm64-downloader /archlinuxarm/ /
# hadolint ignore=DL4006
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && \
    pacman-key --init && \
    pacman-key --populate archlinuxarm && \
    pacman -Qq | grep -E '^(linux-aarch64|linux-firmware.*|mkinitcpio.*)$' | xargs -r pacman -Rdd --noconfirm && \
    pacman -Syu --noconfirm && \
    sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && \
    pacman -S --noconfirm base-devel sudo && \
    pacman -Qq openssh dhcpcd netctl openresolv net-tools | xargs -r pacman -Rns --noconfirm && \
    rm -rf /var/cache/pacman/pkg/* && \
    gpgconf --kill all && \
    rm -rf /etc/pacman.d/gnupg/S.*

# One layer: on top of the rootfs COPY, the upgrade above stores every
# replaced and removed file a second time.
FROM scratch AS base-arm64
# hadolint ignore=DL3067
COPY --from=base-arm64-prep / /

# pacman -Sc keeps every installed package in the cache, and -Scc --noconfirm
# answers its default No, so the cache is emptied with rm in each stage.
# hadolint ignore=DL3006
FROM base-${TARGETARCH} AS base
ARG TARGETARCH
RUN useradd -m paru && \
	echo "paru ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/paru && \
	pacman -Syu --noconfirm git cargo && \
	rm -rf /var/cache/pacman/pkg/* && \
	git config --system init.defaultBranch master

# Built in its own stage so ~/.cargo and the build tree never reach a layer
# of the published image.
FROM base AS paru-build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3066
USER paru:paru
WORKDIR /home/paru
RUN git clone https://aur.archlinux.org/paru.git && \
	makepkg -D paru --noconfirm && \
	mkdir /home/paru/out && \
	makepkg -D paru --packagelist | grep -v -- '-debug-' | xargs cp -t /home/paru/out/

FROM base
WORKDIR /home/paru
RUN --mount=type=bind,from=paru-build,source=/home/paru/out,target=/tmp/paru \
	pacman -U --noconfirm /tmp/paru/* && \
	rm -rf /var/cache/pacman/pkg/*
