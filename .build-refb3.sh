#!/bin/bash
# WSL control v3: rd2 patch applied, then RD2 behavior surgically removed
# (elements unregistered, CKRL prescaler off, motor dropped). Output: /tmp/s51-ref-b
set -e
R=/mnt/p/projects/s51-rd2-workbench/s51-workbench/s51-ucsim-rd2
D=/tmp/refb3-src
[ -d "$D/.git" ] || git clone -q "$R/vendor/ucsim-stc" "$D"
cd "$D"
git checkout -q -f 441710c87dc93577caf1c64394eefb86b928eee2
git clean -qfd
git apply "$R/patches/rd2-vs-ucsim-stc-441710c.patch"
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
./configure --prefix=/tmp/refb3-install > /tmp/refb3-configure.log 2>&1
make -j8 > /tmp/refb3-make.log 2>&1 || { echo BUILD-FAILED; grep -E 'error:' /tmp/refb3-make.log | head; exit 1; }
cp src/sims/s51.src/ucsim_51 /tmp/s51-ref-b
echo REFB3-BUILT
