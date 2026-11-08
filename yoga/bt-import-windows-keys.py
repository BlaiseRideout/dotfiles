#!/usr/bin/env python3
"""Turn Windows Bluetooth LE pairing keys into BlueZ `info` files.

Reads the SYSTEM registry hive of a Windows install (a COPY of it; never point this
at the live file) and, for every paired device whose name matches --name, writes
    <out>/<ADAPTER MAC>/<DEVICE MAC>/info
which you then copy into /var/lib/bluetooth as root. The files hold secret keys:
keep --out outside the repo, mode 0700.

Needs python-registry (pip install python-registry, in a venv) since the system
python has no hive parser.

    python -I yoga/bt-import-windows-keys.py SYSTEM-copy --name "Yoga Book 9 Bluetooth KB" --out ~/bt-stage

Only LE devices (BTHPORT\\Parameters\\Keys\\<adapter>\\<device> subkeys) are handled;
classic devices store a single 16-byte link key and need a [LinkKey] section instead.
The conversions follow carvsdriver/yoga-book-9-linux setup/btreg.py: LTK as hex,
ERand as a little-endian 64-bit integer, EDIV as an integer.
"""
import argparse
import os
import sys

from Registry import Registry

BASE = "ControlSet001\\Services\\BTHPORT\\Parameters"


def mac(h):
    return ":".join(h[i:i + 2] for i in range(0, 12, 2)).upper()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hive")
    ap.add_argument("--name", required=True, help="exact Windows device name")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    reg = Registry.Registry(a.hive)
    devices = {}
    for d in reg.open(BASE + "\\Devices").subkeys():
        v = {x.name(): x.value() for x in d.values()}
        n = v.get("Name")
        if isinstance(n, (bytes, bytearray)):
            n = bytes(n).rstrip(b"\0").decode("utf8", "replace")
        devices[d.name().lower()] = n

    wrote = 0
    for adapter in reg.open(BASE + "\\Keys").subkeys():
        for dev in adapter.subkeys():
            if devices.get(dev.name().lower()) != a.name:
                continue
            v = {x.name(): x.value() for x in dev.values()}
            if "LTK" not in v:
                print(f"skip {mac(dev.name())}: no LTK", file=sys.stderr)
                continue
            first = int(dev.name()[:2], 16)
            # top two address bits 11 = static random, otherwise assume public
            addr_type = "static" if first >> 6 == 3 else "public"
            lines = [
                "[General]",
                f"Name={a.name}",
                f"AddressType={addr_type}",
                "SupportedTechnologies=LE;",
                "Trusted=true",
                "Blocked=false",
                "",
            ]
            if "IRK" in v:
                lines += ["[IdentityResolvingKey]", f"Key={bytes(v['IRK']).hex().upper()}", ""]
            if "CSRK" in v:
                lines += ["[LocalSignatureKey]", f"Key={bytes(v['CSRK']).hex().upper()}",
                          "Counter=0", "Authenticated=false", ""]
            lines += [
                "[LongTermKey]",
                f"Key={bytes(v['LTK']).hex().upper()}",
                "Authenticated=0",
                f"EncSize={v.get('KeyLength', 16)}",
                f"EDiv={v.get('EDIV', 0)}",
                f"Rand={v.get('ERand', 0)}",
                "",
            ]
            d = os.path.join(a.out, mac(adapter.name()), mac(dev.name()))
            os.makedirs(d, mode=0o700, exist_ok=True)
            p = os.path.join(d, "info")
            with open(os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
                f.write("\n".join(lines))
            print("wrote", p)
            wrote += 1
    if not wrote:
        sys.exit(f"no paired device named {a.name!r} with LE keys")


if __name__ == "__main__":
    main()
