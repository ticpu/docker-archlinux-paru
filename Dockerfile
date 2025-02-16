FROM docker.io/library/archlinux:base-devel
RUN useradd -m paru && \
	echo "paru ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/paru && \
	pacman -Sy && \
	pacman -S git --noconfirm && \
	pacman -Sc --noconfirm && \
	git config --system init.defaultBranch master
USER paru:paru
WORKDIR /home/paru
RUN git clone https://aur.archlinux.org/paru.git && \
	(cd paru && makepkg -s -i -r --noconfirm) && \
	sudo pacman -Sc --noconfirm && \
	rm -r ~/.cargo && \
	sudo rm -r paru /usr/lib/debug
