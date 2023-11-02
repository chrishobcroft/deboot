# DeBoot - express yourself through bootloading

DeBoot is a project to research and implement approaches to bootloading OS images from decentralized storage networks, such as [Swarm](https://ethswarm.org) or [IPFS](https://ipfs.tech/).

## Milestone report

DeBoot reached a milestone in its development: [read more about DeBoot's recent milestone](https://hackmd.io/@i79XZRmjR86P6AbhL0jwVQ/BJUaVuaUn).

## Get involved

If you want to get involved, join [the DeBoot chat on Matrix](https://matrix.to/#/#deboot:matrix.org) or [the DeBoot chat on Telegram](https://t.me/+hd2JXtyitYw0ZWE9).

## Repo contents

`/initramfs`. Tools and scripts for building initramfs.

`/loader`. Templates for instructions for kernel loaders. GRUB and U-Boot are supported.

`/resources`. General notes on booting devices.

`/rootfs`. Scripts and tools for generating squashfs images.

`/swarm.hash`. Swarm hashes of premade rootfs.

## Running DeBoot

You'll need a KVM-ready Linux OS. Your Linux OS is KVM-ready if a file exists at `/dev/kvm`.

1. Install podman, slirp4netns, uidmap

2. Clone this repo using `git --recurse-submodules -b aarch64`.

3. Change to the repository's home directory. Run
   ```
   make build-env
   make init-env
   ```
   to set up the build environment (container) and enter an isolated shell.

4. Change to the `deboot` directory, then run `make KERNEL_LOADER=u-boot BEE_VERSION=$LATEST_VERSION boot-tree HASH` where:
   * `$HASH` is the Swarm hash of a premade rootfs. If you haven't made one yourself, pick one of the filenames in the swarm.hash directory, e.g. `HASH=$(ls ./swarm.hash | grep ebf).
   * `$LATEST_VERSION` is set to the latest version of the bee node released on https://github.com/ethersphere/bee/release (`1.17.5` at time of writing). 
   
   This will create a boot directeory tree `build/boot/` containing our Swarm initramfs.
    
5. Exit the container.

6. Run `sudo make install` to install the bootfs into `boot.img`. This image can be flashed to an SD card.

*This last step is for testing boot from UEFI; ignore it if you are using U-Boot.*

7. To test the image you just built, run `make test-grub`. Select an item from the menu corresponding to the Swarm hash of the userspace you want to boot into.
   
   If something goes wrong and you get stuck in the QEMU console, press the sequence `<Ctrl>+a, x` to quit.


## What?

Network boot is a way to get an operating system (OS) running on your device without a bootable USB drive (or other removable media). With 10Gbps and even 100Gbps network adapters increasingly available, this can even be the fastest method to boot a device without an OS image on a storage device attached to a PCIe bus.

Typically, a network boot retrieves a bootable image from a server on the local network, which the user sets up themselves (and could be on the router itself).

## Why?

Decentralised storage solves some liveness problems (such as censorship) with centralised hosting. With an incentivized decentralized storage solution like Swarm, files should remain available as long as hosting is funded, regardless of who is funding it, where the hosting peers are, or where the client is.

Other benefits of our system compared to net boot include:

- Operator does not need to manage hosting of the OS images
- (in some models) operator does not need a second device to act as a PXE server.

## How?

The basic challenge is this: establish a connection with a Swarm node and request a blob of data in a minimalist preboot environment. In particular, we have **no OS** available at this point. We came up several different approaches, depending on:

- Which stage in the boot process the Bee client is started up;
- How minimal an environment we load (partly determined by what is available at the boot stage we're jumping into our binary);
- Local network topology: whether the Bee client runs on the boot device itself or on a separate relay server on the LAN.

Different networking facilities are available at different stages of the boot process. The following table shows a few. (If something in the table doesn't make sense, it's because we didn't have time to make it make sense yet.)

|                  | PXE                       | UEFI executable | GrUB module       |
| ---------------- | ------------------------- | --------------- | ----------------- |
| format on device | N/A (board firmware only) | PE              | ELF (relocatable) |
| libC (syscalls)  | 🗴                         | 🗴               | 🗴                 |
| TCP              | ✓                         | ✓               | ✓                 |
| HTTP             | 🗴                         | ✓               | ✓ (with http.mod) |
| WiFi             | 🗴                         | 🗴               | 🗴                 |
| DHCP             | ✓                         | ✓               | ✓                 |
| TFTP             | ✓                         | ✓               | ✓                 |
|                  |                           |                 |                   |
|                  |                           |                 |                   |

## Exocompile approach

To get around difficulties with the limited boot environment (and to avoid doing a weird port of the Swarm client), we tried making a **unified kernel image** which bundles together a minimal Linux kernel together with enough junk to fetch a chunk from the Swarm:

- Modules/programs required for networking. This is much easier if you have an Ethernet port; you just need to add a line `"ip=:::::<interface-name>:dhcp"` to the kernel commandline (argument to `-c` in `efi-muki`). We didn't manage to get it working over WiFi yet.
- Bee client: https://github.com/ethersphere/bee
- `curl` (to make an HTTP API request from the local node).

To do this, use the `initramfs-tools` package to make an initramfs containing these components (see `./initramfs-tools/`) and then pass it and the kernel as a parameter to the `efi-mkuki` tool. Here is an example build sequence for Ubuntu (see `./initramfs-tools/`):

```sh
update-initramfs -c -k <kernel-version> 
	# creates in /boot/initrd.img-<kernel-version>
sudo efi-mkuki -c BOOT_IMAGE=/boot/vmlinuz\ 
	root=/dev/mapper/vgubuntu-root ro quiet splash vt.handoff=7 \
	break=modules  -o deboot.efi -s logo1024768.bmp \
	-S linuxx64.efi.stub /boot/vmlinuz /boot/initrd.img-<kernel-version>
# the file linuxx64.efi.stub comes from /usr/lib/systemd/boot/efi/ 
# on our machine
```

This outputs a UEFI executable `deboot.efi`, which you need to copy into your system EFI partition. Your mainboard firmware should then be able to find it, so it appears in the boot menu in the BIOS settings.

Once booted into the initramfs, you need to execute the following:

```sh
bee start --swap-enable=false --password=beanus
curl localhost:1633/bzz/<id> -LO
mount <efi-partition> esp
cp <id> esp/EFI/BOOT/nextboot.efi
exit
```

