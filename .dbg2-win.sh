#!/bin/bash
export PATH="/usr/bin:/usr/local/bin:$PATH"
export S51=/p/projects/s51-rd2-workbench/s51-workbench-win/s51-ucsim-rd2
export S51_SIM=$S51/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51.exe
cd "$S51"
timeout 900 python3 t/s51dbgtest.py > /p/projects/s51-rd2-workbench/dbgtest-win2.log 2>&1
echo RC=$?
grep -E "^\S.*BAD" /p/projects/s51-rd2-workbench/dbgtest-win2.log | cut -c1-150
tail -1 /p/projects/s51-rd2-workbench/dbgtest-win2.log
