#!/bin/bash
# Primary GPUI host-architecture build. SwiftUI references use build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 0 ]]; then
  printf 'Usage: %s (host architecture; configure SNIFFER_BUILD_ROOT / SNIFFER_BUILD_JOBS)\n' "$0" >&2
  exit 64
fi
build_root="${SNIFFER_BUILD_ROOT:-${TMPDIR:-/tmp}/space-sniffer-gpui-build}"
jobs="${SNIFFER_BUILD_JOBS:-4}"
version="$(python3 -c 'from pathlib import Path; import re; print(re.search(r"(?m)^version = \"([^\"]+)\"", Path("gpui-app/Cargo.toml").read_text()).group(1))')"
output_root="${SNIFFER_OUTPUT_ROOT:-$(pwd)/dist/gpui-builds}"
output="$output_root/${version}-$(uname -m)-$(date -u +%Y%m%dT%H%M%SZ)"
python3 scripts/gpui-app/check-shared-domain.py
python3 scripts/gpui-app/check-fonts.py
CARGO_TARGET_DIR="$build_root/cli-target" CARGO_INCREMENTAL=0 cargo +1.97.0 build --release --locked --manifest-path gpui-app/cli/Cargo.toml --jobs "$jobs"
swift build --scratch-path "$build_root/swift" -c release --product MacScanBridge --jobs 2
swift build --scratch-path "$build_root/swift" -c release --product MacPreviewSupport --jobs 2
SPACE_SNIFFER_BUNDLE_ID=local.macspacesniffer.app CARGO_INCREMENTAL=0 CARGO_TARGET_DIR="$build_root/target" \
  cargo +1.97.0 build --release --locked --manifest-path gpui-app/Cargo.toml --jobs "$jobs"
python3 scripts/gpui-app/package-macos.py --rust-binary "$build_root/target/release/space-sniffer-gpui" \
  --cli-binary "$build_root/cli-target/release/spacer-cli" \
  --native-directory "$build_root/swift/release" --output "$output/Mac Space Sniffer.app"
ditto -c -k --sequesterRsrc --keepParent "$output/Mac Space Sniffer.app" "$output/Mac-Space-Sniffer-$version-$(uname -m).zip"
python3 - "$output/Mac Space Sniffer.app" <<'PY'
from pathlib import Path
import os, sys
app=Path(sys.argv[1]); alias=Path('dist/Mac Space Sniffer GPUI.app'); stage=alias.with_name('.GPUI-latest.next')
assert not stage.exists() and (not alias.exists() or alias.is_symlink()), 'Do not replace an unrelated bundle'
stage.symlink_to(os.path.relpath(app, alias.parent), target_is_directory=True)
os.replace(stage, alias)
print('Built:', app)
print('Latest:', alias)
PY
