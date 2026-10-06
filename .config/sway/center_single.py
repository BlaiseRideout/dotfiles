#!/usr/bin/env python3

"""
Center a lone tiled window on wide outputs: when a workspace has exactly one
tiling window, set horizontal gaps so the window is at most --ratio wide
(width / height). Other workspaces get their horizontal gaps reset to 0.
"""

import argparse

from i3ipc import Connection, Event


def get_parser():
    parser = argparse.ArgumentParser(prog="center_single", description=__doc__)
    parser.add_argument("-r", "--ratio", type=float, default=16 / 9,
                        help="maximum width/height of a lone window (default 16/9)")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="print commands to stdout")
    return parser


def update(i3, ratio, verbose):
    tree = i3.get_tree()
    for output in tree.nodes:
        if output.name == "__i3":
            continue
        for ws in output.nodes:
            if ws.type != "workspace":
                continue
            leaves = ws.leaves()
            if not leaves:
                continue
            gap = 0
            if len(leaves) == 1:
                max_width = ws.rect.height * ratio
                gap = max(0, int((output.rect.width - max_width) / 2))
            # Criteria make "current" refer to the window's workspace, so this
            # works for workspaces that aren't focused.
            cmd = f"[con_id={leaves[0].id}] gaps horizontal current set {gap}"
            if verbose:
                print(f"{ws.name}: {cmd}")
            i3.command(cmd)


def main():
    args = get_parser().parse_args()
    i3 = Connection()

    def handler(i3, _event):
        update(i3, args.ratio, args.verbose)

    for event in (Event.WINDOW_NEW, Event.WINDOW_CLOSE, Event.WINDOW_MOVE,
                  Event.WINDOW_FLOATING, Event.WORKSPACE_INIT,
                  Event.WORKSPACE_MOVE, Event.OUTPUT):
        i3.on(event, handler)

    update(i3, args.ratio, args.verbose)
    i3.main()


if __name__ == "__main__":
    main()
