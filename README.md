# Proxmox VE bootc

<p align="center">
  <img src="https://raw.githubusercontent.com/DaemonCores/.github/refs/heads/main/assets/banner.svg" alt="DaemonCores Banner" width="100%"/>
</p>

<p>
  <strong align="left">Simplify and Innovate for Everyone.</strong>
  <a href="https://github.com/DaemonCores/proxmox-ve-bootc/wiki"><img align="right" src="https://img.shields.io/badge/Wiki-FFFFFF?style=for-the-badge&logoColor=white" alt="Documentation"/></a>
  <a href="https://github.com/orgs/DaemonCores/discussions"><img align="right" src="https://img.shields.io/badge/Community-000000?style=for-the-badge&logoColor=white" alt="Community"/></a>
  <a href="https://github.com/DaemonCores/debian-bootc"><img align="right" src="https://img.shields.io/badge/Base_debian_for_all_project-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian Bootc"/></a>

  <em>Identify gaps and fill them, make improvements where possible, but above all, empower developers to offer more to users.</em>
</p>

---

`proxmox-ve-bootc` builds **vanilla Proxmox VE** as a transactional bootc/OSTree operating-system image on top of [`debian-bootc`](https://github.com/DaemonCores/debian-bootc). The repository ships the standard Proxmox packaging as a versioned OCI image: the PVE packages, the Proxmox kernel, and the fixes any standard Proxmox installation needs to boot and live on an immutable/OSTree root (systemd start timeouts on slow hardware, log mounts, kernel-helper compatibility, the no-subscription apt source, chronyd on a composefs root).

The repository is deliberately **fork-free**: every DaemonCores-specific addition — the ddns bridge layout, the first-boot network autoconf, the host tooling `fanctl`/`powerctl`/`compose2bootc`/`pvect-ostree` and the `dc-*` package set — lives in the **[DaemonCores-VE](https://github.com/DaemonCores/DaemonCores-VE)** fork, which builds its images FROM this repository's published image (`ghcr.io/daemoncores/proxmox-ve-bootc`). The packages this image repacks carry the `+bootc1` suffix; `ifupdown2` ships unmodified upstream; the THP boot default of this image is `never` (ruling R-804: one compiled kernel, the image karg decides, the fork derives thin `-thpalways` twins).

The repository is under active development. The current deployment target is amd64 hardware. Review the release workflow and test results before installing it on a host that carries important workloads.

## Why a vanilla repository

The separation audit (owner plan, 03/11) splits what a standard Proxmox installation needs from what the DaemonCores fork adds. Every fix that must land in a standard Proxmox installation — the kind of change one would file upstream — belongs here; the fork-only runtime belongs to DaemonCores-VE. Proxmox users get a clean bootable image, and the fork stays reviewable as pure additions.

## Implemented components

The base image supplies Debian 13, bootc, OSTree, composefs, bootupd, the bootloader path, first-boot setup, and the generic installer infrastructure. This repository adds:

- Proxmox VE and the Proxmox kernel, with the shared kernel-pve flavours lane (x64v1-v4 + the arm64 flavours) built from this repository's manifest;
- the standard guest defaults for OVMF, Q35, guest agent, NIC firewall and disk caching;
- the OSTree-compatible package set below (fix repacks, `+bootc1`);
- the resolver chain of an immutable host: `openresolv` + `dnsmasq`, the single-source-of-truth interfaces file written at install time;
- the THP `never` karg of the standard VM workload line (R-804);
- exhaustive boot tests: QEMU/KVM bootc install over SSH, every test failing with a diagnosis, never silently.

## Project packages

| Package | Responsibility |
| --- | --- |
| `pve-manager` | Applies the standard web-interface defaults and subscription-status patch. |
| `qemu-server` | Applies backend VM defaults and EFI provisioning behaviour. |
| `libpve-storage-perl` | Mounts API/GUI-created ZFS pools under `/mnt/<pool>` and keeps the zfspool path fallback off the read-only OSTree root. |
| `libtemplate-perl` | Handles OSTree's zero file mtimes correctly so Proxmox templates remain discoverable. |
| `chrony` and `openipmi` | Add service guards and network ordering suitable for the image. |
| `proxmox-kernel-helper` | Removes boot operations that conflict with the bootc-managed boot path. |

Exact defaults and operational constraints live with each package under `workflows/bootc-debs-builder/`.

## Build and validation

The repository calls the shared [`DaemonCores-CI`](https://github.com/DaemonCores/DaemonCores-CI) pipeline. A complete run:

1. optionally rebuilds the `debian-bootc` base;
2. builds and publishes the project Debian packages;
3. assembles the Proxmox image from `Containerfile`;
4. installs the image to a virtual disk and boots it with QEMU/KVM;
5. verifies the Proxmox cluster filesystem, services, web UI, package patches, resolver chain and THP state;
6. publishes and signs the image after those tests pass;
7. produces online and offline installer ISOs.

The monthly schedule performs a complete rebuild. Push builds use change detection, while manual runs can select individual stages and optionally trigger the upstream base pipeline first.

## Installation

Installer artifacts are published in the [`install-iso`](https://github.com/DaemonCores/proxmox-ve-bootc/releases/tag/install-iso) release when the ISO stage succeeds.

- The online ISO pulls `ghcr.io/daemoncores/proxmox-ve-bootc:latest` during installation.
- The offline ISO embeds an OCI archive.
- The installer asks for the target disk and preserves an existing compatible `var` Btrfs subvolume during reinstall.
- First boot runs the inherited console setup flow before normal host operation.

The selected installation disk is repartitioned. Test the image and installation path in a virtual machine before using physical hardware.

## Host configuration

The network interfaces file is written at install time by the bootc-installer network stage; the resolver chain (openresolv → dnsmasq) reads it as its single source of truth. The first-boot wizard renames the host following the standard PVE flow; the matching `/etc/hosts` template entry ships with the image.

## Required repository configuration

| Secret | Purpose |
| --- | --- |
| `PAT_PKG` | Pull and publish GHCR images. |
| `APT_GPG_KEY` | Sign this repository's APT repository. |
| `SB_SIGNING_KEY` | Used by the inherited boot stack when the Secure Boot package is rebuilt. |
| `SB_SIGNING_CERT` | Certificate paired with the Secure Boot key. |

Container images are signed keylessly with cosign through GitHub Actions OIDC. No `COSIGN_PRIVATE_KEY` or `COSIGN_PASSWORD` secret is used by the current image workflow.

## Documentation

- [Architecture](docs/Handoff-Architecture.md)
- [Design decisions and trade-offs](docs/Handoff-Decisions.md)
- [The PVE/NVIDIA host kernel plan](docs/kernel-nvidia-pve-host-plan.md)
- [Support](SUPPORT.md)
- [Security policy](SECURITY.md)

---

<p>
  <strong align="left">Made with ⭐ by the DaemonCores community</strong>
  <a href="https://github.com/DaemonCores/proxmox-ve-bootc/wiki"><img align="right" src="https://img.shields.io/badge/Wiki-FFFFFF?style=for-the-badge&logoColor=white" alt="Documentation"/></a>
  <a href="https://github.com/orgs/DaemonCores/discussions"><img align="right" src="https://img.shields.io/badge/Community-000000?style=for-the-badge&logoColor=white" alt="Community"/></a>
  <a href="https://github.com/DaemonCores/debian-bootc"><img align="right" src="https://img.shields.io/badge/Base_debian_for_all_project-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian Bootc"/></a>
</p>