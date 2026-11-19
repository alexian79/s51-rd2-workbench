# Windows bring-up: two verified routes

This folder holds a complete, gate-verified reproduction of the [s51-rd2-workbench](README.md)
on Windows — one route per side of the WSL boundary:

| route | tree | floor | Ghidra gates |
|---|---|---|---|
| **A. WSL Ubuntu** (official `bring-up.sh`, zero edits) | `s51-workbench/` | **28/28 green** (s51dbgtest 68/68) | langtest 18/18, rmwtest 10/10, banktest 3/3, symmaptest 11/11 |
| **B. Native MSYS2** (no WSL anywhere in the toolchain) | `s51-workbench-win/` | 27/28 — see *pty ceiling* (s51dbgtest 67/68) | langtest 18/18, rmwtest 10/10, banktest 3/3, symmaptest 11/11 |

The WSL route reproduces the runbook release exactly:

```
All gates green. Workbench ready at /mnt/p/projects/s51-rd2-workbench/s51-workbench
```

Native route results are in `floor-win.log` (floor) and reproduced by `.floor-win.sh` /
`.gates-win.sh`.

> **Why this folder is on P:** the first reproduction lived on **R:, which is a RAM drive —
> a reboot wiped the whole tree** (repos, builds, Ghidra, JDK, control binaries, logs). Keep
> this folder on persistent storage. WSL's ext4 home survived; if you only need Route A, the
> only things to restore after a wipe are `WB_ROOT` (rerun `bring-up.sh`, it rebuilds
> everything) and `control/s51-ref-b-wsl` (see *Control binary*).

## Folder layout

```
s51-workbench/          WSL WB_ROOT — repos + built ucsim_51 (Linux ELF), official green run
s51-workbench-win/      native WB_ROOT — repos + ucsim_51.exe (PE) via the same patch
ghidra_12.1.4_PUBLIC/   Ghidra for the native route (support/analyzeHeadless = MSYS bridge,
                        stock script kept as analyzeHeadless.linux-original)
jdk-21.0.13+9/          Temurin JDK 21 for the native route
native-support/bin/     java/javac shims + winpath.sh (POSIX<->Windows path translation)
control/                ref-B control binaries (see "Control binary" below)
.floor-win.sh           reruns the native 28-suite floor
.gates-win.sh           reruns the native Ghidra gates, one at a time
.dbg2-win.sh            reruns only s51dbgtest and prints the failing rows
.build-native-p.sh      native clones + rd2 patch + ucsim_51.exe + native ref-B control
.patch-s51dbg-p.sh      applies the two Windows fixes to s51-workbench-win's tools/s51dbg.py
.setup-tools-p.sh       extract JDK/Ghidra zips + install the analyzeHeadless bridge
.prefetch-p.sh .dl-win.sh   WSL clones / native downloads (bootstrap for a fresh machine)
build_refb.sh-style recipe lives in .build-native-p.sh's refb section + notes below
bring-up.log            the WSL green run, verbatim
```

## Route A — WSL Ubuntu (recommended, zero source edits)

Proven on Ubuntu 24.04 (Python 3.12.3), WSL2. P: mounts at `/mnt/p` automatically.

```sh
# in WSL, as root (or with sudo)
apt-get install -y build-essential openjdk-21-jdk-headless unzip
curl -fSL -o /root/ghidra.zip \
  https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip
(cd /root && unzip -q ghidra.zip)          # -> /root/ghidra_12.1.4_PUBLIC = script default $GHIDRA

# control binary BEFORE the run (ident89c51r + rd2identity need /tmp/s51-ref-b):
cp /mnt/p/projects/s51-rd2-workbench/control/s51-ref-b-wsl /tmp/s51-ref-b

WB_ROOT=/mnt/p/projects/s51-rd2-workbench/s51-workbench \
GHIDRA=/root/ghidra_12.1.4_PUBLIC \
sh /mnt/p/projects/s51-rd2-workbench/bring-up.sh
```

Ends with `All gates green.` (`floor: 0 suite(s) not green`). Clones/patch/build are
idempotent. `NOTE: expected 40 changed files after the patch, found 44` is informational —
the patch was already applied in this tree.

## Route B — native MSYS2 (no WSL)

Proven on: Git 2.49, MSYS2 with the **MSYS (Cygwin-runtime) toolchain and interpreter**
(`g++ 15.2`, `python 3.12` — not mingw64, see fix 9), Temurin JDK 21.0.13, Ghidra 12.1.4 —
the last two unzipped into this folder.

```sh
# from "MSYS2 MSYS" shell (C:\tools\msys64\usr\bin\bash.exe)
bash /p/projects/s51-rd2-workbench/.build-native-p.sh   # clones + patches + builds exe + ref-B
bash /p/projects/s51-rd2-workbench/.patch-s51dbg-p.sh   # the two Windows fixes (below)
bash /p/projects/s51-rd2-workbench/.floor-win.sh
bash /p/projects/s51-rd2-workbench/.gates-win.sh
```

or by hand:

```sh
export PATH="/p/projects/s51-rd2-workbench/native-support/bin:/usr/bin:/usr/local/bin:$PATH"
export GHIDRA=/p/projects/s51-rd2-workbench/ghidra_12.1.4_PUBLIC
export JAVA_HOME="$(cygpath -w /p/projects/s51-rd2-workbench/jdk-21.0.13+9)"  # JVM wants a Windows path
cd /p/projects/s51-rd2-workbench/s51-workbench-win/s51-ucsim-rd2
sh t/floor.sh "$PWD/vendor/ucsim-stc/ucsim/src/sims/s51.src/ucsim_51.exe"     # absolute SIM!
```

### What Windows forced, and where the fixes live

1. **ANSI colors on the JSON console (root cause of all `s51dbgtest` flakiness).**
   `fwio.cc` — the *win32* I/O variant — hardcodes `tty = true` for the `-Z` console socket
   ("assuming TTY on socket"), and `prepare_terminal()` even emits malformed telnet IAC
   (`write(s, 7)` — wrong arity). Linux keeps `tty=false` there, so only the Windows build
   paints the scripted console: `\x1b[0m118\n\x1b[33m3> ` instead of `118\n3> `, and the
   driver's per-read strip desynchronizes when sequences split across 1-byte socket writes.
   Fix: `tools/s51dbg.py` spawns with **`-b`** (ucsim's own `black_and_white` flag) at every
   programmatic console — a no-op on Linux, the cure on Windows. 61/68 -> 67/68.
   (`fwio.cc` itself is left untouched; `-b` is the sanctioned switch.)
2. **Nagle stalls.** The console writes one byte at a time; with default Nagle + Windows
   delayed-ACK every round trip costs ~40 ms and the driver's 4 s windows start expiring.
   Fix: `TCP_NODELAY` on the driver socket (`tools/s51dbg.py`, after `create_connection`).
   Both fixes are applied idempotently by `.patch-s51dbg-p.sh`.
3. **`analyzeHeadless` rejects `MSYS_NT`** and would build a `:`-separated classpath for a
   Windows JVM. Fix: `support/analyzeHeadless` in the local Ghidra is a bash bridge that
   `exec cmd //c analyzeHeadless.bat` with `cygpath`-translated args (original kept as
   `analyzeHeadless.linux-original`).
4. **Java on PATH**: `native-support/bin/java` (+`javac`) shims convert `-cp` POSIX lists and
   path arguments to Windows form, so `langbuild` and `gh51` run against the stock Windows JDK.
5. **`timeout`**: exists in MSYS2 (`/usr/bin/timeout`); do NOT run the suites from Git-Bash,
   where `timeout.exe` is the interactive one, and remember `export A=x B=$A` expands before
   assignment (set them in separate `export`s).
6. **Quoting through `wsl`/`cmd` hops mangles inline scripts** — run everything as script files
   (this folder's dot-scripts exist for exactly that reason).
7. **`B` macro vs `winnt.h` (native build blocker).** `regs51.h` `#define B 0xf0` (the 8051
   secondary accumulator); `port.cc` included `regs51.h` *before* `portcl.h`, whose transitive
   chain pulls `<windows.h>` -> `winnt.h`, and winnt.h uses `B` as an identifier -> hard syntax
   error, MinGW only (no `windows.h` on Linux). Fix: `port.cc` parses `portcl.h` first; applied
   idempotently by `.build-native-p.sh` (`reorder_port_cc`, both trees). Every other `s51.src`
   TU already parsed the Windows chain first, which is why only `port.o` failed.
8. **`ps` hygiene audit**: msys `ps` has no BSD `-eo pid,ppid,args=`; floor.sh's leak-audit line
   is inert (never counted; suite verdicts unaffected). Cosmetic `ps: unknown option -- o` only.
9. **One runtime, three contracts.** MSYS2 ships two interpreters and two toolchains. The
   suites are POSIX-flavored (`os.getuid`, `/tmp/...` path strings, `rm`, `pty.openpty`) and
   hand the simulator the SAME `/tmp` paths they write themselves — so the whole native stack
   must be the Cygwin-runtime one: build `ucsim_51.exe` with `/usr/bin/g++` (MSYS) and run
   every suite with `/usr/bin/python3`. A MinGW binary passes `dpstest` but can't open the
   MSYS-`/tmp` hexes the suites hand it (26 red at once), and a MinGW interpreter lacks
   `getuid`/`openpty` (9 red). All-MSYS is the aligned contract; every runner here keeps
   `/usr/bin` ahead. When switching toolchains, `git clean -xfd` (not `-fd`) first — ignored
   `.o`/exe files silently survive `-fd` and get relinked across toolchains.

### pty ceiling (the one red leg)

`s51dbgtest` leg **14a** drives ucsim's *stdio* console on a real pty (`pty.openpty`) and
reads the load report off the master side. Under MSYS2 the leg reads zero bytes — with either
interpreter and either toolchain build — while every other leg, including the whole `-Z`
socket console, is byte-clean. 67/68 is the native ceiling (observed identically pre- and
post-rebuild); the WSL route covers that surface at 68/68. The floor therefore prints one
FAIL row (`s51dbgtest`) on native with everything else green — treat it as the documented
Windows platform limit, not a behavior difference.

## Control binary (ref-B)

`ident89c51r` + `rd2identity` compare transcripts against a ucsim-stc build *without* the rd2
behavior, at the default path `/tmp/s51-ref-b(.exe)`. The control is the rd2-patched tree with
three surgeries: `ckrl_divider` forced to `return 1`, `cl_uc89c51rd2::mk_hw_elements` returns
early (no RD2 elements registered), motor `add_hw` removed. Persisted here:

- `control/s51-ref-b-wsl` (Linux ELF) — `cp control/s51-ref-b-wsl /tmp/s51-ref-b` (WSL)
- `control/s51-ref-b-win.exe` (PE) — copy into `C:\tools\msys64\tmp\` as **both** `s51-ref-b`
  and `s51-ref-b.exe` (some suites strip the extension; a suite's temp cleanup has wiped it once)

Rebuild recipes: the refb section of `.build-native-p.sh` (MSYS) and `.build-refb3.sh` (WSL);
base tree `ucsim-stc@441710c` + the repo's rd2 patch + the three surgeries above.

## Try it

```sh
# WSL
cd /mnt/p/projects/s51-rd2-workbench/s51-workbench/s51-ucsim-rd2 && ./s51 t/isa.ihx
# native (cmd or MSYS2)
s51-workbench-win\s51-ucsim-rd2\vendor\ucsim-stc\ucsim\src\sims\s51.src\ucsim_51.exe t\isa.ihx
```
