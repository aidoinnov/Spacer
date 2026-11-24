#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p References/Windows
archive="References/Windows/spacesniffer_2_2_0_27_x64.zip"
curl -fL --retry 2 'https://www.uderzo.it/main_products/space_sniffer/files/spacesniffer_2_2_0_27_x64.zip' -o "$archive"
expected='1b0f676927e37747566075b1970615138d3de26a'
actual="$(shasum "$archive" | cut -d ' ' -f 1)"
if [[ "$actual" != "$expected" ]]; then
  printf 'Archive checksum mismatch: %s\n' "$actual" >&2
  exit 1
fi
mkdir -p References/Windows/2.2.0.27
unzip -o "$archive" -d References/Windows/2.2.0.27
