#!/bin/bash
# Pre-fetch everything the official bring-up.sh needs (idempotent; it will skip what exists).
set -e
WB=/mnt/p/projects/s51-rd2-workbench/s51-workbench
mkdir -p "$WB"
cd "$WB"
M=https://github.com/alexian79
for r in s51-ucsim-rd2 ghidra-8051-dual-dptr ghidra-at89c51rd2; do
  [ -d "$r/.git" ] || git clone -q "$M/$r"
done
cd s51-ucsim-rd2
if [ ! -d vendor/ucsim-stc/.git ]; then
  mkdir -p vendor
  git clone -q https://github.com/CrispStrobe/ucsim-stc vendor/ucsim-stc
fi
cd vendor/ucsim-stc
git checkout -q 441710c87dc93577caf1c64394eefb86b928eee2
echo PRE-FETCH-DONE
