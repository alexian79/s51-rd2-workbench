#!/usr/bin/env python3
"""
t0v2: replica of the REAL BV08 config (from the forwarded report photos).

Boot (BV08ct22.a51:469-490):
  MOV SP,#60h ; MOV TCON,#55h ; MOV TMOD,#51h ; MOV AUXR,#11h ; MOV CKCON,#7Fh
  SETB P2.5 ; CLR P3.7 ; SETB FL_DISABLED ; SETB EA
  InitTMR: MOV TL0,#21h / MOV TH0,#0FAh          (mkS1000 = 0xFA21)
  MOV TMR(0x30),#10 ; CLR TMF ; JNB TMF,$        <- boot waits for first T0 tick
  fallthrough: SJMP $                            <- marker: boot saw TF0
Variant A: SETB ET0 BEFORE the spin (ISR steals TF0 -> spin must hang).
Variant B: SETB ET0 AFTER  the spin (poll sees TF0; handler runs later).
ISR @0x327C (int_TMR): reload FA21, DJNZ TMR,#10 re-arm, SETB FL_DISABLED at 0.
"""

import os
RELOAD_LO, RELOAD_HI = 0x21, 0xFA


def build(variant):
    mem = {}

    def put(addr, data):
        for i, b in enumerate(data):
            mem[addr + i] = b

    def word(v):
        return [(v >> 8) & 0xFF, v & 0xFF]

    INIT, T0ISR = 0x2280, 0x327C
    put(0x0000, [0x02] + word(INIT))                 # LJMP INIT
    put(0x000B, [0x02] + word(T0ISR))                # LJMP int_TMR

    init = [0x75, 0x81, 0x60,                        # MOV SP,#60h
            0x75, 0x88, 0x55,                        # MOV TCON,#55h
            0x75, 0x89, 0x51,                        # MOV TMOD,#51h
            0x75, 0x8E, 0x11,                        # MOV AUXR,#11h
            0x75, 0x8F, 0x7F,                        # MOV CKCON,#7Fh
            0xD2, 0xA5,                              # SETB P2.5  (INTR)
            0xC2, 0xB7,                              # CLR  P3.7  (CLK)
            0xD2, 0x00,                              # SETB FL_DISABLED (0x20.0)
            0xD2, 0xAF]                              # SETB EA (IE.7)
    init += [0x75, 0x8A, RELOAD_LO,                  # MOV TL0,#Low(mkS1000)
             0x75, 0x8C, RELOAD_HI]                  # MOV TH0,#High(mkS1000)
    if variant == "a":
        init += [0xD2, 0xA9]                         # SETB ET0 BEFORE spin
    init += [0x75, 0x30, 0x0A,                       # MOV TMR,#10
             0xC2, 0x8D,                             # CLR TMF (TCON.5)
             0x20, 0x8D, 0xFE]                       # JNB TMF,$
    mark = INIT + len(init)
    init += [0x80, 0xFE]                             # MARK: SJMP $ (boot saw TF0)
    if variant == "b":
        init += [0xD2, 0xA9]                         # SETB ET0 AFTER spin
    put(INIT, init)

    isr = [0x75, 0x8A, RELOAD_LO,                    # MOV TL0,#21h
           0x75, 0x8C, RELOAD_HI,                    # MOV TH0,#0FAh
           0xD5, 0x30, 0x05,                         # DJNZ TMR,+5 -> RETI
           0xD2, 0x00,                               # SETB FL_DISABLED
           0x75, 0x30, 0x0A,                         # MOV TMR,#10 (re-arm)
           0x32]                                     # RETI
    put(T0ISR, isr)

    lines = []
    for base in range(0, 0x3300, 16):
        chunk = [mem.get(base + i, None) for i in range(16)]
        while chunk and chunk[-1] is None:
            chunk.pop()
        if not chunk:
            continue
        data = [(mem.get(base + i, 0)) for i in range(len(chunk))]
        rec = [len(data), (base >> 8) & 0xFF, base & 0xFF, 0x00] + data
        rec.append((-(sum(rec))) & 0xFF)
        lines.append(":" + "".join("%02X" % b for b in rec))
    lines.append(":00000001FF")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "t0v2%s.ihx" % variant)
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", out, "MARK=0x%x ISR=0x%x" % (mark, T0ISR))
    return mark


for v in ("a", "b"):
    build(v)
