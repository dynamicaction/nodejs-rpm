#!/usr/bin/env python3
"""Set the version macros in nodejs22.spec from an extracted Node.js source tree.

Usage: update-spec.py <nodejs22.spec> <node-vX.Y.Z source dir>

Every value is read from the source tree, so the spec's bundled() Provides and
the %check version assertions match what is actually being built. Fails if a
macro is missing from the spec or a version cannot be found in the source.
"""
import json
import re
import sys
from pathlib import Path

spec_path, src = Path(sys.argv[1]), Path(sys.argv[2])
spec = spec_path.read_text()


def read(rel):
    return (src / rel).read_text()


def define(rel, name):
    m = re.search(r"#define\s+%s\s+\"?([^\"\s]+)\"?" % name, read(rel))
    if not m:
        sys.exit("cannot find %s in %s" % (name, rel))
    return m.group(1)


def dotted(rel, prefix, parts=("MAJOR", "MINOR", "PATCH")):
    return ".".join(define(rel, "%s_%s" % (prefix, p)) for p in parts)


def pkg(rel):
    return json.loads(read(rel))["version"]


node = dotted("src/node_version.h", "NODE", ("MAJOR_VERSION", "MINOR_VERSION", "PATCH_VERSION")).split(".")
v8 = dotted("deps/v8/include/v8-version.h", "V8", ("MAJOR_VERSION", "MINOR_VERSION", "BUILD_NUMBER", "PATCH_LEVEL")).split(".")
icu = re.search(r"release-(\d+)[.-](\d+)", json.loads(read("tools/icu/current_ver.dep"))[0]["url"])

macros = {
    "nodejs_major": node[0],
    "nodejs_minor": node[1],
    "nodejs_patch": node[2],
    "v8_major": v8[0],
    "v8_minor": v8[1],
    "v8_build": v8[2],
    "v8_patch": v8[3],
    "zlib_version": define("deps/zlib/zlib.h", "ZLIB_VERSION").split("-")[0],
    "c_ares_version": define("deps/cares/include/ares_version.h", "ARES_VERSION_STR"),
    "llhttp_version": dotted("deps/llhttp/include/llhttp.h", "LLHTTP_VERSION"),
    "libuv_version": dotted("deps/uv/include/uv/version.h", "UV_VERSION"),
    "nghttp2_version": define("deps/nghttp2/lib/includes/nghttp2/nghttp2ver.h", "NGHTTP2_VERSION"),
    "nghttp3_version": define("deps/ngtcp2/nghttp3/lib/includes/nghttp3/version.h", "NGHTTP3_VERSION"),
    "ngtcp2_version": define("deps/ngtcp2/ngtcp2/lib/includes/ngtcp2/version.h", "NGTCP2_VERSION"),
    "icu_major": icu.group(1),
    "icu_minor": icu.group(2),
    "simdutf_version": define("deps/simdutf/simdutf.h", "SIMDUTF_VERSION"),
    "npm_version": pkg("deps/npm/package.json"),
    "uvwasi_version": dotted("deps/uvwasi/include/uvwasi.h", "UVWASI_VERSION"),
    "sqlite_version": define("deps/sqlite/sqlite3.h", "SQLITE_VERSION"),
}

for name, value in macros.items():
    spec, n = re.subn(r"^(%%global %s) \S+$" % name, r"\g<1> %s" % value, spec, flags=re.M)
    if n != 1:
        sys.exit("expected one %%global %s in the spec, found %d" % (name, n))

provides = {
    "ada": define("deps/ada/ada.h", "ADA_VERSION"),
    "nodejs-cjs-module-lexer": pkg("deps/cjs-module-lexer/src/package.json"),
    "nodejs-undici": pkg("deps/undici/src/package.json"),
    "brotli": dotted("deps/brotli/c/common/version.h", "BROTLI_VERSION"),
}
for name, value in provides.items():
    spec, n = re.subn(r"^(Provides: bundled\(%s\) =) \S+$" % re.escape(name), r"\g<1> %s" % value, spec, flags=re.M)
    if n != 1:
        sys.exit("expected one bundled(%s) Provides in the spec, found %d" % (name, n))

spec_path.write_text(spec)
for name, value in {**macros, **provides}.items():
    print("%-24s %s" % (name, value))
