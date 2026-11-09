# Dock, on-screen keyboard and posture: one shared state

Four daemons care about the same few facts (is the keyboard docked, is the on-screen keyboard up, which posture).
Early on each read the dock itself and they disagreed during transitions. Now there is one authority.

## Rule

**`yoga-posture` is the only reader of the dock** (`keyboard_position`, 4 Hz; each read is an ACPI call). It
debounces it once, derives everything that follows, and publishes `$XDG_RUNTIME_DIR/yoga/state.json` four times a
second. `yoga-touchpad`, `yoga-bottom-reserve`, `yoga-osk`, `yoga-osk-lockwatch` read that file. If it is older
than 3 s (daemon down or stalled) they compute the same thing themselves with the same code
(`yoga/bin/yoga_state.py`, `python3 -I yoga/bin/yoga_state.py show`).

## Definitions (all constants in `yoga_state.py`)

- `dock_eff`: a non-zero reading is believed at once; **0 only after continuous 0 for 1.5 s** (`DOCK_DEBOUNCE_S`),
  **or 0.4 s when the position before it was 1** (`DOCK_DEBOUNCE_FROM_1_S`; undocking from the hinge position is
  the normal case and should be quick). So a slide 2 -> 1 never reads as undocked, but a slide 1 -> 2 shows as a
  brief undock (the on-screen keyboard may flash up) before 2 is read. The first reading is believed immediately. An unreadable file keeps the last value (resume).
- `osk.held`: the keyboard counts as visible at once and gone only after 1 s without its layer (`OSK_HOLD_S`), so
  restarting it in another mode doesn't flicker the bar.
- Derived (a pure function): `osk_allowed` (never while docked), `reserved` (the bottom screen's workspaces move
  away while the keyboard is up), `bar_hidden`, `touchpad_ok` (two screens lit, bottom at transform 0, not
  tablet/tent).

## Invariants

- Never the on-screen keyboard and the physical keyboard together: docking hides the on-screen one first.
- The touchpad grab is only held when the bottom panel is on, upright, and in a two-screen posture.
- A posture change hides the on-screen keyboard before the layout is applied, then waits for its layer to go.
- The posture daemon dying restores the laptop layout (`ExecStopPost=yoga-posture reset`) and removes the state file.

## Testing

`python3 yoga/tests/state-sim.py` replays slides, docking with the keyboard up, posture changes, fold glitches,
daemon restarts, reloads, resume and lock against the real code with a fake dock file and stubbed `hyprctl`/
`wvkbd`. It touches nothing of the session and checks the invariants. (Its fixtures still use a top transform of
2 as sample data; that doesn't affect what it checks.)

## Dock, pointer and the reserved bottom screen

While the bottom screen is reserved (`want.reserved`: dual screen and the keyboard docked or the on-screen one up) `yoga-bottom-reserve` hides Noctalia's dock on that screen (`dock.monitor.<out>.enabled`, restored when the service stops), and `yoga_layout()` parks the panel 10000 logical px below its place (`RESERVED_AWAY` in `yoga/hypr/yoga.lua`) so the pointer cannot reach it; touch still works, it is mapped to the panel itself. Single-screen postures never reserve, so the floating tablet keyboard leaves both alone. `YOGA_RESERVE_HIDE_DOCK=0` turns off the dock part.

## Known gaps

The lock screen's keyboard has never been confirmed to take touch right after a resume; modifier keys held on the
physical keyboard when it docks can leave keyd's virtual keyboard with Shift down (`sudo keyd reload`).
