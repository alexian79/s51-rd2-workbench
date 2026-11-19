#!/bin/bash
WB=${WB:-$HOME/s51-workbench}
S=${S51_R2_DIR:-$WB/s51-ucsim-rd2}
SIM=$S/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51
CTL=${CTL:-/tmp/s51-ref-b}
IMG=$(dirname "$0")/t0repro.ihx
cd "$S"
run() { # $1 bin, $2 device, $3 label
  echo "##### $3 #####"
  {
    echo "file \"$IMG\""
    echo "break 0x327c"
    echo "go"                       # first handler hit
    echo "delete 1"
    echo "break 0x22cc"             # past the JNB once FL_DISABLED is set
    echo "go"
    echo "info registers"
    echo "dump sfr 0x88 0x8c"
    echo "quit"
  } | timeout 600 "$1" -t "$2" -b -c - 2>&1 |
  grep -E "Loading|Breakpoint [0-9]|Stop at|0x88 |0x89 |0x8a |0x8c |SP 0x|deleted|No such|not found" | head -12
}
run "$SIM" 89C51RD2 "89C51RD2 @ ucsim_51"
run "$SIM" 89C51R   "89C51R @ ucsim_51"
run "$CTL" 89C51RD2 "89C51RD2 @ s51-ref-b (control)"
