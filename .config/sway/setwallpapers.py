#!/usr/bin/env python3

import argparse
import mimetypes
import random
import json
import os
import sys
from datetime import datetime, timedelta
from operator import itemgetter
from functools import partial, cmp_to_key

from i3ipc import Connection, Event, OutputEvent, TickEvent

aspect_ranges = {
    'dualwide':{"min":32./9.},
    'ultrawide':{"min": 17./9., "max": 32./9.},
    'wide':{"min":16./10., "max":16./9.},
    'fullscreen':{"min":1, "max":4./3.},
    'standard':{"min":1, "max":4./3.},
    'tall':{"max":1},
    'vertical':{"max":1},
    'portrait':{"max":1},
}

default_config={
    'default': '/usr/share/backgrounds/sway/Sway_Wallpaper_Blue_1920x1080.png',
}

# min <= aspect < max
def aspect_in_range(aspect, aspect_range):
    if isinstance(aspect_range, dict):
        if 'min' in aspect_range:
            if aspect < aspect_range['min']:
                return False
        if 'max' in aspect_range:
            if aspect >= aspect_range['max']:
                return False
    else:
        raise ValueError(f"Invalid aspect range {aspect_range} of type: {type(aspect_range)}")
    return True

output_cmd_cache = {}
last_update = None

def handle_event(i3, e, verbose, config, interval):
    global last_update
    if verbose and e is not None:
        if isinstance(e, OutputEvent):
            print("output event received:", e.change, e.ipc_data)
        elif isinstance(e, TickEvent):
            print("tick event received:", e.first, e.ipc_data)

    now = datetime.now()
    if interval and last_update and now < last_update + interval:
        return

    update_wall(i3, verbose, config)

    last_update = now

def update_wall(i3, verbose, config):
    global output_cmd_cache
    outputs = i3.get_outputs()

    if verbose:
        print("Outputs:")

    for output in outputs:
        aspect = output.rect.width / output.rect.height
        matching_rows = list(row
                             for name, row in config.items()
                             if aspect_in_range(aspect, row['aspect_range'])
        )
        matching_rows = sorted(matching_rows, key = itemgetter('priority'), reverse = True)
        top_match = matching_rows[0] if len(matching_rows) > 0 else config['default']
        wp = top_match['wp']

        if isinstance(wp, list):
            wps = wp
        elif os.path.isdir(wp):
            wps = [os.path.join(wp, f) for f, mime in
                   ((f, mimetypes.guess_type(f)[0]) for f in os.listdir(wp))
                   if not f.startswith(".") and
                       mime is not None and
                       mime.startswith('image/')]
        else:
            wps = [wp]
        wp = random.choice(wps)
        cmd = f"output '{output.name}' bg '{wp}' fill"
        needs_update = output_cmd_cache.get(output.name) != cmd

        if verbose:
            print(output.name, "(Enabled)" if output.active else "(Disabled)")
            print(f"Rect: {output.rect.width}x{output.rect.height}\tPos: {output.rect.x},{output.rect.y}")
            print(f"Res: {output.current_mode.width}x{output.current_mode.height}\tScale: x{output.scale}")
            print(f"Matching configs: {matching_rows}")
            print(f"Best config: {top_match}")
            if isinstance(wps, list):
                print(f"WPs:", wps)
            if needs_update:
                print(f"Running: {cmd}")
            else:
                print(f"No need to run: {cmd}")
            print()

        if needs_update:
            i3.command(cmd)
            output_cmd_cache[output.name] = cmd

def eval_config(config):
    if isinstance(config, str):
        config = "\n".join(
                    line for line in
                        (line.strip() for line in config.split("\n"))
                    if len(line) != 0 and line[0] != "#"
                )
        config = json.loads(config)
    elif not isinstance(config, dict):
        raise ValueError(f"Config is of unsupported type {type(config)}")

    if 'default' not in config:
        config['default'] = default_config['default']

    out_config = {}
    for name, row in config.items():
        if isinstance(row, dict):
            out_row = row
        elif isinstance(row, str) or isinstance(row, list):
            out_row = {'wp':row}
        else:
            raise TypeError(f"Row {name} is of unsupported type {type(row)}")

        if 'aspect_range' in out_row:
            aspect_range = out_row['aspect_range']
        elif name in aspect_ranges:
            aspect_range = aspect_ranges[name]

        if isinstance(aspect_range, str):
            if aspect_range in aspect_ranges:
                aspect_range = aspect_ranges[aspect_range]

        if 'priority' not in out_row:
            out_row['priority'] = -sys.maxsize-1 if name == 'default' else 0

        out_row['aspect_range'] = aspect_range
        out_row['name'] = name

        out_config[name] = out_row

    return out_config

def get_parser():
    parser = argparse.ArgumentParser(prog="autowallpaper", description="Script for managing wallpapers across multiple monitors")

    parser.add_argument("-v", "--verbose", action="store_true",
                        help="print verbose messages to stderr")
    parser.add_argument("-d", "--daemon", action="store_true",
                        help="run daemon, update wallpapers on output change events")
    parser.add_argument("-c", "--config", type=str,
                        help="wallpaper config file")
    parser.add_argument("-i", "--interval", type=str,
                        help="Auto update interval, fmt '(#h)?(#m)?(#s?)?'. Will enable daemon mode if not already")
    return parser


def main():
    args = get_parser().parse_args()

    interval = None
    if args.interval:
        args.daemon = True

        formats = ["%Hh%Mm%S","%Hh","%Mm","%Hh%Mm","%Hh%S","%Mm%S","%S"]
        args.interval = args.interval.rstrip("s").lower()

        for fmt in formats:
            try:
                interval = datetime.strptime(args.interval, fmt)
            except:
                continue
        if interval is None:
            raise ValueError(f"faled to parse '{args.interval}' as time duration")
        interval = timedelta(hours=interval.hour,minutes=interval.minute,seconds=interval.second)

    if args.config is None:
        config = default_config
    elif os.path.isfile(args.config):
        config = open(args.config,"r").read()
    else:
        config = args.config

    config = eval_config(config)
    if args.verbose:
        print("Config:", config)

    running = True
    while running:
        try:
            i3 = Connection()

            handler = partial(
                handle_event,
                verbose=args.verbose,
                config=config,
                interval=interval,
            )
            handler(i3, None)

            if args.daemon:
                event_types = [Event.OUTPUT]
                if interval is not None:
                    event_types += [Event.TICK]
                for event_type in event_types:
                    try:
                        i3.on(event_type, handler)
                    except KeyError:
                        print(f"'{event_type}' is not a valid event", file=sys.stderr)
                i3.main()
                if args.verbose:
                    print("awaiting events")
                running = False
        except ConnectionRefusedError:
            running = True
            continue

if __name__ == "__main__":
    main()
