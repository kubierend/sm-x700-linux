# Kernel base

- Upstream: https://github.com/sm8450-mainline/linux (branch `next-new`), 6.13-rc3-based
- Pinned commit: `bf1d29fced6e156dd6090a9b6600a8c44259c114`
- Tarball: https://github.com/sm8450-mainline/linux/archive/bf1d29fced6e156dd6090a9b6600a8c44259c114.tar.gz
- Config: upstream `defconfig` + `sm8450.config`, then `config/x700.config`
  (and optionally `config/x700-debug.config`).

`patches/` are plain unified diffs (`-p1`) against exactly that commit; they are
independent of each other except where a file is created and later touched.
`./build.sh` fetches the tarball, applies them in order and builds `Image` + the DTB.
