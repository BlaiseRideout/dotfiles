Zoom uses native Wayland so the sharing toolbar accepts clicks. Home Manager
activation applies `xwayland=false` and `enableWaylandShare=true` to the writable
`zoomus.conf`, preserving all other settings. Quit Zoom before activating so
Zoom cannot overwrite the changes on exit. The launcher never edits its config.

On NVIDIA Wayland sessions, `~/.local/libexec/zoom/launch.sh` selects Mesa's CPU OpenGL renderer
when its EGL vendor file is available. This fixes corrupted icons and text while
keeping the sharing preview working. It uses more CPU than GPU rendering. Other
GPU/session combinations use their normal rendering environment.

Known limitation with Zoom 7.2.5: the meeting's Settings sidebar may not redraw
until the meeting window loses focus. Use Settings in the main window or click
another window after toggling the sidebar. Full compositor redraws, click-to-focus,
floating the meeting, and Qt vsync/atlas/text workarounds did not resolve it.
Qt's software backend broke the preview; XWayland broke the Stop Share button.
