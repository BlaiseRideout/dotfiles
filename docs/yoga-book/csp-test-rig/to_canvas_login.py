"""From the splash (any panel state with a Back button or the main page) log into the throwaway account and open Doodle mode."""
import sys, time, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
tm = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tempmail.json")))
s = probe.splash(); ox, oy = s["at"]
m = inputrig.Mouse(); k = inputrig.Keyboard()
def c(rx, ry, wait=3): m.click(ox + rx, oy + ry, hold=0.15, approach=True); time.sleep(wait)
c(97, 81, 4)            # Back out of the blank panel
c(883, 681, 5)          # Log in
c(883, 273, 1); inputrig.type_dvorak(k, tm["address"], dt=0.05)
c(883, 346, 1); inputrig.type_dvorak(k, tm["csp_password"], dt=0.05)
c(883, 440, 20)         # Log in button
c(687, 129, 4)          # Back from plan list
c(883, 468, 16)         # Doodle mode
m.click(876, 345, hold=0.12, approach=True); time.sleep(22)    # setup dialog OK
m.click(950, 98, hold=0.12, approach=True); time.sleep(2)      # close blank welcome dialog
m.close(); k.close()
print("windows:", [(c["title"], c["size"]) for c in probe.clients() if c["size"][0] > 1])
