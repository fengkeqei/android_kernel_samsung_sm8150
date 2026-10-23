#!/usr/bin/env python3
# Pack a built kernel Image into a stock OS12 boot.img template.
#
# Usage: pack_boot_stock.py <template_boot.img> <Image> <out.img> [extra_cmdline...]
#
# Method (verified booting on SM-G9730 / stock Android 12):
#   - the kernel blob in the template starts at page 2 (offset 4096), its
#     size is the u32 at offset 8; the blob is UNCOMPRESSED_IMG header
#     (20 bytes, payload size at +16) + Image + DTB tail
#   - keep the template's DTB tail (this kernel builds no -dtb blob)
#   - keep the template's header verbatim (incl. the original `id` field),
#     only patch kernel_size and append extra cmdline args
#   - pad the result back to the template (partition) length
#
# The stock template (md5 66bbbc967d361a541f88f33443637ee9, 67108864 bytes)
# is kept at /home/dev/Projects/stockboot-template/boot-stock-os12.img
import struct, sys, hashlib

tmpl_p, img_p, out_p = sys.argv[1], sys.argv[2], sys.argv[3]
extra = ' '.join(sys.argv[4:]) if len(sys.argv) > 4 else 'skip_initramfs'

tmpl = open(tmpl_p, 'rb').read()
assert tmpl[:8] == b'ANDROID!', 'not an Android boot image'

ks = struct.unpack('<I', tmpl[8:12])[0]
blob = tmpl[4096:4096 + ks]
assert blob[:16] == b'UNCOMPRESSED_IMG', f'blob magic {blob[:16]!r}'
imgsz = struct.unpack('<I', blob[16:20])[0]
dtb_tail = blob[20 + imgsz:]
assert len(dtb_tail) > 0, 'no DTB tail found in template blob'

image = open(img_p, 'rb').read()
hdr = bytearray(20)
hdr[0:16] = b'UNCOMPRESSED_IMG'
struct.pack_into('<I', hdr, 16, len(image))
new_blob = bytes(hdr) + image + dtb_tail

out = bytearray(tmpl[:4096])
orig_cmd = bytes(out[64:576]).split(b'\0')[0].decode()
new_cmd = (orig_cmd + ' ' + extra).strip()
out[64:576] = new_cmd.encode() + b'\0' * (512 - len(new_cmd))
struct.pack_into('<I', out, 8, len(new_blob))
out += new_blob
assert len(out) <= len(tmpl), 'kernel blob larger than partition'
out += b'\0' * (len(tmpl) - len(out))
out = bytes(out)

open(out_p, 'wb').write(out)
print(f'cmdline: {new_cmd!r}')
print(f'blob: {len(new_blob)} (template {ks}), image {len(image)}, dtb {len(dtb_tail)}')
print(f'wrote {out_p}: {len(out)} bytes, md5={hashlib.md5(out).hexdigest()}')
