# Flat tray icons

Noctalia 5.4.1 cannot override individual tray icons. This adapter republishes
Dropbox and Discord's StatusNotifierItems using the flat white SVG artwork from
`.config/waybar/icons`. The bar hides Discord by its stable ID and Dropbox by
its stock icon names (matching Dropbox's ID also hides the proxy by its title).
Clicks and dbusmenu calls/signals are forwarded to the original applications.
Hover tooltips retain the original applications' text and update with their state.
Like the Waybar overrides, the artwork stays fixed through sync/unread states.
Other tray items are untouched.

The CachyOS user service uses `/usr/bin/python`, `python-dbus`, and
`python-gobject`. Home Manager links the files and enables the service for the
graphical session. Discovery runs every three seconds to handle application
restarts and Noctalia restarts. Missing applications become passive.

To remove this workaround, stop and disable `noctalia-flat-tray.service` and
remove the corresponding `widget.tray.hidden` entries in `dotfiles/bar.toml`.
