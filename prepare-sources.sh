#!/bin/bash
# Stage an rpmbuild tree for a Node.js 22 release: verified upstream tarball
# with deps/openssl removed (Amazon's "stripped" tarball), ICU data, this
# repo's patches and files, and the spec with versions read from the source.
#
# Usage: ./prepare-sources.sh <node version, e.g. 22.23.4> [work dir]
set -euo pipefail

version=${1:?usage: $0 <node version> [work dir]}
work=${2:-$PWD/work}
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

sha() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
sha512() { if command -v sha512sum >/dev/null; then sha512sum "$@"; else shasum -a 512 "$@"; fi; }

rm -rf "$work"
mkdir -p "$work/download" "$work/rpmbuild/SOURCES" "$work/rpmbuild/SPECS"
cd "$work/download"

echo "== node-v$version.tar.gz"
curl -sSfLO "https://nodejs.org/dist/v$version/node-v$version.tar.gz"
curl -sSfL "https://nodejs.org/dist/v$version/SHASUMS256.txt" | grep " node-v$version.tar.gz\$" | sha -c -
tar -zxf "node-v$version.tar.gz"
rm -rf "node-v$version/deps/openssl"
tar -zcf "$work/rpmbuild/SOURCES/node-v$version-stripped.tar.gz" "node-v$version"

icu=$(python3 -I -c 'import json,re,sys; m=re.search(r"release-(\d+)[.-](\d+)", json.load(open(sys.argv[1]))[0]["url"]); print(m.group(1)+"."+m.group(2))' "node-v$version/tools/icu/current_ver.dep")
echo "== ICU $icu data"
for f in "icu4c-$icu-data-bin-b.zip" "icu4c-$icu-data-bin-l.zip" SHASUM512.txt; do
    curl -sSfLO "https://github.com/unicode-org/icu/releases/download/release-$icu/$f"
done
grep -E "icu4c-$icu-data-bin-(b|l)\.zip\$" SHASUM512.txt | sha512 -c -
cp icu4c-"$icu"-data-bin-*.zip "$work/rpmbuild/SOURCES/"

cp "$repo"/[0-9][0-9][0-9][0-9]-*.patch "$repo"/npmrc.nodejs22 "$repo"/btest402.js \
   "$repo"/nodejs.pc.in "$repo"/v8.pc.in "$repo"/nodejs-sources.sh "$work/rpmbuild/SOURCES/"
cp "$repo/nodejs22.spec" "$work/rpmbuild/SPECS/"

echo "== spec versions"
python3 -I "$repo/update-spec.py" "$work/rpmbuild/SPECS/nodejs22.spec" "node-v$version"

# rpm applies patches in order with --fuzz=0; check the same way here so a
# patch that is now upstream or needs rebasing fails before a long build.
echo "== patches (in spec order, --fuzz=0)"
failed=0
for p in $(sed -n 's/^Patch[0-9]*: *//p' "$work/rpmbuild/SPECS/nodejs22.spec"); do
    if patch -d "node-v$version" -p1 --fuzz=0 -s -f < "$work/rpmbuild/SOURCES/$p" >/dev/null 2>&1; then
        echo "ok        $p"
    elif patch -d "node-v$version" -p1 -R --dry-run --fuzz=0 -s -f < "$work/rpmbuild/SOURCES/$p" >/dev/null 2>&1; then
        echo "UPSTREAM  $p  (already in $version: drop it from the spec)"; failed=1
    else
        echo "FAILS     $p  (check whether $version fixed it another way, else rebase)"; failed=1
    fi
done

echo
echo "Staged in $work/rpmbuild. Review the spec diff, then add a %changelog entry:"
echo "  diff $repo/nodejs22.spec $work/rpmbuild/SPECS/nodejs22.spec"
exit $failed
