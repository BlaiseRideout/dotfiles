#!/usr/bin/python3
# Run INSIDE the Bottles Flatpak (see csp-bottle.sh):
#   flatpak run --command=python3 com.usebottles.bottles bottles-install-components.py \
#       runner:caffe-9.2 dxvk:dxvk-2.5.2 vkd3d:vkd3d-proton-2.14.1
# bottles-cli can create bottles but cannot install a named runner/DXVK/vkd3d (it silently
# falls back to its defaults), so this calls the same ComponentManager the GUI uses.
import sys, warnings
warnings.filterwarnings("ignore")
import gi
gi.require_version("Gtk", "4.0")
sys.path.insert(1, "/app/share/bottles")
from gi.repository import Gio
from bottles.backend.managers.manager import Manager
from bottles.frontend.params import APP_ID

mng = Manager(g_settings=Gio.Settings.new(APP_ID), is_cli=True)
for spec in sys.argv[1:]:
    kind, name = spec.split(":", 1)
    res = mng.component_manager.install(kind, name)
    print(spec, "->", "ok" if getattr(res, "status", res) else f"FAILED {getattr(res, 'message', '')}")
