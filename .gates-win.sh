#!/bin/bash
# Native Ghidra gates, one at a time (fixed project names collide).
export PATH="/p/projects/s51-rd2-workbench/native-support/bin:/usr/bin:/usr/local/bin:$PATH"
export GHIDRA=/p/projects/s51-rd2-workbench/ghidra_12.1.4_PUBLIC
export JAVA_HOME="$(cygpath -w "$(printf '%s\n' /p/projects/s51-rd2-workbench/jdk-*/ | head -1)")"
SIMDIR=/p/projects/s51-rd2-workbench/s51-workbench-win/s51-ucsim-rd2
LANGDIR=/p/projects/s51-rd2-workbench/s51-workbench-win/ghidra-at89c51rd2
BIN=$SIMDIR/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51.exe
cd "$LANGDIR"
for t in langtest rmwtest banktest; do
  o=$(S51="$LANGDIR" S51_SIM="$BIN" timeout 900 python3 "t/$t.py" 2>&1); rc=$?
  printf '%-12s rc=%s %s\n' "$t" "$rc" "$(printf '%s\n' "$o" | grep -E 'PASS|FAIL' | tail -1 | cut -c1-90)"
done
cd "$SIMDIR"
o=$(S51="$SIMDIR" S51_SIM="$BIN" timeout 900 python3 t/symmaptest.py 2>&1); rc=$?
printf '%-12s rc=%s %s\n' symmaptest "$rc" "$(printf '%s\n' "$o" | grep -E 'PASS|FAIL' | tail -1 | cut -c1-90)"
