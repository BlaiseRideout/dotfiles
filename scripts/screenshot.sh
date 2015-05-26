#!/bin/bash
name=$(date +%F-%H%M%S_scrot.png)
scrot $@ -e 'mv $f '"~/images/scrot/$name"
