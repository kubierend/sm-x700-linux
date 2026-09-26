#!/bin/sh
# pmOS hooks-cleanup: runs after /sysroot is mounted, before switch_root.
# All added services live on /run's tmpfs and disappear on the next reboot.
set -e
mkdir -p /run/gts8-usb-debug
exec >>/run/gts8-usb-debug/initramfs.log 2>&1
echo "gts8 USB debug: configuring NCM + authenticated serial login"
. /init_functions.sh
. /usr/share/misc/source_deviceinfo
[ ! -e /etc/unudhcpd.conf ] || . /etc/unudhcpd.conf

# Stage 1 may have checked USB before the controller finished probing.
attempt=0
while [ -z "$(get_usb_udc)" ] && [ "$attempt" -lt 15 ]; do
	attempt=$((attempt + 1))
	sleep 1
done
if [ -z "$(get_usb_udc)" ]; then
	echo "No USB device controller after 15s; continuing normal boot."
	dmesg > /run/gts8-usb-debug/dmesg-no-udc.txt
	exit 0
fi

if [ ! -d "$CONFIGFS/g1/configs/c.1" ]; then
	setup_usb_network_configfs
fi

if [ ! -d "$CONFIGFS/g1/functions/acm.usb0" ]; then
	setup_usb_acm_configfs
fi
if [ ! -L "$CONFIGFS/g1/configs/c.1/acm.usb0" ]; then
	printf '\n' > "$CONFIGFS/g1/UDC"
	ln -s "$CONFIGFS/g1/functions/acm.usb0" "$CONFIGFS/g1/configs/c.1/acm.usb0"
fi
setup_usb_configfs_udc
echo "Bound NCM + ACM to $(get_usb_udc)"

# The util-linux switch_root from pmOS initramfs-extra moves /run, including
# these runtime units, into the real rootfs. No /etc or /usr files are changed.
mkdir -p /sysroot/run /run/systemd/system/multi-user.target.wants
cp /gts8-usb-debug/network.sh /run/gts8-usb-debug/network.sh
cp /gts8-usb-debug/gts8-usb-debug.service /run/systemd/system/
for unit in gts8-usb-debug.service sshd.service serial-getty@ttyGS0.service unudhcpd@usb0.service; do
	if [ "$unit" = gts8-usb-debug.service ]; then
		target=/run/systemd/system/$unit
	elif [ "$unit" = serial-getty@ttyGS0.service ]; then
		target=/usr/lib/systemd/system/serial-getty@.service
	elif [ "$unit" = unudhcpd@usb0.service ]; then
		target=/usr/lib/systemd/system/unudhcpd@.service
	else
		target=/usr/lib/systemd/system/$unit
	fi
	ln -sf "$target" "/run/systemd/system/multi-user.target.wants/$unit"
done
for unit in sshd.service serial-getty@ttyGS0.service unudhcpd@usb0.service; do
	mkdir -p "/run/systemd/system/$unit.d"
	cp "/gts8-usb-debug/$unit.conf" "/run/systemd/system/$unit.d/85-gts8-usb-debug.conf"
done
dmesg > /run/gts8-usb-debug/dmesg-initramfs.txt
echo "SSH: user@172.16.42.1; USB serial: ttyACM on PC, press Enter, existing pmOS login."
