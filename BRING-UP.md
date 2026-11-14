# AT89C51RD2 workbench — agent bring-up runbook

The executable checklist for getting the whole AT89C51RD2 / AT89C51ED2 toolchain up and proving it
works. Prose, rationale and datasheet citations live in [`README.md`](README.md); this file is the
form an agent can follow without reading that first.

Fetch it raw:

    curl -fsSL https://raw.githubusercontent.com/alexian79/s51-rd2-workbench/main/BRING-UP.md

Three repositories, two licences:

| repo | licence | what it is |
|---|---|---|
| [`s51-ucsim-rd2`](https://github.com/alexian79/s51-ucsim-rd2) | GPL-2.0-or-later | ucsim device-model + peripheral build-out as a patch against upstream, verification bed of 26 counted suites plus `runtests` (reported, never counted), analysis notes |
| [`ghidra-at89c51rd2`](https://github.com/alexian79/ghidra-at89c51rd2) | Apache-2.0 | Ghidra processor module: dual DPTR in Sleigh context, 1792 B on-chip XRAM, doc4235 SFR map, `gh51` headless front end |
| [`ghidra-8051-dual-dptr`](https://github.com/alexian79/ghidra-8051-dual-dptr) | Apache-2.0 | the same bank model as a gated patch to Ghidra's shared `8051_main.sinc`, plus proof it is inert for languages that do not opt in |

## 1. Bring it up

```sh
curl -fsSL https://raw.githubusercontent.com/alexian79/s51-rd2-workbench/main/bring-up.sh -o bring-up.sh
sh bring-up.sh
```

Idempotent: a rerun skips everything already done. Needs `git`, `python3`, `make`, `g++`;
`java` + Ghidra 12.x are optional. About four minutes from nothing on a warm cache.

| knob | meaning |
|---|---|
| `WB_ROOT=/tmp/wb` | where the workbench lives (default `~/s51-workbench`) |
| `GHIDRA=/path/to/ghidra_12.1.4_PUBLIC` | Ghidra install to build the language into |
| `SKIP_GHIDRA=1` | simulator only — those gates are reported *skipped*, never silently passed |

**Trust the exit status, not the narrative in the middle of the log.**

| outcome | signal |
|---|---|
| success | `exit 0` and last line `All gates green. Workbench ready at <root>` |
| failure | `exit 1` and `NOT GREEN: <space-separated gates>` |

## 2. The lines that mean success

Grep for these exact strings; anything else is not a pass.

| gate | required output |
|---|---|
| `t/floor.sh` (26 counted suites plus `runtests` — reported, never counted — one binary) | `floor: 0 suite(s) not green` |
| `langtest` | `PASS: 18/18 checks` |
| `rmwtest` | `PASS: 10/10 cases agree with the simulator` |
| `banktest` | `PASS: 3/3` |
| `symmaptest` | `symmaptest: PASS 11/11 legs` |

Representative floor legs when green: `rd2registers PASS: 288/288`, `irctest PASS: 50/50`,
`t2cnttest: PASS 30/30 legs`, `ident89c51r PASS: 36/36 transcripts byte-identical` (a guard against
collateral damage: it compares the shared `-t 89C51R` transcript surface against `$S51_REF`, so
agreeing with an unpatched build is the correct answer rather than a vacuous one),
`rd2identity PASS: 38/38`, `x2test PASS: 15/15`, `eepromtest PASS: 29/29`,
`bpcmdtest: PASS 25/25 legs`, `wptrtest: PASS 27/27 legs`, `symtest: PASS 14/14 legs`,
`maptest: PASS 10/10 legs` (a `.map` linked by sdcc 4.6.0, wide and narrow layouts, bound
through the same area rule as the `.sym`),
`s51dbgtest: PASS: 68/68 checks` (the last two run against whichever binary the floor was given).

Two lines that look like failures and are not:

- `runtests  11/20 baselines match` — the upstream baseline is 11/20 and that suite exits non-zero by
  design. It is **reported, never counted**; "1 not green" has never meant this suite.
- `eepromtest` printing 29 instead of 30 — the 30th leg compares against a control binary supplied
  through `S51_REF`. Absent that variable, 29 is correct.

## 3. Ordering rules that bite

- The language must be **installed before the simulation floor**: `banktest` runs *inside* the floor
  and resolves SFR names through the installed module. A machine that fails `banktest` first thing
  usually just has no module installed yet.
- Run `langtest`, `rmwtest`, `banktest` and `symmaptest` **one at a time**: each starts a headless
  Ghidra with fixed project names and they collide.
- Syntax-check these scripts with `bash -n`. `sh -n` fails falsely because `gh51` uses arrays.
- The simulator patch expects the vendor tree at commit `441710c` and **38** changed files, counted
  immediately after the apply. The same tree shows **42** once `build.sh` has run, because
  `configure` rewrites the four generated files the patch deliberately excludes — that is the
  intended consequence of shipping them out, not drift. A number other than 38 at apply time means
  the base tree or the patch, never a code bug.

## 4. Simulator console traps

| trap | truth |
|---|---|
| `code` space | it is called **`rom`**, not `code` |
| `info hw` | needs a *category*: `info hw port`, `info hw eeprom` |
| `get sfr` | can report stale values — use `dump sfr 0x80 0xff` |
| read-clear SFRs | reading one through the console **consumes the clear** |
| `file` command | path must be quoted: `file "t/isa.ihx"` |
| `step N` | N steps, not one: from reset on `t/isa.ihx`, `step 1` lands PC at `0x000030`, `step 2` at `0x000033`, `step 3` at `0x000035`, `step 5` at `0x00003a` |
| suites fail oddly | they read `S51` (repo root) and `S51_SIM` (binary); `S51_ROOT` relocates the tree |

```sh
cd "$WB_ROOT/s51-ucsim-rd2"
./s51 t/isa.ihx                       # == ucsim_51 -t 89C51R <image>
./s51 -X 11.0592M firmware.hex        # real crystal, so baud and timers are honest
echo 'file "t/isa.ihx"; b 0x12; go; info reg; dump sfr 0x80 0xff' | ./s51 -c -
```

## 5. Showing what the Ghidra module buys

Same bytes, two languages — the delta is the argument:

```sh
cd "$WB_ROOT/ghidra-at89c51rd2"
./gh51 demo ../s51-ucsim-rd2/t/isa.ihx
S51LANG=8051:BE:16:default ./gh51 demo ../s51-ucsim-rd2/t/isa.ihx
```

If Ghidra says `Unsupported language: AT89C51RD2:BE:16:default`, it dropped the module silently for
a missing `Module.manifest`, missing `lib/`, or an out-of-schema `.ldefs`. Rerun `./langbuild`; the
real reason is one `ERROR` line in `~/.config/ghidra/<version>/application.log`.

## 6. Do not overclaim

- Nothing here is submitted upstream. The Ghidra change would still need an issue plus a
  `certification.manifest`; the ucsim changes need rebasing onto 0.9.x, not a plain `git apply`.
- **Open, deliberately unmodelled:** `timer0.cc` samples T0/T1 counter inputs on a *rising* edge
  while timer 2, the PCA and the external interrupts use *falling*. Suites pass either way; it needs
  the hardware manual's counter-edge statement before picking a side.
- **Coverage limit:** the STC12 port path shares `port.cc` with the double-notify fix and no suite
  in this bed covers it.
- `xcompare.py` cross-checks against an independent Rust `i8051` core (pc 104/104, cycles 104/104);
  you clone `vendor/mcs51-rs` yourself, so it is not part of the green floor.
- The Atmel datasheets (`doc4235`, `doc4316`) are Microchip copyright and are **not** redistributed;
  citations give a section and a printed page number instead.

## 7. Debugging firmware: what actually works in this build

The simulator is a debugger, not only a loader. Every line below was run against this build; the
traps that make a command silently do nothing are called out after the table.

Keep the console alive. `run` deliberately freezes its own console (ENTER stops the simulation), so
a heredoc that closes stdin can end the process before the breakpoint is ever reached:

```sh
( printf 'file "fw.ihx"\nbreak 0x3a\nrun\n'; sleep 5 ) | ./ucsim_51 -t 89C51R -q -c -
```

Or drive a session that outlives the client — `./ucsim_51 -t 89C51R -Z 3445`, then
`nc 127.0.0.1 3445` and type (`2>` prompt). No respawn per probe, no lost state.

| want | command | verified behaviour |
|---|---|---|
| stop at an instruction | `break 0x3a` | banner: `Stop at 0x00003a: (104) Breakpoint` + registers + the instruction |
| stop on the Nth hit | `break 0x3a hit 2` | honoured here (`Hit 2`, stops on the second crossing); upstream 0.8.15 accepts the keyword and silently keeps `Hit 1`. Positional `break 0x3a 2` works on both |
| stop on a RAM/SFR access | `break iram w 0x30` | `w`/`r`, also `sfr w 0x8e`; reports `(112) Event break` at the instruction **after** the write |
| stop on a condition | `break 0x3a if ACC==0x5a` | one token, or quoted for spaces and brackets — see below |
| step | `step`, `step 20`, `next` | units are `s ms us ns vclk fclk rclk wclk`; `cycle` is not one (`Unknown unit.`) |
| print on every stop | `display /X iram[0x41]` | `1:/X iram[0x41] = 0xa5` |
| act on a stop | `commands 1 "echo hit\n"` | runs at each accepted hit |
| what led here | `history list` | disassembled ring of the last executions (`history info` → `len: 10000`) |
| evaluate | `expression /X sfr[0x8e]`, `expression AUXR` | **brackets, never colons**: `iram[0x41]`, `sfr[0x8e]`, `rom[0]`, or an SFR name |
| time a region | `timer start 1` → `step 20` → `timer get 1` | `timer #1("time") ON 0.000030381944444 sec (336 clks)` on `t/isa.ihx` at the default 11.0592 MHz — seconds first, clocks parenthesised; timer 1 (`"time"`) already exists out of the start, so `timer add 1` only answers `Error: Timer 1 already exists` |
| inspect | `dump sfr 0x80 0xff`, `di`, `dx`, `info registers`, `memory cell iram 0x40` | code space is **`rom`**; `get sfr` lies |

The colon form is the trap to burn in: `expression dseg:0x30` prints `Parser error: syntax error`
**and then `0`**, so a condition written that way is not an error, it is a permanently false test.

### Reading a stop

The stop banner's **status code** is the discriminator, and it has to be counted at the address you
care about:

| code | meaning |
|---|---|
| `(104) Breakpoint` | a breakpoint fired |
| `(109) stepped N ticks` | a `step` merely landed on that address |
| `(112) Event break` | a watchpoint fired; reported at the instruction *after* the access |

`Stop at 0x00003a:` is printed in all three cases, so counting that string proves nothing. Likewise
`info break`'s `Cond` column reads `false` on every conditional row, whether or not the condition
held: the condition text appears only in the trailing `cond="…"`, and it is never what decides a
stop.

Scripted sessions also need a **sentinel** — a second, unconditional breakpoint past the point of
interest (`break 0x44`). Without it a session whose tested breakpoint never fires simulates forever,
and a simulator killed at a timeout loses its buffered output, which looks exactly like "the
breakpoint was never created". With one, `stops == [target]` says it fired and
`stops == [sentinel]` proves the code ran to the end without firing.

### Proving a program is actually loaded

`file` reports the load on the **stdio console, and only without `-q`**. `ucsim_51 -q -t 89C51R
-c -` answers with the echo and the prompt and nothing else, which is very easy to mistake for "the
console never reports a load". Drop `-q` and both halves appear — and they cross a pipe perfectly
well:

```text
Loading from t/isa.ihx
233 words read from t/isa.ihx
```

Exactly two things silence it, and each has manufactured a false "nothing reports the load"
finding: `-q`, and aiming the command at a console that is not reading your stdin. Nothing else
does — measured on one binary, the report is there with stdin as a pty *or* a pipe, and with `-c -`
*or* without it (`-c -` nominally adds the stdio console; the stdio console was reading stdin
already, so on this binary it selects nothing). A capture holding only the banner means the `file`
command never arrived, and the byte count is a red herring in either direction: both report lines
echo the path you typed, so the same 233-word load measured **305 bytes** as
`file "t/isa.ihx"` and **359 bytes** as an absolute path, and the capture also carries a varying
`Wall time:` line. Assert the two lines, never a total. The telnet console opened by `-Z` is the
one that echoes `file` and stays silent about the load on every build — that is the real second
silencer, and it is why the driver proves a load by ROM readback.

Readback is still the stronger check, because a word count proves a file was parsed, not that bytes
landed where you think: `dump rom 0 0x07` after that load gives `02 00 30 32 ff ff ff ff`. Never use
"ROM is non-zero" as the test — an image with nothing loaded reads `ff ff ff ff ff ff ff ff`, not
`00`, so it passes for any program. Byte-exact proof is available whenever you want it: `t/isa.ihx`
is an ordinary Intel HEX file (fifteen type-`00` records, one type-`01`, every length and checksum
valid), so parse it and compare against `dump rom`. The record type is at byte offset **7**, not
right after the `:` — that field is the byte count, and reading it as a type makes a clean file look
like it uses exotic record codes.

### Waveforms instead of printfs

`conf` lists a `vcd` element, off by default. Bind signals by address and dump — port writes are
included, with real timestamps:

```text
set hw vcd file "/tmp/p1.vcd"
set hw vcd add sfr 0x90          # auto-named P1;  add bits[0x90]  for a single bit
set hw vcd start
step 30
set hw vcd stop
```

The file opens in Surfer/GTKWave (`b11111111 → b01010101 → b10101010` on `P1`, one `#<ps>` line per
event). A counter edge that fires twice is visible in one screen, which is exactly the class of bug
the one-count-per-edge suite exists to catch.

If you parse the file rather than eyeballing it: in a split `$scope` line the scope name is index
**2** (`$scope module ucsim_vcd_0 $end`); index 3 is `$end`, so an off-by-one names every signal
`$end/P1`. Signals therefore read back as `ucsim_vcd_0/P1`, and `$var wire 8 ! P1 $end` is the
id-to-name map.

### gdbserver

`-d <portnum>` is in `--help` here; upstream 0.8.15 assigns `rgdb_port` in `app.cc` but leaves its
usage line commented out, so the option is invisible there. Either way
`./ucsim_51 -t 89C51R -d 3333` answers the GDB remote protocol: `qSupported` replies with
`PacketSize=7fff;QStartNoAckMode+;qXfer:features:read+`, and `qXfer:features:read:target.xml`
serves a `gdb-target.dtd` target description. A front end that speaks RSP can therefore drive
the core.

### Stepping onto a breakpoint

Upstream tests a fetch breakpoint only under `steps_done > 0` (`cl_uc::do_brk`), and that counter
resets at every stop — so the first instruction fetched after *every* stop is exempt. The result is
that `step` can never reach an armed address (12 single steps across one give zero `(104)`) and,
worse, once a `step` has landed on that address, a following `run` sails straight past the
breakpoint sitting there. This build exempts only the fetch of the address the breakpoint itself
stopped us on — the one fetch that genuinely would re-trigger at once — so `step` arrives at it and
`run` stops in the right place. `step 30` fired it mid-flight on both kinds of build; `step 2` still
depends on parity relative to the last stop. `t/wptrtest.py` legs WP-K13/K14/K15 pin all of it, and
classify which rule the binary under test implements.

### The silent-noop forms

- **Conditions work, in one spelling only.** `break 0x3a if ACC==0x5a` is honoured: at `0x3a`, just
  after the program executes `MOV A,#0x5a`, it stops — while `if ACC==0x5b`, `if ACC!=0x5a` and
  `if AUXR==0x09` do not stop and `if AUXR==0x08` does. The console splits on spaces, so the
  condition must be **a single token**, or quoted: `break 0x3a if "ACC == 0x5a"` stops,
  `if "ACC == 0x00"` does not.
- **A bracket expression has to be quoted, and then it works.** `break 0x3a if iram[0x40]==0x5a`
  is refused outright — the console splits on spaces, the condition arrives as several words, and
  nothing is created. Quoted, it is evaluated correctly: `if "iram[0x40]==0x5a"` stops there,
  `if "iram[0x40]==0x5b"` runs on to the sentinel. A named cell reads better and is what
  `t/bpcmdtest.py` pins: `var z iram[0x40]`, then `break 0x3a if z==0x5a`.
- **A condition that is not a string is refused, never ignored.** `if 0`, `if 1` and a misspelled
  keyword (`iff ACC==0x5a`) used to build an **unconditional** breakpoint: the grammar branch
  matched, the condition came out as the empty string, and the breakpoint then stopped at
  everything. This build refuses each of them, creates nothing, and says why (`A condition has to
  be a word or a quoted string`). On unpatched 0.8.15 a literal `0` looks exactly like a working
  breakpoint, so no negative control there may ever be a bare number.
- **`hit` is honoured.** `break 0x3a hit 2` reads `Hit 2` and stops on the second crossing, like
  the positional `break 0x3a 2`; the event forms take it too (`break iram w 0x30 hit 2`). Upstream
  0.8.15 accepts the keyword, silently keeps `Hit 1` and stops on the first crossing.
- **`var` binds a cell; its old usage line was wrong.** `var counter iram 0x30`, `var flag
  iram[0x40]`, `var a sfr[0xe0]` and bare `var scratch` (a slot of its own in `variables[]`) all
  work; the literal `var counter memory 0x30` is refused, because the `memory` in the old usage
  line was a placeholder that people typed as a keyword. The usage line now spells the two real
  forms. The failure was never fatal, so a script that ignored it went on to condition on an
  undefined name — which simply never fires.
- **`break rom 0x3a`** is rejected (fetch breakpoints take a bare address; the grammar only accepts
  `mem op addr`). A watchpoint by name works only as the name alone: `break flag` places **two**
  event breakpoints on the variable's cell, one `read` and one `write`, while `break AUXR w` fails.
- **`delete` takes the id from `info break`, never an address.** `delete 0x3a` and `delete 58` print
  a bare `Error` and leave every row in the table exactly as it was; `delete 1` removes the row
  numbered 1, and `del break` answers with the same bare `Error` — that reply is not a distinctive
  symptom of any one spelling. A reply, or its absence, proves nothing either way: resolve
  address → id from `info break`, delete, then re-read the table.
- **`Hit`, `Cnt` and `Cond` lie on a row that has never run.** A breakpoint created and never hit
  prints `Hit 1  Cnt 1`, so `Hit` is not an execution counter, and `Cond` prints `true` for a
  breakpoint with no condition at all. Neither column tells you what you asked for; the condition
  text exists only in the `Breakpoint N at 0x… (cond="…")` reply.
- **no `finish`, no `bt`** — stepping out of a subroutine and a call stack do not exist. `info
  registers` prints `SP 0x60 -> f6 8d e3 …`; the return addresses are yours to read.
