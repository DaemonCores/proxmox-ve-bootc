#####################################################################################
# Base image
#####################################################################################
# The shared CI (bootc-build.yml) builds Containerfile.base once per job as
# localhost/proxmox-ve-bootc-base and passes it as BASE_IMAGE; the base's FROM
# line feeds the image content hash (the base digest is part of the hash).
ARG BASE_IMAGE=localhost/proxmox-ve-bootc-base
FROM ${BASE_IMAGE}
STOPSIGNAL SIGRTMIN+3

# Environement Setup
LABEL org.opencontainers.image.title="Proxmox VE bootc"
LABEL org.opencontainers.image.description="Vanilla Proxmox VE on Debian 13 Trixie, bootc/ostree — standard packaging and fixes only."
LABEL org.opencontainers.image.base.name="ghcr.io/daemoncores/debian-bootc:latest"
LABEL org.opencontainers.image.source="https://github.com/DaemonCores/proxmox-ve-bootc"
LABEL org.opencontainers.image.licenses="LGPL-2.1"
LABEL containers.bootc=1
LABEL ostree.bootable=1
# GPU model: the NVIDIA driver lane belongs to debian-bootc (owner order
# 2026-11-03); VE consumes it through apt. No GPU image descriptor here —
# the -nvidia twin label and its GPU_EXTRA_PKGS RUN were removed with it.

# APT repository trust — same mechanics as debian-bootc: the full pipeline
# hashes the APT_GPG_KEY secret at every run (full-pipeline.yml apt_key job)
# and bootc-build.yml passes both build-args (BOOTC_GPG_SHA256 / BOOTC_APT_URL
# env, consumed by build-arch.sh apt_build_args). Nothing to hand-edit after a
# key rotation; the committed defaults only serve plain local podman builds.
# The sources stanza below carries the same URL (src/pvepreinstall). The
# value below is this repository's APT repo URL; its GPG digest is passed by
# the CI (the committed value here is the DaemonCores-VE key inherited at the
# cut-over date — replaced by the vanilla repo key at its first rotation).
ARG BOOTC_APT_URL=https://daemoncores.github.io/proxmox-ve-bootc/
ARG BOOTC_GPG_SHA256=07a57112edcbe89680a46a52b44fa5b9d3217420d365eb3a9b37367f8173b787
# The Proxmox archive key is an upstream artifact (not our secret-derived repo
# key): its pin stays committed, refreshed with the release that fetches it.
ARG PVE_GPG_SHA256=136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45
# Product display name, injected by the CI from the repo name (dashes -> spaces).
# Overrides the base's value so bootc-finalize (re-run by the pve-kernel install)
# brands the UEFI boot-entry label with this product; empty keeps the base value.
ARG PRODUCT_NAME=""
# Setup all environement variables
ENV DEBIAN_FRONTEND=noninteractive
# Default shell: fail build on error. Honored with `--format docker` in CI.
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Proxmox setup — the vanilla image trusts ONE fork-free APT repo: its own
# (fix repacks, this repository's gh-pages) plus the upstream Proxmox
# no-subscription index. No DaemonCores-VE source, no fork keyring.
COPY ./src/pvepreinstall /
RUN chmod +x /usr/sbin/policy-rc.d \
    && url="${BOOTC_APT_URL%/}" \
    && wget \
        -O /usr/share/keyrings/proxmox-ve-bootc-keyring.gpg \
        "${url}/gpg.key" \
    && printf '%s  /usr/share/keyrings/proxmox-ve-bootc-keyring.gpg\n' "${BOOTC_GPG_SHA256}" \
        | sha256sum -c - \
    && wget \
        https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
        -O /usr/share/keyrings/proxmox-archive-keyring.gpg \
    && printf '%s  /usr/share/keyrings/proxmox-archive-keyring.gpg\n' "${PVE_GPG_SHA256}" \
        | sha256sum -c - \
    && echo "postfix postfix/main_mailer_type string Local only" | debconf-set-selections \
    && echo "postfix postfix/mailname string proxmox.local" | debconf-set-selections \
    && echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections \
    && mkdir -p /usr/lib/bootc \
    && { [ -z "${PRODUCT_NAME}" ] \
        || printf '%s' "${PRODUCT_NAME}" > /usr/lib/bootc/product-name; } \
    && apt update \
    && apt full-upgrade -y \
    && apt update \
    && apt install -y \
        proxmox-default-kernel \
        proxmox-ve \
        postfix \
        open-iscsi \
        chrony \
        ksmtuned \
        dnsmasq \
        proxmox-firewall \
        openipmi \
        ifupdown2 \
    && { apt remove -y \
        linux-image-amd64 \
        os-prober \
        $(dpkg -l 'linux-image-[0-9]*' | awk '/^ii/{print $2}' | grep -v proxmox) \
        2>/dev/null || true ; } \
    # Remove standard Debian AND daemoncores kernels (the base image ships the
    # profiled daemoncores-kernel-* lane) to keep only proxmox-default-kernel,
    # then prune stale module trees so only the active Proxmox kernel's modules
    # remain on disk. KVER resolves from the installed proxmox-kernel package,
    # never by lexical ls order: "7.2.15-x64v3-xanmod1" sorts AFTER
    # "7.2.15-1-pve" and pruned the freshly-installed proxmox tree.
    && dpkg --purge 2>/dev/null \
        $(dpkg -l 'daemoncores-kernel-*' | awk '/^ii/{print $2}') \
        || true \
    && KVER=$(for k in $(dpkg -l 'proxmox-kernel-*' | awk '/^ii/{print $2}' \
        | grep -v -- '-dbgsym$' \
        | sed -n -e 's/^proxmox-kernel-\([0-9][^ ]*\)-signed$/\1/p' -e 's/^proxmox-kernel-\([0-9][^ ]*\)$/\1/p' \
        | sort -ru); do \
        [ -d "/usr/lib/modules/$k" ] && echo "$k" && break; done) \
    && case "${KVER}" in \
        [0-9]*-pve) : ;; \
        *) echo "FATAL prune: no proxmox-kernel module tree resolved (packages: $(dpkg -l 'proxmox-kernel-*' | awk '/^ii/{print $2}' | tr '\n' ' '), trees: $(ls -A /usr/lib/modules | tr '\n' ' '))" >&2; exit 1 ;; \
       esac \
    && find /usr/lib/modules -mindepth 1 -maxdepth 1 ! -name "${KVER}" -exec rm -rf {} +

# Post install patch
# COPY ships the Debian-standard PVE host config: /etc/hostname, a matching
# bootstrap /etc/hosts entry (+ their .tpl variants), the motd rebrand and the
# Proxmox drop-in configs (shipped in src/pvepreinstall, before the deb
# install, at the PVE/Debian-standard position — the audit verdict is
# MUST-SHIP vanilla). The ddns bridge layout and the first-boot autoconf
# (ifupdown2-autoconf, domain-set) live in the DaemonCores-VE fork image; on
# the vanilla image the network interfaces file is written at install time by
# the bootc-installer network stage.
COPY ./src/pvepostinstall /
# NOTE: no target.wants symlinks are needed for the first-boot host naming:
# the first-boot wizard renames the host, and /etc/hosts refinement to the
# real address follows the standard PVE flow.
RUN mkdir -p /etc/systemd/system/multi-user.target.wants \
    # Guard: abort if pve-manager is missing (proxmox-ve install failed earlier).
    && dpkg -s pve-manager >/dev/null 2>&1 \
        || { echo "ERROR: pve-manager not installed; proxmox-ve install failed." >&2; exit 1; } \
    && rm -f /etc/apt/sources.list.d/pve-install-repo.sources \
        /tmp/* \
        /var/tmp/* \
        /usr/sbin/policy-rc.d \
    # Enable KSM adaptive tuning (dedup guest memory under pressure) via symlink
    && ln -sf /usr/lib/systemd/system/ksmtuned.service \
        /etc/systemd/system/multi-user.target.wants/ksmtuned.service \
    # Enable chrony via symlink (bootc-compatible, avoids systemctl enable)
    && ln -sf /lib/systemd/system/chrony.service \
        /etc/systemd/system/multi-user.target.wants/chrony.service \
    # Create chronyd alias for Anaconda (Fedora naming convention)
    && ln -sf /lib/systemd/system/chrony.service /etc/systemd/system/chronyd.service

# bootc images are updated in-place via ostree; no runtime healthcheck applies.
HEALTHCHECK NONE
