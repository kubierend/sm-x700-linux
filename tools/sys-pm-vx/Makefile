# Out-of-tree debug module: which RPMh voters keep the SoC out of CX collapse in suspend.
#   make KDIR=<kernel build dir> ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
#   (on the tablet) insmod sys_pm_vx_probe.ko; suspend; cat /sys/kernel/debug/sys_pm_vx/violators
obj-m += sys_pm_vx_probe.o
KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
