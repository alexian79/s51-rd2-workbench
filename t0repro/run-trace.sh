#!/bin/bash
WB=${WB:-$HOME/s51-workbench}
S=${S51_R2_DIR:-$WB/s51-ucsim-rd2}
SIM=$S/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51
IMG=$(dirname "$0")/t0repro.ihx
cd "$S"
{
  echo "file \"$IMG\""
  for i in $(seq 1 860); do echo "step 1"; done
} | timeout 300 "$SIM" -t 89C51RD2 -b -c - 2>&1 |
awk '
/^Stop at 0x/ { pc=$3; gsub(/:/,"",pc) }
/^SP 0x/ { sp=$2 }
/^0x[0-9a-f]+ .* (MOV|JNB|LJMP|SJMP|PUSH|POP|RETI|INC|CJNE|SETB|ORL|ANL|ACALL|RET|JZ|JNZ) / {
  dis=$0
}
/^F 0x/ { n++; if (n>=775 && n<=860) printf "%d PC=%s SP=%s | %s\n", n, pc, sp, dis }
' | head -90
