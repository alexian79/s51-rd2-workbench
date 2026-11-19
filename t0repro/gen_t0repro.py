#!/usr/bin/env python3
"""
t0repro.ihx — replica of the firmware in the other agent's T0 report.

Layout mirrored from the report:
  0x0000  LJMP  INIT                 reset vector
  0x000B  LJMP  T0ISR                T0 interrupt vector
  0x2280  INIT: MOV TMOD,#51h        T0=16-bit timer, T1=16-bit external counter (P3.5)
                MOV TH0,#0FDh        start value 0xFD01, exactly as the report's trace
                MOV TL0,#01h
                MOV IE,#82h          EA + ET0
                MOV TCON,#55h        TR0=1 TR1=1 (palindromic: same under bit-reversed layout)
  0x22C9  SPIN: JNB FL_DISABLED,SPIN the pinned PC in the report (FL_DISABLED = 0x20.0)
  0x327C  T0ISR: 16-bit counter @0x30/0x31, SETB FL_DISABLED at 1000 overflows
"""

def word(v):
    return [(v >> 8) & 0xFF, v & 0xFF]

mem = {}

def put(addr, data):
    for i, b in enumerate(data):
        mem[addr + i] = b

INIT = 0x2280
SPIN = 0x22C9
T0ISR = 0x327C

put(0x0000, [0x02] + word(INIT))                 # LJMP INIT
put(0x000B, [0x02] + word(T0ISR))                # LJMP T0ISR

init = [0x75, 0x89, 0x51,                         # MOV TMOD,#51h
        0x75, 0x8C, 0xFD,                         # MOV TH0,#0FDh
        0x75, 0x8A, 0x01,                         # MOV TL0,#01h
        0x75, 0xA8, 0x82]                         # MOV IE,#82h
init += [0x75, 0x88, 0x55]                        # MOV TCON,#55h
init += [0x00] * (SPIN - INIT - len(init))       # NOP fallthrough to SPIN
put(INIT, init)
put(SPIN, [0x20, 0x00, 0xFD,                      # SPIN: JNB 00h,SPIN
           0x80, 0xFE])                           # (unreachable tail) SJMP $

isr = [0xC0, 0xE0,                                # PUSH ACC
       0x05, 0x30,                                # INC 0x30
       0xE5, 0x30,                                # MOV A,0x30
       0x70, 0x02,                                # JNZ +2 (skip high INC)
       0x05, 0x31,                                # INC 0x31
       0xC5, 0x30, 0xE8, 0x06,                    # CJNE 0x30,#0E8 -> pop (low of 1000)
       0xC5, 0x31, 0x03, 0x02,                    # CJNE 0x31,#003 -> pop (high of 1000)
       0xD2, 0x00,                                # SETB FL_DISABLED (bit 0x20.0 = 0x00)
       0xD0, 0xE0,                                # POP ACC
       0x32]                                     # RETI
put(T0ISR, isr)

lines = []
for base in range(0, 0x3300, 16):
    chunk = [mem.get(base + i, None) for i in range(16)]
    while chunk and chunk[-1] is None:
        chunk.pop()
    if not chunk:
        continue
    data = [b for b in chunk if b is not None]
    if len(data) != len(chunk):                   # keep it contiguous: fill holes with 0
        data = [(mem.get(base + i, 0)) for i in range(len(chunk))]
    rec = [len(data), (base >> 8) & 0xFF, base & 0xFF, 0x00] + data
    rec.append((-(sum(rec))) & 0xFF)
    lines.append(":" + "".join("%02X" % b for b in rec))
lines.append(":00000001FF")

import os
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "t0repro.ihx")
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print("wrote", out, len(lines), "records")
