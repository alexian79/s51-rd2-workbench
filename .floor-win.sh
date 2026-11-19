#!/bin/bash
# Native floor: all suites vs the MSYS binary; absolute S51_SIM path (cwd varies per suite).
unset S51_REF
export PATH="/p/projects/s51-rd2-workbench/native-support/bin:/usr/bin:/usr/local/bin:$PATH"
export GHIDRA=/p/projects/s51-rd2-workbench/ghidra_12.1.4_PUBLIC
export JAVA_HOME="$(cygpath -w "$(printf '%s\n' /p/projects/s51-rd2-workbench/jdk-*/ | head -1)")"
cd /p/projects/s51-rd2-workbench/s51-workbench-win/s51-ucsim-rd2
sh t/floor.sh /p/projects/s51-rd2-workbench/s51-workbench-win/s51-ucsim-rd2/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51.exe 2>&1 | tee /p/projects/s51-rd2-workbench/floor-win.log | tail -40
echo "FLOOR-EXIT=${PIPESTATUS[0]}"
