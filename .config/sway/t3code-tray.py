#!/usr/bin/python3
"""Tray icon for T3 Code (which has none of its own).

Click: bring the window back from the Sway scratchpad (or focus it), starting T3 Code if
it isn't running. Middle click: toggle (hide to the scratchpad). Right click: menu.

Sway ignores xdg-toplevel minimize requests, so T3 Code's own minimize button does nothing
there. To make it hide to the tray, the main process is hooked once per run: SIGUSR1 opens
Node's inspector on 127.0.0.1:9229, we replace BrowserWindow.minimize (and listen for the
'minimize' event) to send the window to the scratchpad, then close the inspector again.

The tray item is hand-written StatusNotifierItem + dbusmenu: libayatana-appindicator has no
Activate method, so Waybar's left click would do nothing.
"""
import asyncio
import json
import os
import signal
import subprocess
import threading
import time
import urllib.request

import websockets
from gi.repository import Gio, GLib

APP_ID = "com.t3tools.T3Code"
ICON = "com.t3tools.t3code"
LAUNCHER = os.path.expanduser("~/.local/bin/t3code")
ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"

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


def sway(*cmd):
    return subprocess.run(["swaymsg", *cmd], capture_output=True, text=True)


def find_window():
    """Return (node, hidden) for the T3 Code window, or (None, False)."""
    tree = json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree"]))
    stack = [(tree, None)]
    while stack:
        node, ws = stack.pop()
        if node.get("type") == "workspace":
            ws = node["name"]
        if node.get("app_id") == APP_ID:
            return node, ws == "__i3_scratch"
        stack.extend((c, ws) for c in node.get("nodes", []) + node.get("floating_nodes", []))
    return None, False


def reveal():
    win, hidden = find_window()
    if win is None:
        subprocess.Popen(["swaymsg", "exec", LAUNCHER])
    elif hidden:
        # scratchpad show floats it; restore tiling and focus it on the current workspace
        sway(f"[con_id={win['id']}] scratchpad show, floating disable, focus")
    else:
        sway(f"[con_id={win['id']}] focus")


def toggle():
    win, hidden = find_window()
    if win is not None and not hidden:
        sway(f"[con_id={win['id']}] move scratchpad")
    else:
        reveal()


def quit_app():
    win, _hidden = find_window()
    if win is not None:
        sway(f"[con_id={win['id']}] kill")


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


class Hooker:
    """Re-hook whenever a new T3 Code process shows up."""

    def __init__(self):
        self.hooked = None
        self.busy = False

    def tick(self):
        pid = main_pid()
        if pid and pid != self.hooked and not self.busy:
            self.busy = True
            threading.Thread(target=self._run, args=(pid,), daemon=True).start()
        return True

    def _run(self, pid):
        if inject(pid):
            self.hooked = pid
        self.busy = False


SNI_XML = """<node><interface name="org.kde.StatusNotifierItem">
  <property name="Category" type="s" access="read"/>
  <property name="Id" type="s" access="read"/>
  <property name="Title" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="WindowId" type="u" access="read"/>
  <property name="IconName" type="s" access="read"/>
  <property name="IconThemePath" type="s" access="read"/>
  <property name="OverlayIconName" type="s" access="read"/>
  <property name="AttentionIconName" type="s" access="read"/>
  <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
  <property name="ItemIsMenu" type="b" access="read"/>
  <property name="Menu" type="o" access="read"/>
  <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>"""

MENU_XML = """<node><interface name="com.canonical.dbusmenu">
  <property name="Version" type="u" access="read"/>
  <property name="TextDirection" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="IconThemePath" type="as" access="read"/>
  <method name="GetLayout">
    <arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
    <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
  <method name="GetGroupProperties">
    <arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/></method>
  <method name="GetProperty">
    <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
  <method name="Event">
    <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
  <method name="EventGroup"><arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/></method>
  <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
  <method name="AboutToShowGroup">
    <arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/></method>
  <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
</interface></node>"""

MENU_ITEMS = {1: ("Show T3 Code", reveal), 2: ("Hide / show T3 Code", toggle), 3: ("Quit T3 Code", quit_app)}


def item_props(i):
    return {"label": GLib.Variant("s", MENU_ITEMS[i][0]), "enabled": GLib.Variant("b", True),
            "visible": GLib.Variant("b", True)}


def sni_property(_conn, _sender, _path, _iface, name):
    return {
        "Category": GLib.Variant("s", "ApplicationStatus"),
        "Id": GLib.Variant("s", "t3code"),
        "Title": GLib.Variant("s", "T3 Code"),
        "Status": GLib.Variant("s", "Active"),
        "WindowId": GLib.Variant("u", 0),
        "IconName": GLib.Variant("s", ICON),
        "IconThemePath": GLib.Variant("s", ""),
        "OverlayIconName": GLib.Variant("s", ""),
        "AttentionIconName": GLib.Variant("s", ""),
        "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], "T3 Code", "Click to show the window")),
        "ItemIsMenu": GLib.Variant("b", False),
        "Menu": GLib.Variant("o", MENU_PATH),
    }[name]


def sni_call(_conn, _sender, _path, _iface, method, _params, invocation):
    # Run on a thread: reveal() shells out to swaymsg and must not block the D-Bus main loop
    action = {"Activate": reveal, "SecondaryActivate": toggle}.get(method)
    if action:
        threading.Thread(target=action, daemon=True).start()
    invocation.return_value(None)


def menu_property(_conn, _sender, _path, _iface, name):
    return {
        "Version": GLib.Variant("u", 3),
        "TextDirection": GLib.Variant("s", "ltr"),
        "Status": GLib.Variant("s", "normal"),
        "IconThemePath": GLib.Variant("as", []),
    }[name]


def menu_call(_conn, _sender, _path, _iface, method, params, invocation):
    if method == "GetLayout":
        children = [GLib.Variant("(ia{sv}av)", (i, item_props(i), [])) for i in MENU_ITEMS]
        root = (0, {"children-display": GLib.Variant("s", "submenu")}, children)
        invocation.return_value(GLib.Variant("(u(ia{sv}av))", (1, root)))
    elif method == "GetGroupProperties":
        ids = params.unpack()[0] or list(MENU_ITEMS)
        invocation.return_value(GLib.Variant("(a(ia{sv}))", ([(i, item_props(i)) for i in ids if i in MENU_ITEMS],)))
    elif method == "GetProperty":
        i, name = params.unpack()
        invocation.return_value(GLib.Variant("(v)", (item_props(i)[name],)))
    elif method in ("Event", "EventGroup"):
        events = [params.unpack()] if method == "Event" else params.unpack()[0]
        for i, kind, _data, _ts in events:
            if kind == "clicked" and i in MENU_ITEMS:
                threading.Thread(target=MENU_ITEMS[i][1], daemon=True).start()
        invocation.return_value(GLib.Variant("(ai)", ([],)) if method == "EventGroup" else None)
    elif method == "AboutToShow":
        invocation.return_value(GLib.Variant("(b)", (False,)))
    elif method == "AboutToShowGroup":
        invocation.return_value(GLib.Variant("(aiai)", ([], [])))
    else:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


def main():
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    conn.register_object(ITEM_PATH, Gio.DBusNodeInfo.new_for_xml(SNI_XML).interfaces[0], sni_call, sni_property, None)
    conn.register_object(MENU_PATH, Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0], menu_call, menu_property, None)

    name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
    Gio.bus_own_name_on_connection(conn, name, Gio.BusNameOwnerFlags.NONE, None, None)

    def register(*_):
        # Waybar owns the watcher, so this also runs again each time Waybar restarts
        conn.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                       "RegisterStatusNotifierItem", GLib.Variant("(s)", (name,)), None, Gio.DBusCallFlags.NONE, -1)

    Gio.bus_watch_name_on_connection(conn, "org.kde.StatusNotifierWatcher", Gio.BusNameWatcherFlags.NONE, register, None)

    hooker = Hooker()
    hooker.tick()
    GLib.timeout_add_seconds(5, hooker.tick)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
