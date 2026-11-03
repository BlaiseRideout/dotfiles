#!/usr/bin/env python3

import argparse
import sys

from i3ipc import Connection

def get_parser():
    parser = argparse.ArgumentParser(prog="equalize_split", description="Script for equalizing tile size")

    parser.add_argument("-v", "--verbose", action="store_true",
                        help="print verbose messages to stderr")
    return parser


def main():
    args = get_parser().parse_args()

    i3 = Connection()

    workspace = next(w for w in i3.get_tree().workspaces() if any(win.focused for win in w.leaves()))

    if workspace.layout == 'splith':
        dimension, orient = "width", 'splith'
    elif workspace.layout == 'splitv':
        dimension, orient = "height", 'splitv'
    else:
        print(f"Don't know how to equalize tiling for layout {workspace.layout}", file=sys.stderr)
        exit(-1)

    def slots(node):
        """Number of equal slots a node takes along `orient`.

        Single-child wrappers are transparent, and a nested container split
        the same way as the workspace contributes its children's slots (so a
        splith inside a splith counts as its columns). Anything else
        (a splitv column, tabbed, a window) is one slot.
        """
        if len(node.nodes) == 1:
            return slots(node.nodes[0])
        if node.layout == orient and node.nodes:
            return sum(slots(c) for c in node.nodes)
        return 1

    def equalize(node, unit):
        if len(node.nodes) == 1:
            equalize(node.nodes[0], unit)
            return
        if node.layout != orient or not node.nodes:
            return
        for child in node.nodes:
            size = int(unit * slots(child))
            cmd = f'[con_id={child.id}] resize set {dimension} {size}px'
            if args.verbose:
                print("Cmd:", cmd)
            res = i3.command(cmd)[0]
            if not res.success:
                print(f"Failed to set {dimension} for container {child.id}: {res.error}", file=sys.stderr)
        for child in node.nodes:
            equalize(child, unit)

    total = workspace.rect.width if dimension == "width" else workspace.rect.height
    equalize(workspace, total / slots(workspace))

if __name__ == "__main__":
    main()
