import struct, hashlib, sys

PART = 104857600
VB_SIZE = 512
DESC = 256          # 描述符起点（vbmeta 头 256 字节、auth 块 0）
F_SIZE = DESC + 16  # image_size 字段
F_DIG  = DESC + 140 # sha256 摘要字段

def template():
    d = open('orig.img','rb').read()
    ks, rs, _, _ = struct.unpack_from('<IIII', d, 8)
    L = ((4096 + rs) + 4095)//4096*4096
    return d[L:L+VB_SIZE], d[-64:], L

def wrap(raw, part=PART):
    L = len(raw); assert L % 4096 == 0
    vb, foot, _ = template()
    vb = bytearray(vb); foot = bytearray(foot)
    struct.pack_into('>Q', vb, F_SIZE, L)
    vb[F_DIG:F_DIG+32] = hashlib.sha256(raw).digest()
    struct.pack_into('>Q', foot, 12, L)   # original_image_size
    struct.pack_into('>Q', foot, 20, L)   # vbmeta_offset
    struct.pack_into('>Q', foot, 28, VB_SIZE)
    out = bytearray(raw) + vb + b'\x00'*(part - L - VB_SIZE - 64) + foot
    assert len(out) == part
    return bytes(out)

def raw_of(ramdisk):
    orig = open('orig.img','rb').read()
    hdr = bytearray(orig[:1584])
    ram = open(ramdisk,'rb').read() if isinstance(ramdisk,str) else ramdisk
    struct.pack_into('<I', hdr, 0x08, 0)
    struct.pack_into('<I', hdr, 0x0c, len(ram))
    struct.pack_into('<I', hdr, 0x62c, 0)
    raw = bytearray(hdr) + b'\x00'*((-1584) % 4096) + ram
    raw += b'\x00'*((-len(raw)) % 4096)
    return bytes(raw)

if __name__ == '__main__':
    if sys.argv[1] == 'selftest':
        d = open('orig.img','rb').read()
        ks, rs, _, _ = struct.unpack_from('<IIII', d, 8)
        img = wrap(raw_of(d[4096:4096+rs]))
        print('重建原包与原件逐字节一致:', img == d)
    else:
        out = wrap(raw_of(sys.argv[1]))
        open(sys.argv[2],'wb').write(out)
        print('写出', sys.argv[2], len(out))
