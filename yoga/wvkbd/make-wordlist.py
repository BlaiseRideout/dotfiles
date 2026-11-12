#!/usr/bin/env python3
"""Build the autocorrect dictionary for wvkbd-yoga: one word per line, most frequent first.

Source: SymSpell's en-80k frequency dictionary (wolfgarbe/SymSpell): the 80k most frequent
words of Google's web n-grams that are also in a spell-checker word list (SCOWL), so it holds
real words (no typos, no subtitle noise) in frequency order, the same kind of list a phone
keyboard corrects against. Fetched once.

Adjustments:
- contractions (don't, i'm, ...) are put in at a mid rank (the source has a few at low ranks or
  not at all), so the keyboard can offer "don't" for "dont"
- "cant", "wont", "hell", "well" style words that are nearly always a contraction typo: cant and
  wont are dropped so they become can't / won't
- two-letter entries are limited to real words (the source has initialisms like "ab")
- a few technical words the list lacks are appended (never "corrected")

Also writes the word-pair counts the keyboard uses as context (the previous word makes "their" more
likely than "there" in "in their", ...): Peter Norvig's count_2w.txt (Google web text, 286k pairs),
reduced to the pairs of words that are in the dictionary, "a b count" per line.

  make-wordlist.py WORDS BIGRAMS [WORDS_SRC [BIGRAMS_SRC]]     (sources: local copies of en-80k.txt and
                                                               count_2w.txt, else downloaded)
"""
import re
import sys
import urllib.request

URL = "https://raw.githubusercontent.com/wolfgarbe/SymSpell/master/SymSpell.FrequencyDictionary/en-80k.txt"
BIGRAM_URL = "https://norvig.com/ngrams/count_2w.txt"
MAX_BIGRAMS = 200000

# contraction -> the word whose rank it takes
CONTRACTIONS = {
    "don't": "do", "i'm": "i", "can't": "can", "won't": "will", "didn't": "did",
    "doesn't": "does", "isn't": "is", "wasn't": "was", "couldn't": "could",
    "wouldn't": "would", "shouldn't": "should", "i've": "i", "you're": "you",
    "that's": "that", "there's": "there", "aren't": "are", "haven't": "have",
    "hasn't": "has", "weren't": "were", "they're": "they", "what's": "what",
    "here's": "here", "where's": "where", "hadn't": "had", "you've": "you",
    "you'll": "you", "we've": "we", "we're": "we", "we'll": "we", "he's": "he",
    "she's": "she", "it's": "it", "it'll": "it", "that'll": "that", "would've": "would",
    "could've": "could", "should've": "should", "they'll": "they", "they've": "they",
    "who's": "who", "let's": "let", "i'll": "i", "i'd": "i", "he'll": "he", "she'll": "she",
    "he'd": "he", "she'd": "she", "you'd": "you", "we'd": "we", "they'd": "they",
    "mustn't": "must", "ain't": "is", "how's": "how", "why's": "why", "o'clock": "clock",
}
DROP = {"cant", "wont", "dont", "im", "ive", "youre", "thats", "didnt", "doesnt", "isnt", "wasnt",
        "couldnt", "wouldnt", "shouldnt", "arent", "havent", "hasnt", "werent", "theyre"}
TWO_LETTER = set("""of to in is it as at be by he we me my or on do if so up an go no us am ah oh ok hi
ma pa ex id ox ow ye yo uh um""".split())
# words the list lacks that must never be "corrected" (appended at the end)
EXTRA = """sudo git vim nvim grep sed awk wget pacman systemctl journalctl dotfiles config configs
repo repos github gitlab usb hdmi cpu gpu ram ssd json yaml toml api cli gui urls btw imo idk dev
src bin usr tmp env bash zsh kde gnome hyprland wayland nvidia linux ubuntu arch debian golang
npm pip lol omg tbh imo fyi thx pls plz ur cuz lmao lmk ty np tho thru gonna wanna gotta kinda sorta
yeah yep nope hmm haha hahaha wtf asap rn smh brb nvm bc ily gg""".split()


def main():
    out, big_out = sys.argv[1], sys.argv[2]
    if len(sys.argv) > 3:
        text = open(sys.argv[3], encoding="utf-8").read()
    else:
        text = urllib.request.urlopen(URL, timeout=60).read().decode("utf-8")
    words = []
    for line in text.splitlines():
        w = line.split(" ")[0].strip().lower()
        if not re.fullmatch(r"[a-z']+", w) or w in DROP:
            continue
        if len(w) == 1 and w not in ("a", "i"):
            continue
        if len(w) == 2 and w not in TWO_LETTER:
            continue
        if "'" in w and w not in CONTRACTIONS:
            continue
        if w in CONTRACTIONS:
            continue            # re-inserted below at its stem's rank
        words.append(w)
    # contractions: not as frequent as their first word; a realistic middle rank (3x its stem's
    # position + 300) keeps "helo" from becoming "he'll" while "dont" still finds "don't"
    pos = {w: i for i, w in enumerate(words)}
    ins = []
    for c, stem in CONTRACTIONS.items():
        ins.append((min(len(words), 300 + 3 * pos.get(stem, 2000)), c))
    final = list(words)
    for idx, c in sorted(ins, reverse=True):
        final.insert(idx, c)
    final += EXTRA
    seen = set()
    with open(out, "w", encoding="utf-8") as f:
        for w in final:
            if w not in seen:
                seen.add(w)
                f.write(w + "\n")
    print(f"{len(seen)} words -> {out}", file=sys.stderr)

    if len(sys.argv) > 4:
        btext = open(sys.argv[4], encoding="utf-8").read()
    else:
        btext = urllib.request.urlopen(BIGRAM_URL, timeout=120).read().decode("utf-8")
    counts = {}    # (the source has "In their" and "in their" apart)
    for line in btext.splitlines():
        try:
            pair, n = line.rsplit("\t", 1)
            a, b = pair.lower().split(" ")
            n = int(n)
        except ValueError:
            continue
        if a in seen and b in seen:
            counts[(a, b)] = counts.get((a, b), 0) + n
    pairs = sorted(((n, a, b) for (a, b), n in counts.items()), reverse=True)
    with open(big_out, "w", encoding="utf-8") as f:
        for n, a, b in pairs[:MAX_BIGRAMS]:
            f.write(f"{a} {b} {n}\n")
    print(f"{min(len(pairs), MAX_BIGRAMS)} word pairs -> {big_out}", file=sys.stderr)


main()
