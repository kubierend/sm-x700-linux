# Optional initramfs extras

`usb-debug-tree/`: brings up a USB network gadget (NCM), sshd and a serial getty *inside the
initramfs*, so the tablet is reachable at 172.16.42.1 over USB-C even when the rootfs or Wi-Fi
is broken. Development aid only; leave it out of a release image.

    ../assemble-initramfs.sh --base pmos-initramfs --out initramfs.cpio.gz \
        ../work/fw/gpu ../work/fw/audio ../work/fw/sensors usb-debug-tree
