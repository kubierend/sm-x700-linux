#!/bin/sh
set -eu
# NetworkManager's shipped 85-nm-unmanaged.rules excludes gadget interfaces.
# Use the actual name exported by configfs; this image's NCM instance is usb0.
gadget=/sys/kernel/config/usb_gadget/g1
iface=$(cat "$gadget/functions/ncm.usb0/ifname")
if [ "$iface" != usb0 ]; then
	echo "Unexpected gadget interface $iface (expected usb0); DHCP unit needs adjustment" >&2
	exit 1
fi
ip address replace 172.16.42.1/24 dev "$iface"
ip link set dev "$iface" up
echo "USB debug network: $iface at 172.16.42.1/24"
echo "UDC: $(cat "$gadget/UDC")"
cat /sys/class/udc/*/state
