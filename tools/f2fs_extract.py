#!/usr/bin/env python3
"""
Minimal read-only F2FS raw-image walker/extractor.

Purpose-built for the SM-X700 firmware harvest: parse an unsparsed F2FS
image (vendor.img / vendor_dlkm.img / odm.img, already run through
simg2img) directly off disk, with no mount, no loop device, and no root,
and pull specific files/directories out to a destination tree.

This is an original implementation written directly against the on-disk
F2FS layout (linux/fs/f2fs/f2fs.h struct definitions: f2fs_super_block,
f2fs_checkpoint, f2fs_node/f2fs_inode, f2fs_dentry_block, NAT entries).
It only opens the given image read-only and only writes under the
destination path passed on the command line.

Usage:
  f2fs_extract.py <image> tree [path] [depth]
  f2fs_extract.py <image> find <glob-pattern> [path]
  f2fs_extract.py <image> extractdir <path> <dest>
  f2fs_extract.py <image> extract <path> <dest-file>
  f2fs_extract.py <image> info
"""
import struct, sys, os, stat, fnmatch

MAGIC = 0xF2F52010
SB_OFF = 1024
NAT_ENTRY_SIZE = 9
DIR_ENTRY_SIZE = 11
NR_DENTRY_IN_BLOCK = 214
DENTRY_BITMAP_SIZE = 27
SLOT_LEN = 8
NEW_ADDR = 0xFFFFFFFF
COMPRESS_ADDR = 0xFFFFFFFE
CP_LARGE_NAT_BITMAP_FLAG = 0x00000400
COMPRESS_HEADER_SIZE = 24  # clen(4) + chksum(4) + reserved(16)

FT_DIR = 2
FT_SYMLINK = 7


def lz4_block_decompress(data, expected_size):
    """Pure-python decoder for the raw LZ4 'block' format (no frame header),
    as produced by f2fs's inline compression. Verified against real
    compressed clusters harvested from this vendor image (ELF magic lands
    exactly where the first literal run says it should)."""
    out = bytearray()
    i, n = 0, len(data)
    while i < n:
        token = data[i]; i += 1
        lit_len = token >> 4
        if lit_len == 15:
            while True:
                b = data[i]; i += 1
                lit_len += b
                if b != 255:
                    break
        out += data[i:i + lit_len]
        i += lit_len
        if i >= n:
            break
        offset = data[i] | (data[i + 1] << 8)
        i += 2
        match_len = (token & 0xF) + 4
        if (token & 0xF) == 15:
            match_len = 15 + 4
            while True:
                b = data[i]; i += 1
                match_len += b
                if b != 255:
                    break
        start = len(out) - offset
        for k in range(match_len):
            out.append(out[start + k])
        if expected_size and len(out) >= expected_size:
            break
    return bytes(out[:expected_size]) if expected_size else bytes(out)


class F2FS:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self._sb()
        self._cp()

    def _blk(self, addr):
        self.f.seek(addr * self.bsz)
        return self.f.read(self.bsz)

    def _sb(self):
        self.f.seek(SB_OFF)
        d = self.f.read(512)
        magic = struct.unpack_from('<I', d, 0)[0]
        if magic != MAGIC:
            raise ValueError(f"not f2fs: magic=0x{magic:08x}")
        g = lambda o, t='<I': struct.unpack_from(t, d, o)[0]
        self.log_blocksize = g(16)
        self.log_blocks_per_seg = g(20)
        self.block_count = g(36, '<Q')
        self.nat_blkaddr = g(84)
        self.root_ino = g(96)
        self.bsz = 1 << self.log_blocksize
        self.blocks_per_seg = 1 << self.log_blocks_per_seg
        self.nat_epb = self.bsz // NAT_ENTRY_SIZE
        self.sb_cp_blkaddr = g(76)

    def _cp(self):
        cpb = self.sb_cp_blkaddr
        d = self._blk(cpb)
        ckpt_flags = struct.unpack_from('<I', d, 132)[0]
        sit_bm = struct.unpack_from('<I', d, 156)[0]
        nat_bm = struct.unpack_from('<I', d, 160)[0]
        BM_OFF = 192
        self.nat_bitmap = None
        try:
            if ckpt_flags & CP_LARGE_NAT_BITMAP_FLAG:
                bm = self._blk(cpb + 1)
                self.nat_bitmap = bm[:nat_bm]
            elif BM_OFF + sit_bm + nat_bm <= self.bsz:
                start = BM_OFF + sit_bm
                self.nat_bitmap = d[start:start + nat_bm]
            else:
                part1 = d[BM_OFF + sit_bm:]
                bm = self._blk(cpb + 1)
                need = nat_bm - len(part1)
                self.nat_bitmap = part1 + bm[:max(need, 0)]
        except Exception:
            self.nat_bitmap = None

    def _nat_set1(self, block_idx):
        if self.nat_bitmap is None:
            return False
        bi, bit = block_idx // 8, block_idx % 8
        if bi >= len(self.nat_bitmap):
            return False
        return bool(self.nat_bitmap[bi] & (1 << bit))

    def _nat_entry(self, nid):
        block_off = nid // self.nat_epb
        entry_off = nid % self.nat_epb
        seg_off = block_off // self.blocks_per_seg
        blk_in_seg = block_off % self.blocks_per_seg
        set0 = self.nat_blkaddr + seg_off * 2 * self.blocks_per_seg + blk_in_seg
        set1 = self.nat_blkaddr + (seg_off * 2 + 1) * self.blocks_per_seg + blk_in_seg

        def rd(pb):
            d = self._blk(pb)
            off = entry_off * NAT_ENTRY_SIZE
            return struct.unpack_from('<I', d, off + 1)[0], struct.unpack_from('<I', d, off + 5)[0]

        primary, secondary = (set1, set0) if self._nat_set1(block_off) else (set0, set1)
        ino, addr = rd(primary)
        if addr not in (0, NEW_ADDR) and addr < self.block_count:
            return ino, addr
        ino2, addr2 = rd(secondary)
        if addr2 not in (0, NEW_ADDR) and addr2 < self.block_count:
            return ino2, addr2
        return ino, addr

    def _read_node(self, nid):
        ino, blkaddr = self._nat_entry(nid)
        if blkaddr in (0, NEW_ADDR):
            return None
        d = self._blk(blkaddr)
        footer_nid = struct.unpack_from('<I', d, 4072)[0]
        if footer_nid == nid:
            return d
        # fall back: try the alternate NAT set explicitly
        block_off = nid // self.nat_epb
        entry_off = nid % self.nat_epb
        seg_off = block_off // self.blocks_per_seg
        blk_in_seg = block_off % self.blocks_per_seg
        for s in (0, 1):
            alt = self.nat_blkaddr + (seg_off * 2 + s) * self.blocks_per_seg + blk_in_seg
            if alt == blkaddr:
                continue
            ad = self._blk(alt)
            off = entry_off * NAT_ENTRY_SIZE
            addr = struct.unpack_from('<I', ad, off + 5)[0]
            if addr in (0, NEW_ADDR) or addr >= self.block_count:
                continue
            nd = self._blk(addr)
            if struct.unpack_from('<I', nd, 4072)[0] == nid:
                return nd
        return d

    def inode(self, nid):
        d = self._read_node(nid)
        if d is None:
            return None
        inode = {'raw': d}
        inode['mode'] = struct.unpack_from('<H', d, 0)[0]
        inode['inline'] = d[3]
        inode['uid'] = struct.unpack_from('<I', d, 4)[0]
        inode['gid'] = struct.unpack_from('<I', d, 8)[0]
        inode['size'] = struct.unpack_from('<Q', d, 16)[0]
        addr_start = 360
        extra_isize = 0
        inline_xattr_size = 0
        if inode['inline'] & 0x20:  # EXTRA_ATTR
            extra_isize = struct.unpack_from('<H', d, 360)[0]
            inline_xattr_size = struct.unpack_from('<H', d, 362)[0]
            addr_start = 360 + extra_isize
        total_slots = (4052 - addr_start) // 4
        if inode['inline'] & 0x01:  # INLINE_XATTR
            xattr_slots = inline_xattr_size if inline_xattr_size > 0 else 50
            num_addrs = total_slots - xattr_slots
        else:
            num_addrs = total_slots
        inode['addr_start'] = addr_start
        inode['num_addrs'] = num_addrs
        inode['addr'] = [struct.unpack_from('<I', d, addr_start + i * 4)[0] for i in range(num_addrs)]
        nid_start = 4052
        inode['nid'] = [struct.unpack_from('<I', d, nid_start + i * 4)[0] for i in range(5)]

        # Compression params (f2fs inline compression). When EXTRA_ATTR is
        # set, the 4 bytes immediately before the address array are
        # [i_compress_algorithm(1)][i_log_cluster_size(1)][i_compress_flag(2)].
        # Harmless to read even on filesystems without the compression
        # feature -- cluster_size just won't matter since no COMPRESS_ADDR
        # markers will ever appear in inode['addr'].
        inode['compress_algo'] = None
        inode['cluster_size'] = 0
        if (inode['inline'] & 0x20) and addr_start >= 360 + 4:
            algo = d[addr_start - 4]
            log_cluster = d[addr_start - 3]
            if 0 < log_cluster <= 8:  # sane cluster size (4..256 blocks)
                inode['compress_algo'] = algo
                inode['cluster_size'] = 1 << log_cluster
        return inode

    # Sentinels used in the raw (pre-cluster-resolution) block list.
    HOLE = 'HOLE'
    CMARK = 'CMARK'

    def _raw_blocks(self, inode):
        """Flat list of per-logical-block entries: an int block address,
        or HOLE (NULL/NEW_ADDR) or CMARK (compressed-cluster marker slot)."""
        def tag(a):
            if a == COMPRESS_ADDR:
                return self.CMARK
            if a in (0, NEW_ADDR):
                return self.HOLE
            return a

        blocks = [tag(a) for a in inode['addr']]
        for idx in range(2):  # single-indirect
            nid = inode['nid'][idx]
            if nid == 0:
                continue
            nd = self._read_node(nid)
            if nd is None:
                continue
            for i in range(1018):
                blocks.append(tag(struct.unpack_from('<I', nd, i * 4)[0]))
        for idx in range(2, 4):  # double-indirect
            nid = inode['nid'][idx]
            if nid == 0:
                continue
            nd = self._read_node(nid)
            if nd is None:
                continue
            for i in range(1018):
                cnid = struct.unpack_from('<I', nd, i * 4)[0]
                if cnid == 0:
                    continue
                cd = self._read_node(cnid)
                if cd is None:
                    continue
                for j in range(1018):
                    blocks.append(tag(struct.unpack_from('<I', cd, j * 4)[0]))
        return blocks

    def _data_blocks(self, inode):
        """Back-compat: flat list of block addr or None (hole/compressed-away).
        Used only by list_dir/_get callers that don't need decompression."""
        return [None if b in (self.HOLE, self.CMARK) else b for b in self._raw_blocks(inode)]

    def read_file(self, nid):
        inode = self.inode(nid)
        if inode is None:
            return b''
        size = inode['size']
        if inode['inline'] & 0x02:  # INLINE_DATA
            d = inode['raw']
            # Inline data begins after DEF_INLINE_RESERVED_SIZE (one u32) of
            # the address array, and holds 4 * (num_addrs - 1) bytes.
            start = inode['addr_start'] + 4
            avail = (inode['num_addrs'] - 1) * 4
            return d[start:start + min(size, avail)]

        cluster_size = inode['cluster_size']
        raw_blocks = self._raw_blocks(inode)

        out = bytearray()
        if cluster_size:
            i = 0
            n = len(raw_blocks)
            while i < n and len(out) < size:
                group = raw_blocks[i:i + cluster_size]
                i += cluster_size
                if group and group[0] == self.CMARK:
                    real_addrs = [b for b in group if isinstance(b, int)]
                    payload = b''.join(self._blk(a) for a in real_addrs)
                    clen = struct.unpack_from('<I', payload, 0)[0]
                    comp = payload[COMPRESS_HEADER_SIZE:COMPRESS_HEADER_SIZE + clen]
                    want = cluster_size * self.bsz
                    if inode['compress_algo'] == 1:  # LZ4
                        dec = lz4_block_decompress(comp, want)
                    else:
                        # Unsupported algorithm (LZO/ZSTD/LZO-RLE) -- can't
                        # safely reconstruct; emit zeros so the caller can
                        # detect/flag rather than silently misdecoding.
                        dec = b'\x00' * want
                    out += dec
                else:
                    for b in group:
                        if isinstance(b, int):
                            out += self._blk(b)
                        else:
                            out += b'\x00' * self.bsz
        else:
            for b in raw_blocks:
                if len(out) >= size:
                    break
                if isinstance(b, int):
                    out += self._blk(b)
                else:
                    out += b'\x00' * self.bsz

        return bytes(out[:size])

    def _dentry_block(self, d):
        bitmap = d[:DENTRY_BITMAP_SIZE]
        dstart = DENTRY_BITMAP_SIZE + 3
        fstart = dstart + NR_DENTRY_IN_BLOCK * DIR_ENTRY_SIZE
        entries = []
        i = 0
        while i < NR_DENTRY_IN_BLOCK:
            bi, bit = i // 8, i % 8
            if bi >= len(bitmap) or not (bitmap[bi] & (1 << bit)):
                i += 1
                continue
            off = dstart + i * DIR_ENTRY_SIZE
            ino = struct.unpack_from('<I', d, off + 4)[0]
            nlen = struct.unpack_from('<H', d, off + 8)[0]
            ftype = d[off + 10]
            foff = fstart + i * SLOT_LEN
            name = d[foff:foff + nlen].decode('utf-8', 'replace') if foff + nlen <= len(d) else f'<ino:{ino}>'
            if ino > 0 and nlen > 0:
                entries.append((name, ino, ftype))
            i += max((nlen + SLOT_LEN - 1) // SLOT_LEN, 1)
        return entries

    def _inline_dentry(self, inode):
        d = inode['raw']
        avail = inode['num_addrs'] * 4
        idata = d[inode['addr_start']:inode['addr_start'] + avail]
        nr = 0
        for t in range(1, 1000):
            bm = (t + 7) // 8
            total = bm + 4 + t * DIR_ENTRY_SIZE + t * SLOT_LEN
            if total > avail:
                nr = t - 1
                break
        else:
            nr = t
        if nr <= 0:
            return []
        bm_size = (nr + 7) // 8
        dsize = nr * DIR_ENTRY_SIZE
        fsize = nr * SLOT_LEN
        reserved = avail - bm_size - dsize - fsize
        if reserved < 0:
            nr -= 1
            bm_size = (nr + 7) // 8
            dsize = nr * DIR_ENTRY_SIZE
            fsize = nr * SLOT_LEN
            reserved = avail - bm_size - dsize - fsize
        bitmap = idata[:bm_size]
        dstart = bm_size + reserved
        fstart = dstart + dsize
        entries = []
        i = 0
        while i < nr:
            bi, bit = i // 8, i % 8
            if bi >= len(bitmap) or not (bitmap[bi] & (1 << bit)):
                i += 1
                continue
            off = dstart + i * DIR_ENTRY_SIZE
            ino = struct.unpack_from('<I', idata, off + 4)[0]
            nlen = struct.unpack_from('<H', idata, off + 8)[0]
            ftype = idata[off + 10]
            foff = fstart + i * SLOT_LEN
            name = idata[foff:foff + nlen].decode('utf-8', 'replace') if foff + nlen <= len(idata) else f'<ino:{ino}>'
            if ino > 0 and nlen > 0:
                entries.append((name, ino, ftype))
            i += max((nlen + SLOT_LEN - 1) // SLOT_LEN, 1)
        return entries

    def list_dir(self, nid):
        inode = self.inode(nid)
        if inode is None:
            return []
        if inode['inline'] & 0x04:  # INLINE_DENTRY
            return self._inline_dentry(inode)
        entries = []
        blocks = self._data_blocks(inode)
        needed = (inode['size'] + self.bsz - 1) // self.bsz
        for i, a in enumerate(blocks):
            if i >= needed:
                break
            if a is None:
                continue
            entries.extend(self._dentry_block(self._blk(a)))
        return entries

    def resolve(self, path):
        path = path.strip('/')
        if path == '':
            return self.root_ino, self.inode(self.root_ino)
        cur = self.root_ino
        for part in path.split('/'):
            entries = self.list_dir(cur)
            m = [e for e in entries if e[0] == part]
            if not m:
                return None, None
            cur = m[0][1]
        return cur, self.inode(cur)

    def walk(self, path='/'):
        """Yield (path, ino, ftype) for every entry under path, recursively."""
        nid, inode = self.resolve(path)
        if inode is None or not stat.S_ISDIR(inode['mode']):
            return
        for name, ino, ft in self.list_dir(nid):
            if name in ('.', '..'):
                continue
            cp = f"{path.rstrip('/')}/{name}"
            yield cp, ino, ft
            if ft == FT_DIR:
                yield from self.walk(cp)

    def extract_dir(self, path, dest):
        nid, inode = self.resolve(path)
        if inode is None:
            print(f"not found: {path}", file=sys.stderr)
            return
        if not stat.S_ISDIR(inode['mode']):
            self.extract_file(path, dest)
            return
        os.makedirs(dest, exist_ok=True)
        for name, ino, ft in self.list_dir(nid):
            if name in ('.', '..'):
                continue
            cp = f"{path.rstrip('/')}/{name}"
            cd = os.path.join(dest, name)
            if ft == FT_DIR:
                self.extract_dir(cp, cd)
            elif ft == FT_SYMLINK:
                try:
                    tgt = self.read_file(ino).decode('utf-8', 'replace')
                    if os.path.exists(cd) or os.path.islink(cd):
                        os.unlink(cd)
                    os.symlink(tgt, cd)
                except Exception as e:
                    print(f"warn symlink {cp}: {e}", file=sys.stderr)
            else:
                try:
                    data = self.read_file(ino)
                    with open(cd, 'wb') as fh:
                        fh.write(data)
                    print(f"{cp} ({len(data)} bytes)")
                except Exception as e:
                    print(f"warn extract {cp}: {e}", file=sys.stderr)

    def extract_file(self, path, dest_file):
        nid, inode = self.resolve(path)
        if inode is None:
            print(f"not found: {path}", file=sys.stderr)
            return False
        data = self.read_file(nid)
        os.makedirs(os.path.dirname(dest_file) or '.', exist_ok=True)
        with open(dest_file, 'wb') as fh:
            fh.write(data)
        print(f"{path} -> {dest_file} ({len(data)} bytes)")
        return True


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    img, cmd = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    fs = F2FS(img)

    if cmd == 'info':
        print(f"block_count={fs.block_count} bsz={fs.bsz} root_ino={fs.root_ino}")
    elif cmd == 'tree' or cmd == 'find':
        path = args[0] if args and cmd == 'tree' else '/'
        pattern = args[0] if cmd == 'find' else None
        for p, ino, ft in fs.walk(path if cmd == 'tree' else '/'):
            if cmd == 'find':
                name = p.rsplit('/', 1)[-1]
                if not fnmatch.fnmatch(name, pattern):
                    continue
            tag = 'd' if ft == FT_DIR else ('l' if ft == FT_SYMLINK else '-')
            print(f"{tag} {p}")
    elif cmd == 'extractdir':
        fs.extract_dir(args[0], args[1])
    elif cmd == 'extract':
        fs.extract_file(args[0], args[1])
    else:
        print(f"unknown command {cmd}")
        sys.exit(1)


if __name__ == '__main__':
    main()
