#!/bin/bash
# Extract JDK + Ghidra into the workbench folder and install the MSYS analyzeHeadless bridge.
set -e
W=/p/projects/s51-rd2-workbench
cd "$W"
JDK_DIR=$(printf '%s\n' jdk-*/ | head -1)
if [ -z "$JDK_DIR" ]; then
  tar -xf jdk21.zip
  JDK_DIR=$(printf '%s\n' jdk-*/ | head -1)
fi
echo "JDK: $JDK_DIR"
if [ ! -d ghidra_12.1.4_PUBLIC ]; then
  tar -xf ghidra.zip
fi
ls -d ghidra_12.1.4_PUBLIC
# --- MSYS bridge for analyzeHeadless (launch.sh rejects MSYS_NT and would build a
# ':'-separated classpath for a Windows JVM). Route to analyzeHeadless.bat instead.
A=ghidra_12.1.4_PUBLIC/support/analyzeHeadless
if [ ! -f "$A.linux-original" ]; then
  mv "$A" "$A.linux-original"
fi
cat > "$A" <<'EOF'
#!/usr/bin/env bash
# MSYS-bridge installed over Ghidra's stock analyzeHeadless (the original is kept as
# analyzeHeadless.linux-original). Under MSYS2, launch.sh rejects MSYS_NT and would build a
# ':'-separated classpath for a Windows JVM, so route to analyzeHeadless.bat instead,
# translating POSIX path arguments the way cmd.exe needs them.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. /p/projects/s51-rd2-workbench/native-support/bin/winpath.sh
bat="$(winpath "$DIR/analyzeHeadless.bat")"
out=()
for a in "$@"; do out+=("$(winpath "$a")"); done
exec cmd //c "$bat" "${out[@]}"
EOF
chmod +x "$A"
echo TOOLS-SETUP-OK
