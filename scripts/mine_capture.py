"""Mine the observation capture: GOP topology, driver bindings, image fingerprints.

Usage: python mine_capture.py <capture-dir>
"""

import hashlib
import re
import sys
from pathlib import Path

CAP = Path(sys.argv[1] if len(sys.argv) > 1 else r"E:\AI\gpu-unlock-win\captures\RTX3090-UNLOCK")
text = (CAP / "DIAG00.TXT").read_text(errors="replace")
lines = text.splitlines()

print("=" * 70)
print("CAPTURE SUMMARY")
print("=" * 70)
for line in lines:
    if re.match(r"^(probe|gops|gop handle|console-out|driver-bindings|cfg256|subsystem|probe-bar0|mmio|prom sha256)", line):
        print(line[:160])

print()
print("=" * 70)
print("IMAGE DUMPS (index -> size, sha256, hints)")
print("=" * 70)

# index -> (base, size) from the text
imgs = {}
cur = None
for line in lines:
    m = re.match(r"img base=0x([0-9a-f]+)", line)
    if m:
        cur = {"base": int(m.group(1), 16)}
    m = re.match(r"img size=0x([0-9a-f]+)", line)
    if m and cur is not None:
        cur["size"] = int(m.group(1), 16)
    m = re.match(r"img dump index=([0-9a-f]+)", line)
    if m and cur is not None:
        imgs[int(m.group(1), 16)] = cur
        cur = None

HINTS = [b"nvgop", "NVIDIA".encode("utf-16-le"), b"NVIDIA", b"GOP", b"UEFI",
         "核显".encode("utf-16-le"), "Intel".encode("utf-16-le"), b"Intel"]
rows = []
for f in sorted(CAP.glob("IMG*.BIN")):
    idx = int(f.stem[3:], 16)
    data = f.read_bytes()
    hints = [h.decode("utf-16-le", "ignore") if h.startswith(b"\x00") is False and any(b == 0 for b in h) else h.decode("latin-1")
             for h in HINTS if h in data]
    # find PCI vendor:device pattern 86 80 (10de little endian) or DE 10
    pci = []
    if b"\xde\x10" in data:
        pci.append("10de-LE")
    if b"\xde\x10\x60\x25" in data:
        pci.append("2560")
    digest = hashlib.sha256(data).hexdigest()
    info = imgs.get(idx, {})
    rows.append((idx, len(data), info.get("size"), digest, hints, pci))
    print(f"IMG{idx:02d} file={len(data):7d} reg={info.get('size', 0):7d} "
          f"base=0x{info.get('base', 0):08x} hints={hints} pci={pci}")
    print(f"      sha256={digest}")

print()
print("=" * 70)
print("DRIVER BINDINGS (version / stop - profile fingerprints)")
print("=" * 70)
for i, line in enumerate(lines):
    if line.startswith("driver-bindings="):
        print(line)
        for follow in lines[i + 1:i + 40]:
            if follow.startswith("binding handle="):
                print(follow)
            elif follow.startswith("gops="):
                break

print()
print("=" * 70)
print("GOP HANDLES")
print("=" * 70)
for i, line in enumerate(lines):
    if line.startswith("gop handle=") or line.startswith("gops=") or line.startswith("console-out="):
        print(line)
