#!/bin/bash
WB=${WB:-$HOME/s51-workbench}
S=${S51_R2_DIR:-$WB/s51-ucsim-rd2}
D=$(dirname "$0")
cd "$S"
sed "s|@IMG@|$D/t0v2a.ihx|" "$D/s51dbg-session.jsonl" |
python3 tools/s51dbg.py --jsonl 2>&1 |
python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line or not line.startswith("{"):
        print(line); continue
    try: r = json.loads(line)
    except Exception: print(line[:200]); continue
    c = r.get("cmd","?")
    if c == "load":
        print("LOAD ok=%s pc=%s" % (r.get("ok"), r.get("pc")))
    elif c in ("cont","step"):
        print("%s ok=%s stop=%s pc=%s ticks=%s" % (c, r.get("ok"),
              r.get("stop_pc") or r.get("stop") or r.get("reason"),
              r.get("pc"), r.get("ticks")))
    elif c == "dump":
        print("dump:", str(r.get("cells") or r.get("raw") or r)[:180])
    elif c == "pc":
        print("pc=%s" % r.get("pc"))
    elif c == "del_break":
        print("del ok=%s" % r.get("ok"))
    elif c == "break":
        print("break ok=%s" % r.get("ok"))
    elif c == "regs":
        print("regs:", str({k:r.get(k) for k in ("ACC","SP","IE","PC") if k in r})[:200])
    else:
        print(c, str(r)[:180])
'
