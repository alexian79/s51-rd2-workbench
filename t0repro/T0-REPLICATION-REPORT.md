# T0 replication report — BV08 config vs s51-rd2-workbench (WSL, green build)

Verdict: **the reported symptoms do not replicate.** T0, TF0, vectoring, the ISR
reload ladder and the `JNB TMF,$` boot poll all work, tick-exact, on both
binaries (patched `ucsim_51` and control `s51-ref-b`, device 89C51RD2). The
other agent's observations are reproducible artifacts of **how** its session was
driven, not of the model.

## What was replicated (from the forwarded config photos)

`gen_t0v2.py` rebuilds the real boot: `MOV SP,#60h, TCON,#55h, TMOD,#51h,
AUXR,#11h, CKCON,#7Fh; SETB EA; TL0/TH0=#0xFA21; TMR=10; CLR TMF; JNB TMF,$`
plus the 0x000B→LJMP 0x327C ISR (reload FA21, `DJNZ TMR`, SETB FL_DISABLED at
0, re-arm). Variant A sets ET0 before the spin, variant B after.

## Measured facts (both binaries identical, every run)

| probe | result |
|---|---|
| first T0 overflow, reload 0xFA21 | stop at 0x327c @ **18216 ticks** = 27 init + 1503 mc × 12t — exact |
| first overflow, reload 0xFD01 (v1) | 9372 ticks = 15 + 766 × 12 — exact |
| T0 rate | 1 tick / machine cycle (CKCON=0x7F leaves **X2 (bit7) clear** — bmX2=0x80 in `uc89c51r.cc`, so 12t standard is correct, not a bug) |
| TF0 readback | reads **0 after vectoring** — hardware clears on ack. "TF0 never set" in dumps is the *normal* post-ack state |
| TCON readback | `MOV TCON,#55h` then `dump sfr 0x88 0x8d` → `0b01010101 0x55` — no stale bits |
| vectoring | LJMP 0x000B→0x327C taken, SP push/pop correct, same-level re-entry blocked until RETI |
| AUXR=0x11 | accepted, reads 0x11. Caveat below |

## Root causes of the original session's symptoms (all artifacts)

1. **Console `file` needs quotes**: `file /path/x.ihx` → `File name is missing.`
   and *nothing loads* (I hit this — every early run silently simulated a blank
   chip). Signature reproduced exactly: handler bp never taken (PC walks erased
   0xFF = `MOV R7,A` at 1 instr/12t; 0x327c would only be hit after 12924
   steps), **every** SFR dump 0x00, "counter never counts".
   Correct: `file "/path/x.ihx"` → `Loading from ...` banner appears.
2. **Wrong dump space**: `dump 0x88` dumps FLASH (zeros). SFR view is
   `dump sfr 0x88 0x8d`. Their "TCON: 0x00 while timer runs" is this.
3. **No `poke` verb** in this console (it's `set`/`var`); every poke they
   scripted was a silent no-op ("File name is missing." / "Parser error").
4. `go` over a piped console is **async**; a following `quit` lands ms later.
   Long runs need `step N` (or `run`), or spaced commands.
5. Their "bit-reversed TCON layout" theory is dead on their own evidence: the
   REG51RX2 table they extracted is the **standard** layout (TR0=0x10=bit4), and
   `regs51.h` bmTR0=0x10 — agreement, not mismatch. bmT0X2/bmT1X2 zeroing was
   disproven in source: `peripheral_cycles` only divides when **both** bmX2 and
   the per-timer bit are set, with a half-cycle carry (`x2_carry[]`) so it can
   never round to 0.

## The one real divergence found (latent, not this blocker)

**AUXR on the RD2 is the XRAM bank register**: XRS2:0 in bits 2:0 (001 = 512 B
window), EXTRAM bit 7 (`uc89c51r.cc:296`, `decode_xram`). BV08's `MOV AUXR,#11h`
writes XRS=001 → every `MOVX` above 0x1FF wraps into a 512-byte bank and the
low 256 alias across all banks. If TMR/ladder live in XRAM (large model),
`DJNZ TMR` reads the wrong cell and the 1 s/5 s ladder silently never fires —
on real silicon too. Worth checking where BV08 places `TMR`, `TL15/TH15`.
Also doc4235 AUXR=0x11 bit0 EXTR0 (T0 external clock) — model ignores it; that
is where ucsim and hardware genuinely differ for T0, but in the *hardware*
direction (silicon would freeze T0 counting a quiet P3.4, ucsim keeps ticking).
That is the only hardware-vs-ucsim path I can see that reproduces "T0 dead on
device, fine in sim".

## Model bugs found while investigating

None in the timer path. The one real derailment found (self-re-entering ISR,
SP creeping +1 per loop) was **my replica's bug** — `B5` = `CJNE A,direct,rel`,
not `CJNE direct,#data` (`C5`). Fixed in gen; the model then stayed tick-exact.

## s51dbg replay (the other agent's own driver)

`run-s51dbg.sh` + `s51dbg-session.jsonl`: load t0v2a, break 0x327c, three
`cont`s → **each stops at 0x327c**; SFR dumps at every stop show
`TCON 0x55 / TMOD 0x51 / TL0 advancing`; `del_break` + two `step 20000` runs
(240072 ticks each) → **PC stays pinned at 0x22a7** (`SJMP $`). The whole
reported picture — pinned PC, live handler, TF0 always 0 in dumps — appears
through their tooling with the correct reading: boot won the TF0 race on the
*first* overflow (JNB samples before the core acks), then every subsequent
overflow is stolen by the ISR, so main never advances past the tail marker.

### Workbench finding (driver, not model)

`load(device=...)` sends `cpu "<name>"`; this build's console has **no `cpu`
verb at all** (Parser error quoted or not, stdin and -Z network console
alike). The load returns `ok:false` but the file still loads and the session
silently keeps the spawn-time `-t` device (default 89C51R). A harness that
ignores `ok` and believes `device` runs a different chip than it asked for.
The suites dodge this by spawning with `-t` directly, which works.

## Artifacts

All in `t0repro/` (this directory). Regenerate the images, then run any
script:

    python3 gen_t0repro.py        # -> t0repro.ihx   (v1, 0xFD01 one-shot)
    python3 gen_t0v2.py           # -> t0v2a.ihx, t0v2b.ihx (BV08-exact boot)
    ./run-v2h.sh                  # decisive: handler bp under go AND step
    ./run-final.sh                # v1 end-to-end, patched + control binary
    ./run-trace.sh                # 1-step trace that pinned the B5/C5 bug
    ./run-s51dbg.sh               # replay through tools/s51dbg.py --jsonl

Paths default to `$HOME/s51-workbench/s51-ucsim-rd2` (bring-up.sh default);
override with `WB=` or `S51_R2_DIR=`, control binary with `CTL=`.
