#!/usr/bin/env python3
"""Apply managed Zoom settings during Home Manager activation, preserving others."""
import os
from pathlib import Path
import re


def configure(text):
    settings = {"xwayland": "false", "enableWaylandShare": "true"}
    section = re.search(r"(?m)^\[General\]\s*\n", text)
    if section is None:
        return "[General]\n" + "".join(f"{k}={v}\n" for k, v in settings.items()) + text
    start = section.end()
    next_section = re.search(r"(?m)^\[", text[start:])
    end = start + next_section.start() if next_section else len(text)
    general = text[start:end]
    for key, value in settings.items():
        pattern = rf"(?m)^{key}=.*$"
        if re.search(pattern, general):
            general = re.sub(pattern, f"{key}={value}", general)
        else:
            if general and not general.endswith("\n"):
                general += "\n"
            general += f"{key}={value}\n"
    return text[:start] + general + text[end:]


if __name__ == "__main__":
    path = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "zoomus.conf"
    before = path.read_text() if path.exists() else ""
    after = configure(before)
    if after != before:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(after)
