#!/bin/bash
WB=${WB:-$HOME/s51-workbench}
S=${S51_R2_DIR:-$WB/s51-ucsim-rd2}
SIM=$S/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51
D=$(dirname "$0")
cd "$S"
{
  echo "file \"$D/t0v2a.ihx\""
  echo "break 0x327c"
  echo "go"
  echo "quit"
} | timeout 60 "$SIM" -t 89C51RD2 -b -c - 2>&1 |
  grep -E "Loading|Stop at|Simulated|Breakpoint" | head -8
echo "--- step mode ---"
{
  echo "file \"$D/t0v2a.ihx\""
  echo "break 0x327c"
  echo "step 100000"
  echo "dump sfr 0x88 0x8d"
  echo "step 100000"
  echo "dump sfr 0x88 0x8d"
  echo "step 100000"
  echo "dump sfr 0x88 0x8d"
  echo "quit"
} | timeout 300 "$SIM" -t 89C51RD2 -b -c - 2>&1 |
  grep -E "Loading|Stop at|Simulated|0x88 |0x8a |0x8c " | head -16
