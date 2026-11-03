#!/usr/bin/python3
"""Make T3 Code's minimize button hide its window to the Sway scratchpad.

Sway ignores xdg-toplevel minimize requests, so the button does nothing there. Each new T3
Code main process is hooked once: SIGUSR1 opens Node's inspector on 127.0.0.1:9229, we
replace BrowserWindow.minimize (and listen for the 'minimize' event) to move the window to
the scratchpad, then close the inspector again. Checks for a new process every 5 s, so
restarts (e.g. after an update) are hooked too.

Showing it again is scratchpad-app.sh's job (Waybar's T3 button).
"""
import asyncio
import json
import os
import signal
import time
import urllib.request

import websockets

APP_ID = "com.t3tools.T3Code"

# Runs in T3 Code's main process. process.mainModule.require reaches electron and node builtins.
HOOK_JS = """(() => {
  const req = process.mainModule.require;
  const { BrowserWindow, app } = req('electron');
  const cp = req('child_process');
  const hide = () => cp.execFile('swaymsg', ['[app_id="%s"] move scratchpad'], () => {});
  if (!globalThis.__t3tray) {
    globalThis.__t3tray = true;
    BrowserWindow.prototype.minimize = function () { hide(); };
    const hook = (w) => w.on('minimize', () => { try { w.restore(); } catch (e) {} hide(); });
    BrowserWindow.getAllWindows().forEach(hook);
    app.on('browser-window-created', (_, w) => hook(w));
  }
  req('inspector').close();
  return 'hooked';
})()""" % APP_ID


def main_pid():
    """PID of T3 Code's Electron main process (the AppImage-mounted binary, no --type arg)."""
    for p in os.listdir("/proc"):
        if p.isdigit():
            try:
                argv = open(f"/proc/{p}/cmdline", "rb").read().split(b"\0")
            except OSError:
                continue
            if argv[0].startswith(b"/tmp/.mount_t3code") and argv[0].endswith(b"/t3code") and len(argv) <= 2:
                return int(p)
    return None


async def _inject(url):
    async with websockets.connect(url) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": HOOK_JS}}))
        await ws.recv()


def inject(pid):
    """Hook the minimize button of the T3 Code instance with this pid. True on success."""
    try:
        os.kill(pid, signal.SIGUSR1)
        for _ in range(30):
            try:
                info = json.load(urllib.request.urlopen("http://127.0.0.1:9229/json", timeout=1))
                break
            except OSError:
                time.sleep(0.2)
        else:
            return False
        asyncio.run(_inject(info[0]["webSocketDebuggerUrl"]))
        return True
    except (OSError, websockets.WebSocketException, KeyError, IndexError):
        return False


def main():
    hooked = None
    while True:
        pid = main_pid()
        if pid and pid != hooked and inject(pid):
            hooked = pid
        time.sleep(5)


if __name__ == "__main__":
    main()
