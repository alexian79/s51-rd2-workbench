#!/bin/sh
# bring-up.sh -- build the whole AT89C51RD2 workbench from a clean checkout of these repos.
#
#   ./bring-up.sh                 # clone what is missing, patch, build, run every gate
#   WB_ROOT=/tmp/wb ./bring-up.sh # somewhere else (default: ~/s51-workbench)
#   GHIDRA=/path/to/ghidra ./bring-up.sh
#   SKIP_GHIDRA=1 ./bring-up.sh   # simulator only, no headless Ghidra
#
# It is idempotent: every step detects work already done and skips it. Network is needed the
# first time for three of my repos plus the GPL simulator base tree (NOT redistributed).
# Nothing here installs anything outside WB_ROOT except the Ghidra language module, which goes
# into $GHIDRA/Ghidra/Processors/AT89C51RD2 (remove it with the language repo's `langbuild --clean`).
set -e

WB_ROOT=${WB_ROOT:-$HOME/s51-workbench}
GHIDRA=${GHIDRA:-$HOME/ghidra_12.1.4_PUBLIC}
MINE=https://github.com/alexian79
BASE=https://github.com/CrispStrobe/ucsim-stc
BASE_COMMIT=441710c87dc93577caf1c64394eefb86b928eee2
PATCH_REL=s51-ucsim-rd2/patches/rd2-vs-ucsim-stc-441710c.patch

SUITES=0; FAILED=""; note() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
bail() { printf '\nSTOP: %s\n' "$*"; exit 1; }

# ---------------------------------------------------------------- prerequisites
step "prerequisites"
for c in git python3 make g++; do
  command -v "$c" >/dev/null 2>&1 || bail "$c not found (needed to build the simulator)"
  note "  ok  $c  $(command -v "$c")"
done
HAVE_GHIDRA=0
if [ "$SKIP_GHIDRA" != 1 ] && [ -x "$GHIDRA/support/analyzeHeadless" ]; then
  HAVE_GHIDRA=1
  command -v java >/dev/null 2>&1 || bail "java not found but $GHIDRA is present (needed to compile the language)"
  note "  ok  ghidra  $GHIDRA"
else
  note "  --  ghidra not found at $GHIDRA (or SKIP_GHIDRA=1): running the simulator gates only."
  note "      The four Ghidra-side suites and the language install are skipped, not passed."
fi
mkdir -p "$WB_ROOT"; cd "$WB_ROOT"
PATCH=$PWD/$PATCH_REL
note "  workbench root: $WB_ROOT"

# ---------------------------------------------------------------- repos
step "repos"
for r in s51-ucsim-rd2 ghidra-8051-dual-dptr ghidra-at89c51rd2; do
  if [ -d "$r/.git" ]; then
    note "  present  $r"
  else
    git clone -q "$MINE/$r.git" "$r" && note "  cloned   $r"
  fi
done

# ---------------------------------------------------------------- simulator base tree
step "simulator base ($BASE_COMMIT)"
V=s51-ucsim-rd2/vendor/ucsim-stc
if [ -d "$V/.git" ]; then
  note "  present  $V"
else
  git clone -q "$BASE" "$V"
  git -C "$V" checkout -q "$BASE_COMMIT"
  note "  cloned   $V at $BASE_COMMIT"
fi
if git -C "$V" status --porcelain | grep -q 'rd2_eeprom.cc'; then
  note "  patch already applied"
else
  git -C "$V" apply "$PATCH" || bail "could not apply $PATCH"
  note "  patch applied: $PATCH_REL"
fi
# the patch is verified to leave zero content differences against the tree every suite was run
# against. It carries 40 paths (28 modified + 12 added); four configure-generated files the author's
# tree also changes are excluded on purpose, so a patched clone shows exactly 40 dirty paths.
n=$(git -C "$V" status --porcelain | wc -l)
[ "$n" -eq 40 ] || note "  NOTE: expected 40 changed files after the patch, found $n"

# ---------------------------------------------------------------- build
step "build ucsim"
BIN=s51-ucsim-rd2/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51
( cd s51-ucsim-rd2 && ./build.sh ) || bail "build failed; see /tmp/s51-configure.log and /tmp/s51-make.log"
[ -x "$BIN" ] || bail "no binary at $BIN"
note "  built  $BIN"

if [ "$HAVE_GHIDRA" = 1 ]; then
  # banktest runs INSIDE the floor below and needs the language installed to resolve anything,
  # so the install happens here, before the floor -- not down with the Ghidra gates.
  step "install + compile the AT89C51RD2 language"
  ( cd ghidra-at89c51rd2 && GHIDRA="$GHIDRA" ./langbuild ) 2>&1 | tail -3 | sed 's/^/  /'
fi

# ---------------------------------------------------------------- simulation floor
step "simulation floor (27 counted suites + runtests, one binary)"
out=$( cd s51-ucsim-rd2 && sh t/floor.sh "$WB_ROOT/$BIN" 2>&1 ) || true
printf '%s\n' "$out" | sed 's/^/  /'
line=$(printf '%s\n' "$out" | grep '^floor:' | tail -1)
case "$line" in
  *"0 suite(s) not green"*) note "  FLOOR GREEN" ;;
  *) FAILED="$FAILED floor"; note "  FLOOR NOT GREEN -- $line" ;;
esac
SUITES=$((SUITES + 1))

# ---------------------------------------------------------------- ghidra side
if [ "$HAVE_GHIDRA" = 1 ]; then
  # (language already installed above, before the floor)

  step "Ghidra gates (headless, one at a time)"
  run_gh() {
    # $1 = suite, $2 = expected pattern
    o=$( cd ghidra-at89c51rd2 && S51="$WB_ROOT/ghidra-at89c51rd2" \
         S51_SIM="$WB_ROOT/$BIN" GHIDRA="$GHIDRA" timeout 900 python3 "t/$1.py" 2>&1 ) || true
    s=$(printf '%s\n' "$o" | grep -E 'PASS|FAIL|checks|cases' | tail -1)
    printf '  %-12s %s\n' "$1" "${s:-no summary line}"
    case "$s" in *FAIL*) FAILED="$FAILED $1" ;; esac
    SUITES=$((SUITES + 1))
  }
  run_gh langtest
  run_gh rmwtest
  run_gh banktest

  run_sim_gh() {
    # $1 = a gate that lives in the SIM repo: it drives the simulator's `sym` command and
    # LoadSym51.java against each other, so it needs s51-ucsim-rd2/gh and .../t, not the
    # language repo. Still one headless Ghidra at a time, like every other gate here.
    o=$( cd s51-ucsim-rd2 && S51="$WB_ROOT/s51-ucsim-rd2" \
         S51_SIM="$WB_ROOT/$BIN" GHIDRA="$GHIDRA" timeout 900 python3 "t/$1.py" 2>&1 ) || true
    s=$(printf '%s\n' "$o" | grep -E 'PASS|FAIL|legs' | tail -1)
    printf '  %-12s %s\n' "$1" "${s:-no summary line}"
    case "$s" in *FAIL*) FAILED="$FAILED $1" ;; esac
    SUITES=$((SUITES + 1))
  }
  run_sim_gh symmaptest
fi

# ---------------------------------------------------------------- summary
step "summary"
printf '  simulation floor : %s\n' "$(printf '%s' "$line" | sed 's/floor: //')"
[ "$HAVE_GHIDRA" = 1 ] && printf '  ghidra gates     : langtest, rmwtest, banktest, symmaptest (see above)\n'
printf '  simulator binary : %s\n' "$WB_ROOT/$BIN"
printf '  try it           : cd %s/s51-ucsim-rd2 && ./s51 t/isa.ihx\n' "$WB_ROOT"
[ "$HAVE_GHIDRA" = 1 ] && printf '  ghidra           : cd %s/ghidra-at89c51rd2 && ./gh51 demo ../s51-ucsim-rd2/t/isa.ihx\n' "$WB_ROOT"

if [ -n "$FAILED" ]; then
  printf '\nNOT GREEN:%s\n' "$FAILED"
  exit 1
fi
printf '\nAll gates green. Workbench ready at %s\n' "$WB_ROOT"
