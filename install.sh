#!/bin/sh
# udt_curses — install the ncurses CallC bridge into UniData (standalone).
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only.
#
# Stages this package's CallC contribution (udt-callc/) into UniData's
# aggregation area and rebuilds the shared library from every contribution
# present, so installing curses never clobbers another add-on (e.g. the git
# bridge) already there — and removing udt-callc/curses + rebuilding drops
# it cleanly.  This is the standalone path; when the package manager
# (mv_package) is present it does the same staging and rebuild for you.
#
# Needs: gcc, ncurses-devel, and the UniData CallC generators
# (gencdef/genefs/genfunc, on PATH) with efsdef + libuvic.a staged in
# $UDTHOME/bin/work.
set -e

: "${UDTHOME:?set UDTHOME to your UniData home (e.g. /usr/ud83)}"
SUDO=${SUDO-sudo}
HERE=$(cd "$(dirname "$0")" && pwd)
CALLCD="$UDTHOME/callc.d"          # one subdir per contributing package
WORK="$UDTHOME/bin/work"
LIB="$UDTHOME/bin/libu2callc.so"

# --- stage this package's contribution ----------------------------------
echo "udt_curses: staging the ncurses contribution into $CALLCD/curses"
$SUDO mkdir -p "$CALLCD/curses"
$SUDO cp "$HERE/udt-callc/curscb.c" "$HERE/udt-callc/funcs" "$CALLCD/curses/"

# --- rebuild the shared library from the union of all contributions -----
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/udtcurses.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT
cd "$BUILD"
cp "$WORK/efsdef" "$WORK/libuvic.a" .

: > FUN ; : > OBJ ; : > LIBS ; OBJPATHS=""
for d in "$CALLCD"/*/ ; do
	[ -d "$d" ] || continue
	pkg=$(basename "$d")
	echo "udt_curses:   + $pkg"
	[ -f "$d/funcs" ] && cat "$d/funcs" >> FUN
	[ -f "$d/libs"  ] && cat "$d/libs"  >> LIBS
	for c in "$d"*.c ; do [ -f "$c" ] || continue
		o="$BUILD/${pkg}__$(basename "${c%.c}").o"
		gcc -m64 -fPIC -O2 -c "$c" -o "$o"; OBJPATHS="$OBJPATHS $o"; basename "$o" >> OBJ
	done
	for o in "$d"*.o ; do [ -f "$o" ] || continue
		OBJPATHS="$OBJPATHS $o"; basename "$o" >> OBJ
	done
done

{ echo '$$FUN'; cat FUN; echo '$$OBJ'; cat OBJ; echo '$$LIB'; } > cfuncdef
rm -f cdef
gencdef ; genefs ; genfunc
CF="-I$UDTHOME/bin/include -m64 -DUV_64PORT -DU2_64_BUILD -fPIC -DLINUX9 \
    -DU_LINUX -DU2_LINUX -DU_NO_POLL -DUNIDATAon -D_LARGEFILE64_SOURCE \
    -D_FILE_OFFSET_BITS=64 -DNDEBUG -O2"
for c in callcf interfunc efs_init funchead; do gcc $CF -c $c.c -o $c.o; done

$SUDO cp -p "$LIB" "$LIB.prev" 2>/dev/null || true
gcc -m64 -shared -fPIC -z muldefs $(tr '\n' ' ' < LIBS) -L/lib64 -L/usr/lib64 \
    funchead.o interfunc.o callcf.o efs_init.o $OBJPATHS libuvic.a \
    /lib64/libglib-2.0.so.0 -lm -lncurses -lrt /lib64/libcrypt.so.1 \
    /lib64/libgdbm.so.6 -ldl /lib64/libpam.so.0 \
    -o libu2callc.so
$SUDO cp libu2callc.so "$LIB"
$SUDO cp cfuncdef "$WORK/cfuncdef"

echo "udt_curses: installed — $(nm -D "$LIB" | grep -c ' T CURS') curses functions live."
echo "udt_curses: now catalog the BASIC API into each account that uses it:"
echo "    :BASIC BP CALLC.EXISTS ; CATALOG BP CALLC.EXISTS LOCAL FORCE"
echo "    :BASIC BP CURSES.AVAIL ; CATALOG BP CURSES.AVAIL LOCAL FORCE"
