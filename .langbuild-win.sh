#!/bin/bash
# Native langbuild: compile + install the AT89C51RD2 language into the local Ghidra.
export PATH="/p/projects/s51-rd2-workbench/native-support/bin:/usr/bin:/usr/local/bin:$PATH"
export GHIDRA=/p/projects/s51-rd2-workbench/ghidra_12.1.4_PUBLIC
export JAVA_HOME="$(cygpath -w "$(printf '%s\n' /p/projects/s51-rd2-workbench/jdk-*/ | head -1)")"
cd /p/projects/s51-rd2-workbench/s51-workbench-win/ghidra-at89c51rd2
./langbuild 2>&1 | tail -4
