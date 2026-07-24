#!/usr/bin/env bash
#
# Byte-identity guard for the cross-language wire-contract golden fixture.
#
# The HAVI mobile SDK ships the same golden envelope table twice — once for the
# Swift tests and once for the Android tests. The two copies MUST stay
# byte-for-byte identical so that iOS and Android are asserted against exactly
# the same wire contract. This check fails when they drift apart.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

ios_fixture="$repo_root/Tests/HaviKitTests/Fixtures/havi-envelope-golden.json"
android_fixture="$repo_root/android/havikit-core/src/test/resources/havi-envelope-golden.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -f "$ios_fixture" ] || fail "iOS golden fixture not found: $ios_fixture"
[ -f "$android_fixture" ] || fail "Android golden fixture not found: $android_fixture"

if ! cmp -s "$ios_fixture" "$android_fixture"; then
  echo "The iOS and Android golden fixtures have drifted apart:" >&2
  cmp "$ios_fixture" "$android_fixture" >&2 || true
  echo >&2
  echo "Both copies must be byte-for-byte identical. Update whichever is stale" >&2
  echo "so the following two paths hold the same bytes:" >&2
  echo "  $ios_fixture" >&2
  echo "  $android_fixture" >&2
  exit 1
fi

echo "OK: golden fixtures are byte-identical"
echo "  $ios_fixture"
echo "  $android_fixture"
