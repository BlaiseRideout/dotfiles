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
    window_count = len(workspace.leaves())

    if workspace.layout == 'splith':
        target = workspace.rect.width / window_count
        dimension = "width"
    elif workspace.layout == 'splitv':
        target = workspace.rect.height / window_count
        dimension = "height"
    else:
        print(f"Don't know how to equalize tiling for layout {workspace.layout}", file=sys.stderr)
        exit(-1)

    target = int(target)

    for leaf in workspace.leaves():
        escaped_name = (leaf.name
                        .replace('[','\\[').replace(']','\\]')
                        .replace('"','\\"'))
        cmd = f'[title="{escaped_name}" pid={leaf.pid}] resize set {dimension} {target}px'
        if args.verbose:
            print("Cmd:", cmd)
        res = i3.command(cmd)[0]
        if not res.success:
            print(f"Failed to set {dimension} for {leaf.name} ({leaf.pid}): {res.error}", file=sys.stderr)

if __name__ == "__main__":
    main()
