#!/usr/bin/env python3
"""palm-probe: read-only: is the touch report rate a contact-size signal? Measures what docs/yoga-book/palm.md tabulates. Run with sudo (or once yoga/udev/64-yoga-palm.rules is in: without)."""
import glob, os, select, statistics as st, time
dev = next("/dev/" + os.path.basename(p) for p in glob.glob("/sys/class/hidraw/hidraw*")
           if "/3-6:1.3/" in os.path.realpath(p + "/device"))
fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
PHASES = ["fingertip held STILL", "fingertip MOVING (slow circles)",
          "flat palm held STILL", "flat palm MOVING (slide it slowly left-right)"]
for title in PHASES:
    print(f"\n=== {title}: starts in 3 s, 6 s ===", flush=True); time.sleep(3); print("GO", flush=True)
    end = time.time() + 6; rows = []
    while time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            try: b = os.read(fd, 4096)
            except BlockingIOError: continue
            if b[0] != 48 or len(b) < 57 or not b[1] & 1: continue
            rows.append((time.monotonic(), int.from_bytes(b[51:55], "little"),
                         b[2] | b[3] << 8, b[4] | b[5] << 8, b[55]))
    rows = rows[1:]  # first report after idle carries stale slots
    if len(rows) < 3: print("  too few reports:", len(rows)); continue
    wall = [b[0] - a[0] for a, b in zip(rows, rows[1:])]
    scan = [b[1] - a[1] for a, b in zip(rows, rows[1:])]
    step = [abs(b[2] - a[2]) + abs(b[3] - a[3]) for a, b in zip(rows, rows[1:])]
    print(f"  {len(rows)} reports = {len(rows)/6:.0f}/s, contacts reported max {max(r[4] for r in rows)}")
    print(f"  wall gap ms: median {st.median(wall)*1e3:.1f}  max {max(wall)*1e3:.0f}")
    print(f"  ScanTime delta: median {st.median(scan)} min {min(scan)} max {max(scan)}   (raw units)")
    print(f"  centroid step: median {st.median(step)}  mean {st.mean(step):.1f}  max {max(step)}   (x+y units; ~38 units/mm)")
