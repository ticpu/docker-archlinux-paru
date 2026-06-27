ARG TARGETARCH
ARG REGISTRY=docker.io/library

# Use official Arch Linux for amd64
FROM --platform=linux/amd64 ${REGISTRY}/archlinux:base-devel AS base-amd64

# Build Arch Linux ARM from official rootfs for arm64
FROM docker.io/library/alpine:latest AS arm64-downloader
ADD http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz /tmp/archlinuxarm.tar.gz
RUN mkdir -p /archlinuxarm && \
    tar -xzf /tmp/archlinuxarm.tar.gz -C /archlinuxarm

FROM scratch AS base-arm64
COPY --from=arm64-downloader /archlinuxarm/ /
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && \
    pacman-key --init && \
    pacman-key --populate archlinuxarm && \
    pacman -Rdd --noconfirm linux-aarch64 linux-firmware mkinitcpio mkinitcpio-busybox 2>/dev/null || true && \
    pacman -Syu --noconfirm && \
    sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && \
    pacman -S --noconfirm base-devel sudo && \
    pacman -Rns --noconfirm openssh dhcpcd netctl openresolv iproute2 iputils net-tools systemd-sysvcompat 2>/dev/null || true && \
    pacman -Sc --noconfirm && \
    gpgconf --kill all && \
    rm -rf /etc/pacman.d/gnupg/S.*

FROM base-${TARGETARCH} AS base
ARG TARGETARCH
RUN useradd -m paru && \
	echo "paru ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/paru && \
	pacman -Sy && \
	pacman -S git cargo --noconfirm && \
	pacman -Sc --noconfirm && \
	git config --system init.defaultBranch master
USER paru:paru
WORKDIR /home/paru
RUN git clone https://aur.archlinux.org/paru.git && \
	cd paru && \
	makepkg --noconfirm && \
	makepkg --packagelist | grep -v -- '-debug-' > /home/paru/paru-pkglist

USER root
RUN pacman -U --noconfirm $(cat /home/paru/paru-pkglist) && \
	pacman -Sc --noconfirm && \
	rm -r /home/paru/.cargo /home/paru/paru /home/paru/paru-pkglist
