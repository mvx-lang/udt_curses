#!/bin/sh
# udt_curses — build the ncurses CallC bridge and stage the UniData release.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
# Runs INSIDE the udt-builder container (see mv-package-registry/builder), at
# the repo root, driven by the udt-build action's build-release.sh.  It stages
# the release package (contents at the root of $1): the BASIC + manifest, plus
# the CallC bridge compiled to objects — the client links the .o without a
# compiler (MVPKG's CALLC op aggregates them into libu2callc.so), so the .c is
# dropped.  The action tars $1 as mvx-lang_curses-<ver>-udt-<os>-<arch>-<endian>.
set -e
STAGE="${1:?usage: build-udt.sh <stagedir>}"

# Copy the tree into the stage, minus VCS/CI metadata, the stage dir itself, and
# this build script (a tar pipe so the stage-in-tree does not recurse).
tar cf - --exclude=./.git --exclude=./.github --exclude=./dist --exclude=./build-udt.sh . \
  | ( cd "$STAGE" && tar xf - )

# Compile the CallC sources to position-independent objects and drop the source.
for c in "$STAGE"/udt-callc/*.c; do
  gcc -m64 -fPIC -O2 -c "$c" -o "${c%.c}.o"
  rm -f "$c"
done
