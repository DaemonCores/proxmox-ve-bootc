# mok.d — Secure Boot keys enrolled in the machine's MOK (bootc install +
# the image-test harness varstore both enroll every public certificate here).
#
# proxmox-secureboot-sign-2023.pem: the Proxmox VE kernels ship their vmlinuz
# Authenticode-signed with Proxmox's own "Secure Boot Sign 2023" key. GRUB
# validates its own signature against the image's sb_signing.crt (already in
# db/MokList); the KERNEL signature nobody else covers — without this cert
# in MokList, grub's shim_lock verifier rejects the PVE kernel with
# "bad shim signature" the moment Secure Boot is enforced (reproduced
# locally under OVMF secboot + smm=on: without the cert = shim_lock
# violation on the kernel, with the cert = the chain boots the kernel to
# initrd; run 42859446971's red "Verification failed: (0x1A) Security
# Violation" screen is the same failure surfaced by the firmware path).
