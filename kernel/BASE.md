# Kernel base

Two bases are maintained. `BASE=6.13` is the default everywhere until 7.2 has been booted
on the tablet.

## 6.13 (verified on hardware)

- Upstream: https://github.com/sm8450-mainline/linux (branch `next-new`), 6.13-rc3-based
  (a linux-next snapshot from December 2024; `next-new` has not moved since)
- Pinned commit: `bf1d29fced6e156dd6090a9b6600a8c44259c114`
- Tarball: https://github.com/sm8450-mainline/linux/archive/bf1d29fced6e156dd6090a9b6600a8c44259c114.tar.gz
- Config: upstream `defconfig` + `sm8450.config` (in that tree), then `config/x700.config`
  (and optionally `config/x700-debug.config`).
- Patches: `patches/`

## 7.2 (builds; not yet booted)

- Upstream: stable `linux-7.2.9` (https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz)
- Config: `defconfig`, then `config/sm8450.config` (the fork's fragment, carried here because
  mainline has none), then `config/x700.config`.
- Patches: `patches-7.2/` (12). Nothing board-relevant exists only in the fork: plain
  mainline plus this overlay is enough.

What changed against the 6.13 series:

| 6.13 patch | 7.2 |
|---|---|
| 0001 DPU ACTIVE CTL for bonded DSI | upstream (6.15) |
| 0002 DSI PHY order + error irq | PHY order upstream; the `dsi_err_rearm` hack stays (0001) |
| 0004 simpledrm interconnect vote | ported: simpledrm moved to `drm/sysfb` and onto `drm_sysfb_device` |
| 0005 sm8450 interconnect link IDs | obsolete: the driver links nodes by pointer now |
| 0006 nvt-ts Samsung firmware | ported (upstream dropped the wake_type check) |
| 0003 NT36523 panel | ported to the `mipi_dsi_*_multi` helpers |
| 0008 max17042 max77705-battery | upstream |
| 0009 charger drivers | `power_supply_config.of_node` -> `fwnode`. Upstream has gained its own MAX77705 MFD/charger driver (binds `maxim,max77705`); ours binds `maxim,max77705-charger-monitor`, no conflict |
| 0011 MI2S/AudioReach | CPU fmt, `lpaif_type`, `q6i2s set_fmt` upstream; codec fmt/bclk stays (0008) |
| 0013 dwc3 SUSPENDENABLE | upstream (it was a backport) |
| 0015 LPASS LPI runtime PM | upstream has its own (sm8450 included) |
| 0017 board DTS | `usb_1_dwc3` folded into the flattened `usb_1`; CoreSight nodes new to `sm8450.dtsi` disabled |

Checked: the 7.2 DTB against the 6.13 one, node by node. Besides the above, every
difference comes from upstream dtsi fixes (sleep clock 32764 Hz, MMCX+MXC for camcc/videocc,
DP MST stream-1 clocks, crypto clocks, reg sizes, timer IRQ masks); `camcc` is now enabled
but its driver is not built. Config: arm64 `defconfig` builds sound as modules since 6.15,
so `x700.config` sets `SOUND`/`SND`/`SND_SOC=y` to keep the built-in audio chain.

To verify on the tablet first: display (bonded DSI via upstream ACTIVE CTL), audio
(the upstream LPI runtime PM instead of ours), USB-C both orientations and DP alt mode
(flattened DWC3), suspend (CX collapse with the upstream LPI PM).

`patches*/` are plain unified diffs (`-p1`) against exactly that base; they are
independent of each other except where a file is created and later touched.
`./build.sh` fetches the tarball, applies them in order and builds `Image` + the DTB;
`regen-patches.sh` writes them back from an edited tree (`BASE=7.2` for the 7.2 series).
