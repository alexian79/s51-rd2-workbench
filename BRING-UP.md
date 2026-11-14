# AT89C51RD2 workbench — agent bring-up runbook

The executable checklist for getting the whole AT89C51RD2 / AT89C51ED2 toolchain up and proving it
works. Prose, rationale and datasheet citations live in [`README.md`](README.md); this file is the
form an agent can follow without reading that first.

Fetch it raw:

    curl -fsSL https://raw.githubusercontent.com/alexian79/s51-rd2-workbench/main/BRING-UP.md

Three repositories, two licences:

| repo | licence | what it is |
|---|---|---|
| [`s51-ucsim-rd2`](https://github.com/alexian79/s51-ucsim-rd2) | GPL-2.0-or-later | ucsim device-model + peripheral build-out as a patch against upstream, 22-suite verification bed, analysis notes |
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
| `t/floor.sh` (22 suites, one binary) | `floor: 0 suite(s) not green` |
| `langtest` | `PASS: 22/22 checks` |
| `rmwtest` | `PASS: 10/10 cases agree with the simulator` |
| `banktest` | `PASS: 3/3` |

Representative floor legs when green: `rd2registers PASS: 288/288`, `irctest PASS: 50/50`,
`t2cnttest: PASS 30/30 legs`, `ident89c51r PASS: 36/36 transcripts byte-identical`,
`rd2identity PASS: 38/38`, `x2test PASS: 15/15`, `eepromtest PASS: 29/29`.

Two lines that look like failures and are not:

- `runtests  11/20 baselines match` — the upstream baseline is 11/20 and that suite exits non-zero by
  design. It is **reported, never counted**; "1 not green" has never meant this suite.
- `eepromtest` printing 29 instead of 30 — the 30th leg compares against a control binary supplied
  through `S51_REF`. Absent that variable, 29 is correct.

## 3. Ordering rules that bite

- The language must be **installed before the simulation floor**: `banktest` runs *inside* the floor
  and resolves SFR names through the installed module. A machine that fails `banktest` first thing
  usually just has no module installed yet.
- Run `langtest`, `rmwtest`, `banktest` **one at a time**: each starts a headless Ghidra with fixed
  project names and they collide.
- Syntax-check these scripts with `bash -n`. `sh -n` fails falsely because `gh51` uses arrays.
- The simulator patch expects the vendor tree at commit `441710c` and expects **34** changed files.
  A different count means the base tree or the patch did not land cleanly — not a code bug.

## 4. Simulator console traps

| trap | truth |
|---|---|
| `code` space | it is called **`rom`**, not `code` |
| `info hw` | needs a *category*: `info hw port`, `info hw eeprom` |
| `get sfr` | can report stale values — use `dump sfr 0x80 0xff` |
| read-clear SFRs | reading one through the console **consumes the clear** |
| `file` command | path must be quoted: `file "t/isa.ihx"` |
| `step N` | a single step, not N |
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
