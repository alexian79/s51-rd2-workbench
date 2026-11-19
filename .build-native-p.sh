#!/bin/bash
# Native MSYS2: clone repos, apply the rd2 patch, build ucsim_51.exe, build ref-B control.
set -e
# MSYS (Cygwin-runtime) toolchain, NOT mingw64: the suites are POSIX-flavored (/tmp paths,
# rm, getuid) and drive the binary with /usr/bin/python3; only an MSYS-built ucsim_51.exe
# resolves the same /tmp paths the suites write. mingw64 builds pass dpstest but break 26 others.
export PATH="/usr/bin:/usr/local/bin:$PATH"
W=/p/projects/s51-rd2-workbench
T=$W/s51-workbench-win
M=https://github.com/alexian79
mkdir -p "$T"
cd "$T"
for r in s51-ucsim-rd2 ghidra-8051-dual-dptr ghidra-at89c51rd2; do
  [ -d "$r/.git" ] || git clone -q "$M/$r"
done
cd "$T/s51-ucsim-rd2"
if [ ! -d vendor/ucsim-stc/.git ]; then
  mkdir -p vendor
  git clone -q https://github.com/CrispStrobe/ucsim-stc vendor/ucsim-stc
fi
cd vendor/ucsim-stc
# MinGW portability: regs51.h #defines B as 0xf0; winnt.h (via portcl.h -> uccl.h ->
# windows.h) uses B as an identifier. port.cc must parse portcl.h BEFORE regs51.h.
reorder_port_cc() {
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''// local
#include "regs51.h"
#include "types51.h"

#include "portcl.h"'''
new = '''// local: portcl.h first (MinGW: winnt.h uses identifier B, regs51.h #defines B)
#include "portcl.h"

#include "regs51.h"
#include "types51.h"'''
if new not in s:
    assert old in s, "port.cc include anchor miss: " + p
    open(p, "w").write(s.replace(old, new, 1))
    print("port.cc reordered:", p)
PYEOF
}
git checkout -q -f 441710c87dc93577caf1c64394eefb86b928eee2
git clean -qfd
if git apply --reverse --check "$T/s51-ucsim-rd2/patches/rd2-vs-ucsim-stc-441710c.patch" 2>/dev/null; then
  echo PATCH-ALREADY-APPLIED
else
  git apply "$T/s51-ucsim-rd2/patches/rd2-vs-ucsim-stc-441710c.patch"
  echo PATCH-APPLIED
fi
reorder_port_cc "$T/s51-ucsim-rd2/vendor/ucsim-stc/ucsim/src/sims/s51.src/port.cc"
cd "$T/s51-ucsim-rd2"
[ -x vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51.exe ] || sh ./build.sh
ls -l vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51.exe
# --- ref-B control: same base, rd2 patch reverted by fresh clone in refb3-win
D=$W/refb3-win
[ -d "$D/.git" ] || git clone -q "$T/s51-ucsim-rd2/vendor/ucsim-stc" "$D"
cd "$D"
git checkout -q -f 441710c87dc93577caf1c64394eefb86b928eee2
git clean -qfd
git apply "$T/s51-ucsim-rd2/patches/rd2-vs-ucsim-stc-441710c.patch"
reorder_port_cc "$D/ucsim/src/sims/s51.src/port.cc"
cd ucsim/src/sims/s51.src
python3 - <<'EOF'
import re
s = open('uc89c51r.cc').read()
s2 = re.sub(r'(cl_uc89c51r::ckrl_divider\(void\)\s*\{\s*int ckrl;)', r'\1\n  return 1;  // control: pre-CKRL', s, count=1)
assert s2 != s, "ckrl_divider miss"; s = s2
s2 = re.sub(r'(cl_uc89c51rd2::mk_hw_elements\(void\)\s*\{\s*class cl_hw \*h;\s*\n\s*cl_uc89c51r::mk_hw_elements\(\);)', r'\1\n  return;  // control: no RD2 elements', s, count=1)
assert s2 != s, "mk_hw_elements miss"; s = s2
s2 = s.replace('add_hw(h= new cl_rd2_motor(this, 20));\n      h->init();', '// control: motor not registered')
assert s2 != s, "motor miss"; s = s2
open('uc89c51r.cc', 'w').write(s)
print("control surgery ok")
EOF
cd ../../..
[ -x src/sims/s51.src/ucsim_51.exe ] || {
  ./configure --prefix="$W/refb-install-win" > /tmp/refb3-configure.log 2>&1
  make -j8 > /tmp/refb3-make.log 2>&1 || { echo REFB-BUILD-FAILED; grep -E "error:" /tmp/refb3-make.log | head; exit 1; }
}
cp src/sims/s51.src/ucsim_51.exe /tmp/s51-ref-b.exe
cp src/sims/s51.src/ucsim_51.exe /tmp/s51-ref-b
mkdir -p "$W/control"
cp src/sims/s51.src/ucsim_51.exe "$W/control/s51-ref-b-win.exe"
echo CONTROL-INSTALLED
echo NATIVE-BUILDS-DONE
