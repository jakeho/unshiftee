#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:-$repo_root/dist/Unshiftee.app}"
module_cache="$repo_root/.build/module-cache"

mkdir -p "$module_cache"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache"

/usr/bin/swift build \
  --package-path "$repo_root" \
  --disable-sandbox \
  --configuration release

binary_directory="$(
  /usr/bin/swift build \
    --package-path "$repo_root" \
    --disable-sandbox \
    --configuration release \
    --show-bin-path
)"

rm -rf "$destination"
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"

/usr/bin/ditto "$binary_directory/Unshiftee" "$destination/Contents/MacOS/Unshiftee"
/usr/bin/ditto "$repo_root/Resources/Info.plist" "$destination/Contents/Info.plist"
/usr/bin/ditto "$repo_root/Resources/AppIcon.icns" "$destination/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$repo_root/DISCLAIMER.md" "$destination/Contents/Resources/DISCLAIMER.md"
/usr/bin/codesign --force --deep --sign - "$destination"

print "Built $destination"
