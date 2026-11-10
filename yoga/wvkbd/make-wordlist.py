#!/usr/bin/env python3
"""Build the autocorrect dictionary for wvkbd-yoga: one word per line, most frequent first.

Source: the 50k English frequency list of hermitdave/FrequencyWords (subtitles), fetched once.
The list splits contractions at the apostrophe and keeps their apostrophe-less typos, so those
are dropped and the real contractions put in at the rank of the typo they replace
(dont -> don't), which makes "dont" autocorrect to "don't".

  make-wordlist.py OUTFILE [SOURCEFILE]     (SOURCEFILE: a local copy of en_50k.txt, else downloaded)
"""
import re
import sys
import urllib.request

URL = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt"

# typo form -> the contraction that replaces it
CONTRACTIONS = {
    "dont": "don't", "im": "i'm", "cant": "can't", "wont": "won't", "didnt": "didn't",
    "doesnt": "doesn't", "isnt": "isn't", "wasnt": "wasn't", "couldnt": "couldn't",
    "wouldnt": "wouldn't", "shouldnt": "shouldn't", "ive": "i've", "youre": "you're",
    "thats": "that's", "theres": "there's", "arent": "aren't", "havent": "haven't",
    "hasnt": "hasn't", "werent": "weren't", "theyre": "they're", "whats": "what's",
    "heres": "here's", "wheres": "where's", "hadnt": "hadn't", "youve": "you've",
    "youll": "you'll", "weve": "we've", "hes": "he's", "shes": "she's", "itll": "it'll",
    "thatll": "that'll", "wouldve": "would've", "couldve": "could've", "shouldve": "should've",
    "theyll": "they'll", "theyve": "they've", "whos": "who's", "ain": "ain't", "mustnt": "mustn't",
    "ill": None,  # a real word too: leave it
}
# fragments left by splitting at the apostrophe (don't -> don + t)
FRAGMENTS = {"don", "didn", "doesn", "isn", "wasn", "couldn", "wouldn", "shouldn", "aren",
             "weren", "hasn", "haven", "hadn", "mustn", "ain", "ll", "ve", "re", "d", "s", "t", "m"}
ONE_LETTER = {"a", "i"}
# words the subtitle list lacks that must never be "corrected" (appended at the end)
EXTRA = """www http https ftp ssh sudo git vim nvim grep sed awk curl wget pacman systemctl
journalctl dotfiles config configs repo repos github gitlab usb wifi bluetooth hdmi cpu gpu
ram ssd html css json yaml toml api cli gui url urls ok okay lol omg btw imo idk dev src bin usr
tmp var etc env bash zsh fish kde gnome hyprland wayland nvidia linux ubuntu arch debian
python javascript rust golang npm pip app apps""".split()


def main():
    out = sys.argv[1]
    if len(sys.argv) > 2:
        text = open(sys.argv[2], encoding="utf-8").read()
    else:
        text = urllib.request.urlopen(URL, timeout=60).read().decode("utf-8")
    words = []
    for line in text.splitlines():
        w = line.split(" ")[0].strip().lower()
        if not re.fullmatch(r"[a-z]+", w):
            continue
        if w in CONTRACTIONS:
            if CONTRACTIONS[w]:
                words.append(CONTRACTIONS[w])
                continue
        elif w in FRAGMENTS:
            continue
        elif len(w) == 1 and w not in ONE_LETTER:
            continue
        words.append(w)
    words += EXTRA
    seen = set()
    with open(out, "w", encoding="utf-8") as f:
        for w in words:
            if w not in seen:
                seen.add(w)
                f.write(w + "\n")
    print(f"{len(seen)} words -> {out}", file=sys.stderr)


main()
