#!/bin/sh
# udt_curses — assert the in-tree manifests agree with each other.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
#   sh tests/manifest-version.sh <version>
#
# WHAT THIS CHECKS.  The two manifests AGREE -- on the version, on the systems
# list, and on the C library this package links.  It does NOT police the
# version against the tag: the tag is stamped into every staged artifact
# instead (mvx#363), so the in-tree version is derived, not authoritative.
#
# WHICH IS WHY BOTH MANIFESTS SAY 0.0.0-dev (#4).  Do not bump it; nothing
# reads it, and the release stamps over it.
#
# WHY IT EXISTS AT ALL.  json#38 shipped a PKG declaring a system mvpkg.json
# had dropped.  Both files travel in every artifact and nothing resolves
# against PKG's copy, which is exactly why that survived a release.  Stamping
# cannot catch it: it writes one version into both files and so cannot notice
# they disagreed about anything else.
#
# IT DELIBERATELY DOES NOT COMPARE THE DEPENDENCY LINE.  PKG line 5 and
# mvpkg.json's "dependencies" use different spellings across the org
# (`+mvpkg` vs `mvx-lang/mvpkg`, `?cmd` vs `mvx-lang/cmd`, `mapfield@!mvx` vs
# `mapfield`), so comparing them needs normalising rules that do not exist
# yet.  This package's two do disagree -- see #7.
set -eu
WANT="${1:?usage: manifest-version.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rc=0

# A rolling dev tag is not a version and is not expected to match.
case "$WANT" in
  dev|latest) printf 'manifest-version: %s is not a version tag - skipped\n' "$WANT"; exit 0 ;;
esac

got=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/mvpkg.json" | head -1)
if [ "$got" = "$WANT" ]; then
  printf '  ok   mvpkg.json version is %s\n' "$WANT"
else
  printf '  FAIL mvpkg.json says "%s", not "%s"\n' "$got" "$WANT"; rc=1
fi

# PKG is line-oriented: 1 name, 2 version, 3 description, 4 systems, 5 deps.
got=$(sed -n '2p' "$ROOT/PKG" | tr -d ' \r')
if [ "$got" = "$WANT" ]; then
  printf '  ok   PKG line 2 is %s\n' "$WANT"
else
  printf '  FAIL PKG line 2 says "%s", not "%s"\n' "$got" "$WANT"; rc=1
fi

sysline=$(sed -n '4p' "$ROOT/PKG" | tr -s ' \r' ' ' | sed 's/^ *//;s/ *$//')
sysjson=$(sed -n '/"systems"/,/]/p' "$ROOT/mvpkg.json" \
          | sed -n 's/.*"\([a-z0-9_]*\)".*/\1/p' | grep -v '^systems$' | tr '\n' ' ' \
          | sed 's/ *$//')
if [ "$sysline" = "$sysjson" ]; then
  printf '  ok   both manifests declare the systems "%s"\n' "$sysline"
else
  printf '  FAIL PKG line 4 says "%s", mvpkg.json says "%s"\n' "$sysline" "$sysjson"; rc=1
fi

# AND THE C LIBRARY.  mvpkg.json's "clibs" is what MVPKG checks for before it
# installs; the -l flag in install.sh is what the bridge is actually linked
# against.  Disagree, and MVPKG either refuses an install that would have
# worked or allows one that cannot link.  `libncurses.so:>=6,<7` -> `ncurses`.
for lib in $(sed -n '/"clibs"/,/]/p' "$ROOT/mvpkg.json" \
             | sed -n 's/.*"lib\([a-z0-9_+-]*\)\.so[^"]*".*/\1/p'); do
  if grep -q -- "-l$lib" "$ROOT/install.sh"; then
    printf '  ok   install.sh links -l%s, the library mvpkg.json declares\n' "$lib"
  else
    printf '  FAIL mvpkg.json "clibs" names lib%s, which install.sh does not link\n' "$lib"
    rc=1
  fi
done

if [ "$rc" -ne 0 ]; then
  printf 'manifests: make the two manifests agree on %s\n' "$WANT" >&2
fi
exit "$rc"
