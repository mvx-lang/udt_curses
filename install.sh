#!/bin/sh
# udt_curses — install the ncurses CallC bridge into UniData.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only.
#
# Builds curscb.c into UniData's shared CallC library (libu2callc.so) and
# registers its functions in the canonical CallC definition, so BASIC can
# reach ncurses through `CALLC CURSINIT(...)` and friends.  Re-runnable:
# entries already present are left alone.
#
# Needs: gcc, ncurses-devel, and the standard CallC generators
# (gencdef/genefs/genfunc, on PATH via $UDTHOME/bin) plus the definition
# files staged in $UDTHOME/bin/work.  Everything is built in a writable
# staging directory; only the finished library and the updated definition
# are copied into place, with sudo.
#
# This rebuilds the SYSTEM library that every UniData session loads.  Any
# other CallC add-ons (e.g. the git bridge) whose objects are staged in the
# work directory are carried through.  Coordinating several packages'
# native objects into one libu2callc.so is ultimately the package manager's
# job; this script covers udt_curses standing alone or beside objects
# already present in the work dir.
set -e

: "${UDTHOME:?set UDTHOME to your UniData home (e.g. /usr/ud83)}"
SUDO=${SUDO-sudo}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK="$UDTHOME/bin/work"           # UniData's CallC recipe + definitions (read-only to us)
LIB="$UDTHOME/bin/libu2callc.so"   # the shared library every session loads
BUILD="$HERE/.build"               # our writable staging directory

echo "udt_curses: building the ncurses bridge for UniData at $UDTHOME"
rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"

# --- gather inputs from the UniData work dir ----------------------------
cp "$WORK/cfuncdef" "$WORK/efsdef" "$WORK/libuvic.a" .

# --- compile the bridge -------------------------------------------------
gcc -m64 -fPIC -O2 -c "$HERE/src/curscb.c" -o curscb.o

# --- register the functions in cfuncdef (idempotent) --------------------
# Each entry is name:rettype:nargs:argtypes — every curses function is
# string(string).  Declarations go under $$FUN; the object under $$OBJ.
add_fun() {
	grep -q "^$1:" cfuncdef && return 0
	awk -v line="$1:string:1:string" \
	    '{ print } /^\$\$FUN/ && !d { print line; d=1 }' \
	    cfuncdef > cfuncdef.n && mv cfuncdef.n cfuncdef
}
for f in CURSVER CURSINIT CURSEND CURSDIM CURSMOVE CURSADDSTR \
         CURSCLEAR CURSREFRESH CURSTIMEOUT CURSKEY CURSMOUSE; do
	add_fun "$f"
done
if ! grep -q '^curscb.o$\|[[:space:]]curscb.o' cfuncdef; then
	awk '/^\$\$OBJ/ { print; print "curscb.o"; next } { print }' \
	    cfuncdef > cfuncdef.n && mv cfuncdef.n cfuncdef
fi

# --- stage any co-installed add-on objects named under $$OBJ ------------
OBJS=""
for o in $(awk '/^\$\$OBJ/{f=1;next} /^\$\$/{f=0} f{print}' cfuncdef); do
	[ "$o" = curscb.o ] && { OBJS="$OBJS curscb.o"; continue; }
	if [ -f "$WORK/$o" ]; then cp "$WORK/$o" .; OBJS="$OBJS $o"
	else echo "udt_curses: warning — $o named in cfuncdef but not staged in $WORK; skipping"; fi
done

# --- regenerate the dispatch/glue and compile ---------------------------
rm -f cdef
gencdef ; genefs ; genfunc
CF="-I$UDTHOME/bin/include -m64 -DUV_64PORT -DU2_64_BUILD -fPIC -DLINUX9 \
    -DU_LINUX -DU2_LINUX -DU_NO_POLL -DUNIDATAon -D_LARGEFILE64_SOURCE \
    -D_FILE_OFFSET_BITS=64 -DNDEBUG -O2"
for c in callcf interfunc efs_init funchead; do gcc $CF -c $c.c -o $c.o; done

# the standard UniData add-on libraries already include -lncurses; keep the
# git bridge's libraries when its objects are part of the build
GITLIBS=""
case "$OBJS" in *mvxgit.o*|*udtgit_rt.o*)
	GITLIBS="-Wl,-rpath,/usr/local/lib64 -L/usr/local/lib64 -lgit2" ;;
esac

# --- link ---------------------------------------------------------------
gcc -m64 -shared -fPIC -z muldefs $GITLIBS -L/lib64 -L/usr/lib64 \
    funchead.o interfunc.o callcf.o efs_init.o $OBJS libuvic.a \
    /lib64/libglib-2.0.so.0 -lm -lncurses -lrt /lib64/libcrypt.so.1 \
    /lib64/libgdbm.so.6 -ldl /lib64/libpam.so.0 \
    -o libu2callc.so

# --- install: the library, and the updated definition (the registry that
#     CALLC.EXISTS reads) -------------------------------------------------
$SUDO cp -p "$LIB" "$LIB.pre-curses" 2>/dev/null || true
$SUDO cp libu2callc.so "$LIB"
$SUDO cp cfuncdef "$WORK/cfuncdef"

echo "udt_curses: installed — $(nm -D "$LIB" | grep -c ' T CURS') curses functions live in $LIB"
echo "udt_curses: now catalog the BASIC API into each account that uses it:"
echo "    :BASIC BP CALLC.EXISTS ; CATALOG BP CALLC.EXISTS LOCAL FORCE"
echo "    :BASIC BP CURSES.AVAIL ; CATALOG BP CURSES.AVAIL LOCAL FORCE"
