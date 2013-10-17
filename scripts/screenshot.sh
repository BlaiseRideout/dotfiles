#!/bin/bash
name=$(date +%F-%H%M%S_scrot.png)
scrot $@ -e 'mv $f ~/Dropbox/images/scrot/'"$name"
sleep 2 && feh -. -- '~/Dropbox/images/scrot/'"$name"
#viewnior "~/Dropbox/images/scrot/$name"
