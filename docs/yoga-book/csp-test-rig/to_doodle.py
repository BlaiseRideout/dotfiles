import sys, time, subprocess, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
for attempt in range(6):
    probe.launch({})
    t0 = time.time()
    while time.time() - t0 < 60 and not probe.splash(): time.sleep(1)
    time.sleep(18)
    s = probe.splash(); m = inputrig.Mouse()
    m.click(s["at"][0] + 883, s["at"][1] + 468, hold=0.15, approach=True)
    t1 = time.time()
    while time.time() - t1 < 25 and probe.splash(): time.sleep(0.5)
    ok = probe.splash() is None
    print("attempt", attempt, "doodle click", "landed" if ok else "missed", flush=True)
    if ok:
        time.sleep(14)
        m.click(876, 345, hold=0.12, approach=True); time.sleep(22)   # 'Setting up' OK
        m.click(950, 98, hold=0.12, approach=True); time.sleep(2)     # close blank welcome dialog
        m.close(); break
    m.close()
print([(c["title"], c["size"]) for c in probe.clients() if c["size"][0] > 1])
