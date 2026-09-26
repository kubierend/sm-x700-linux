# Licensing

This repository carries two licenses, following the projects each part feeds into (the same
split the sibling sm-x800-linux port uses).

| Path | License | Why |
|---|---|---|
| `kernel/patches/`, `kernel/config/`, the device tree and drivers inside them | **GPL-2.0-only** (`LICENSES/GPL-2.0.txt`) | Linux kernel sources; some drivers derive from Samsung's GPL downstream kernel |
| `boot/uniloader/` | **GPL-2.0-only** | uniLoader is GPL-2.0 |
| `tools/sys-pm-vx/` | **GPL-2.0-only** | out-of-tree kernel module, after Qualcomm's GPL downstream driver |
| `device/pmaports/hexagonrpcd/*.patch` | **GPL-3.0-or-later** | patches to hexagonrpc, which is GPL-3.0-or-later; taken from the sm-x800-linux port |
| `boot/*.sh`, `boot/audit-boot-layout.py`, `tools/`, `device/` scripts and packaging, `docs/` | **MIT** (`LICENSES/MIT.txt`) | tooling and postmarketOS packaging, conventionally MIT |
| `boot/tools/mk-tplg.py` | **MIT** | copied unchanged from sm-x800-linux |

Each kernel patch and source file also carries its own SPDX header where the code has one.

**No proprietary files are stored here.** Samsung/Qualcomm firmware (GPU zap shader, ADSP and
SLPI images), Wi-Fi firmware and board data, the sensor configuration and registry, and Samsung's stock
boot ramdisk are read from your own
device or firmware download by the scripts in `boot/` and `tools/`.
