#!/bin/bash
# Native toolchain downloads into the workbench folder (persistent).
set -e
W=/p/projects/s51-rd2-workbench
cd "$W"
[ -f jdk21.zip ] || curl -fSL --retry 3 -o jdk21.zip \
  "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
[ -f ghidra.zip ] || curl -fSL --retry 3 -o ghidra.zip \
  "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip"
echo DOWNLOADS-OK
ls -l jdk21.zip ghidra.zip
