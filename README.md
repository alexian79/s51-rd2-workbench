# AT89C51RD2 workbench — bring everything up in one command

The index and bring-up script for three repositories that together turn an Atmel
**AT89C51RD2 / AT89C51ED2** image into something you can actually reverse engineer: a
cycle-accurate simulator you can step, and a Ghidra language that resolves the chip's odd registers
instead of lying about them.

| repo | licence | what it is |
|---|---|---|
| [`s51-ucsim-rd2`](https://github.com/alexian79/s51-ucsim-rd2) | GPL-2.0-or-later | the simulator: ucsim device-model and peripheral build-out, delivered as a patch against upstream, plus the 22-suite verification bed and the analysis notes |
| [`ghidra-at89c51rd2`](https://github.com/alexian79/ghidra-at89c51rd2) | Apache-2.0 | the Ghidra processor module: dual DPTR in Sleigh context, 1792 B on-chip XRAM, doc4235 SFR map, `gh51` headless front end |
| [`ghidra-8051-dual-dptr`](https://github.com/alexian79/ghidra-8051-dual-dptr) | Apache-2.0 | the same bank model as a gated patch to Ghidra's *shared* `8051_main.sinc`, with the proof that it is inert for every language that does not opt in |

## One command

    curl -fsSL https://raw.githubusercontent.com/alexian79/s51-rd2-workbench/main/bring-up.sh -o bring-up.sh
    sh bring-up.sh

If you are an agent executing this rather than a person reading it, use
[`BRING-UP.md`](BRING-UP.md): the exact strings each gate must print, exit-status semantics, and the
ordering and console traps that otherwise cost a wasted run.

It is idempotent — rerun it any time and it skips whatever is already done. It will:

1. check for `git`, `python3`, `make`, `g++` (and `java` + Ghidra if you have them);
2. clone the three repos into `$WB_ROOT` (default `~/s51-workbench`);
3. clone the GPL simulator base `CrispStrobe/ucsim-stc`, check out commit `441710c`, and apply
   `patches/rd2-vs-ucsim-stc-441710c.patch` — **40 files**, 30 modified `+1635 / -200` and 10 new
   (+2483 lines);
4. build `ucsim_51`;
5. run the **24-suite simulation floor** against that one binary and require zero not-green;
6. install and compile the Ghidra language into `$GHIDRA`, then run the three Ghidra gates.

Knobs: `WB_ROOT=/tmp/wb` (where the workbench lives), `GHIDRA=/path/to/ghidra_12.1.4_PUBLIC`,
`SKIP_GHIDRA=1` (simulator only — those gates are then *skipped*, never silently passed).

## What the gates actually prove

The point of this bed is that no claim rests on a simulator agreeing with itself.

| check | result | what it pins |
|---|---|---|
| `t/floor.sh` (22 suites) | **0 not green** | cycle accuracy, the ten expanded-RAM boundaries, X2 clock modes, boot ROM, SPI bit clock, keyboard, EUART/BRG, prescaler, watchdog, PCA, interrupt priority, dual DPTR, ED2 EEPROM, one-count-per-edge |
| `runtests.py` | 11/20 upstream baselines | reported, **never counted** — it exits non-zero by design at 11/20, so "1 not green" has never meant this suite |
| `xcompare.py` vs an independent Rust `i8051` core | pc **104/104**, cycles **104/104** | control flow and timing corroborated by a second core; the PSW deltas are bugs in *that* core, checked against the Atmel C51 manual |
| `t2cnttest.py` | 30/30, and **9/30 before the fix** | a timer/PCA edge is counted exactly once — the regression gate for the port-mirror double-notify |
| `eepromtest.py` | 29 legs (30 with `S51_REF`) | ED2 EEPROM timing / busy / window; the 30th leg proves the RD2 device transcript stayed byte-identical |
| `bpcmdtest.py` | 25/25 — **6 legs fail on a pre-fix binary, by design** | what `break` and `var` accept and refuse: conditions at both polarities, the refusal text, `hit`, the `var` bindings |
| `wptrtest.py` | 27/27 on **both** build families | watchpoint-as-assertion, plus which fetch-breakpoint stepping rule the binary implements (classified from behaviour, not version) |
| `langtest.py` | 22/22 | registers, SFR map, memory blocks and dual DPTR as Ghidra sees them |
| `rmwtest.py` | 10/10 | `ORL/ANL/XRL/DEC` on `AUXR1`: the **same bytes** run through the executing simulator and through Ghidra's static resolution must agree |
| `banktest.py` | 3/3 | the `MOV AUXR1,A` case Ghidra cannot resolve statically — it first records Ghidra being wrong, then checks the `Bank51` override fixes it |

## Using it

    cd $WB_ROOT/s51-ucsim-rd2
    ./s51 t/isa.ihx                       # == ucsim_51 -t 89C51R <image>
    ./s51 -X 11.0592M firmware.hex        # a real crystal, so baud and timers are honest
    echo 'file "t/isa.ihx"; b 0x12; go; info reg; dump sfr 0x80 0xff' | ./s51 -c -

Console traps worth knowing up front: the code space is called **`rom`**, not `code`; `info hw`
needs a *category* (`info hw port`, `info hw eeprom`); `get sfr` can report stale values, so use
`dump sfr`; and reading a read-clear SFR through the console consumes the clear.

    cd $WB_ROOT/ghidra-at89c51rd2
    ./gh51 demo ../s51-ucsim-rd2/t/isa.ihx                        # analyse + report unmodelled SFR access
    S51LANG=8051:BE:16:default ./gh51 demo ../s51-ucsim-rd2/t/isa.ihx   # same image, stock language

Running `gh51` under both languages is the quickest way to see what the custom module buys you.

## Troubleshooting

| symptom | cause |
|---|---|
| `Unsupported language: AT89C51RD2:BE:16:default` | Ghidra silently ignores modules missing `Module.manifest`, `lib/`, or a current-schema `.ldefs`. Run `./langbuild`; the real reason is one `ERROR` line in `~/.config/ghidra/<version>/application.log` |
| language behaves oddly after a Ghidra upgrade | rerun `./langbuild` — it recompiles the `.sla` and re-installs the module |
| `STOP: no binary at ...` or a build failure | `/tmp/s51-configure.log` and `/tmp/s51-make.log` |
| firmware will not stop where you expect | a `break … if` condition must be a single token or a quoted string (quoted brackets work; unquoted ones create nothing), `run` freezes its own console so a heredoc has to hold stdin open, and stop codes are the only discriminator: `(104)` fired, `(109)` merely stepped onto, `(112)` watchpoint — see [`BRING-UP.md`](BRING-UP.md) §7 |
| `expected 34 changed files after the patch, found N` | the vendor tree is not at `441710c`, or the patch did not land cleanly |
| a suite seems to test the wrong build | every suite reads `S51_SIM` (binary) and `S51` (repo root); `floor.sh` exports both, and `S51_ROOT` moves the whole tree |
| `eepromtest` prints 29, not 30 | the 30th leg is the RD2 identity check against a control binary given by `S51_REF` — not a defect |
| Ghidra suites interfere with each other | each starts a headless Ghidra with fixed project names: run `langtest`, `rmwtest`, `banktest` **one at a time** |
| `xcompare.py` will not run | it drives the Rust `i8051` core; the `xval/` driver path-deps on `vendor/mcs51-rs`, which you clone yourself |

## Deliberately not here

- **The GPL base tree** (`CrispStrobe/ucsim-stc`, 161 MB) and the two other third-party cores
  (`cpu8051`, `mcs51-rs`). `bring-up.sh` clones the one it needs; the recipe and the reasons are in
  each repo's `NOTICE`. That patch is verified against a fresh clone of `441710c`: applied there,
  `diff -rq` against the tree every suite was run against reports **no content differences**.
- **The Atmel datasheets.** `doc4235` and `doc4316` are Microchip copyright and are not
  redistributed; every citation in the docs gives a section and a **printed** page number.
- **The `.sla` in the language repo** is committed for convenience but is a build product;
  `langbuild` regenerates it from `rd2.sinc`.

## Status and known-open items

- Two defects were found in ucsim itself and are packaged in `s51-ucsim-rd2/slices/` as
  self-contained, upstream-sized changes with their own evidence: timer 2's
  `do_t2_reload` / `do_t2_capture` ignoring their `cycles` argument, and the port-mirror write
  re-entering `cl_port::write` so every counter edge fired **twice**. Both are reproduced on
  pristine upstream trees.
- **Not submitted anywhere.** If they ever are, the Ghidra change still needs a
  `certification.manifest` and an issue, and the ucsim changes need rebasing onto 0.9.x rather than
  a plain `git apply`.
- **Open question, unmodelled on purpose:** `timer0.cc` samples the T0/T1 counter inputs on a
  *rising* edge while timer 2, the PCA and the external interrupts use *falling*. The suites assert
  one count per full toggle, so they hold either way — it needs the hardware manual's counter-edge
  statement before anyone should pick a side.
- **Honest coverage limit:** the STC12 port path shares `port.cc` with the double-notify fix and is
  not covered by any suite in this bed.

## Licences

Simulator work: GPL-2.0-or-later, because it modifies ucsim. Ghidra work: Apache-2.0, because
`rd2.sinc` is a derivative of Ghidra's own `8051_main.sinc`. Copyright (C) 2026 Oleksiy — base
commits, provenance and the full third-party list are in each repo's `NOTICE`. The two files in
*this* repo (`README.md`, `bring-up.sh`) contain no code from the other three and carry no licence
file: use them however you like.
