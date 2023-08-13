BUILDDIR = $(realpath ./build)
MOUNTDIR = $(BUILDDIR)/mnt

CONTAINER_OPTS = -v $(realpath .):/deboot -ti --rm --cap-add=SYS_PTRACE
CONTAINER_IMAGE = ghcr.io/debootdevs/fedora
CONTAINER_RELEASE = "sha256:8e9a3947a835eab7047364ec74084fc63f9d016333b4cd9fcd8a8a8ae3afd0fd"
BEE_VERSION ?= 1.17.2

KVERSION = $(shell find /lib/modules -mindepth 1 -maxdepth 1 -printf "%f" -quit)

container:
	podman image exists $(CONTAINER_IMAGE) || podman pull $(CONTAINER_IMAGE)@$(CONTAINER_RELEASE)

dracut/dracut-util: /usr/bin/gcc
	sh -c "cd dracut && ./configure"
	make enable_documentation=no -C dracut

grub: container initramfs/swarm-initrd
	podman run -v $(realpath .)/build/mnt:/deboot/build/mnt \
		$(CONTAINER_OPTS) $(CONTAINER_IMAGE) \
		make KVERSION=$(KVERSION) BUILDDIR=/deboot/build \
		     --directory /deboot/grub

initramfs/swarm-initrd: container dracut/dracut-util
	podman run $(CONTAINER_OPTS) $(CONTAINER_IMAGE) \
		make KVERSION=$(KVERSION) BEE_VERSION=$(BEE_VERSION) \
		     --directory /deboot/initramfs swarm-initrd

test-grub:
	podman run -v /dev:/dev $(CONTAINER_OPTS) $(CONTAINER_IMAGE) sh -c 'cd /deboot && grub/test-grub.sh'

