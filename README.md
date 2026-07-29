# udt_curses

ncurses terminal handling for Rocket UniData, reached from UniBasic
through CallC — so full-screen programs (editors like EB, menus, data
entry) get reliable key and mouse handling over xterm / tmux / ssh
instead of UniData's own flaky terminal layer.

It brings MVX's input model to UniData: **`KEYIN()` returns keys by
name** — `UP`, `F3`, `ENTER`, `PGUP`, `HOME`, … — and **mouse events**
arrive as coordinates, matching MVX's `KEYIN()` / `MOUSE()`.

> UniData only, for now. The bridge is native ncurses compiled into
> UniData's CallC library; there is nothing to install on MVX, which has
> `KEYIN()` and `MOUSE()` built in.

## What you get

A handful of CallC entry points, driven from BASIC:

| Call | Purpose |
|------|---------|
| `CALLC CURSINIT("")` | enter curses mode (raw keys, no echo, mouse on) |
| `CALLC CURSEND("")` | leave curses mode, restore the terminal |
| `CALLC CURSDIM("")` | `"rows cols"` of the screen |
| `CALLC CURSMOVE("r c")` | move the cursor (0-based) |
| `CALLC CURSADDSTR(t)` | write text at the cursor |
| `CALLC CURSCLEAR("")` / `CURSREFRESH("")` | clear / flush |
| `CALLC CURSTIMEOUT("ms")` | read timeout for the next key (`"-1"` blocks) |
| `CALLC CURSKEY("")` | one keystroke, as a **logical name** |
| `CALLC CURSMOUSE("")` | last mouse event: `col : @VM : row : @VM : evt` |

`CURSKEY` returns printable characters as themselves and named keys as
`UP DOWN LEFT RIGHT HOME END PGUP PGDN INS DEL BS TAB BTAB ENTER ESC
F1..F12 MOUSE` — the same vocabulary as MVX.

## Is it installed? — optional-capability check

The bridge is a native add-on that may or may not be present. A program
should ask before using it, and fall back cleanly when it is absent:

```basic
   $INCLUDE BP CURSES.INS
   IF CURSES.AVAIL("") THEN
      GOSUB FULLSCREEN.UI          ;* ncurses is here — use it
   END ELSE
      GOSUB PLAIN.UI               ;* runs on any account
   END
```

`CURSES.AVAIL()` is built on the generic **`CALLC.EXISTS(name)`**, which
reports whether *any* CallC function is registered — **without invoking
it** (a CallC to an unregistered function aborts the whole program, so a
live probe is impossible). It reads the canonical CallC definition the
installer maintains, so it answers correctly even on an account where
udt_curses was never installed. This primitive is general enough that it
belongs in the package manager, available to every installed package.

See [`BP/CURSES.DEMO`](BP/CURSES.DEMO) for a complete probe-then-drive
example.

## Install

Needs `gcc`, `ncurses-devel`, and a UniData whose `$UDTHOME/bin/work`
holds the standard CallC generators and link recipe.

```sh
export UDTHOME=/usr/ud83        # your UniData home
./install.sh                    # builds curscb.c into libu2callc.so
```

then catalog the BASIC API into each account that uses it:

```
:BASIC BP CALLC.EXISTS
:CATALOG BP CALLC.EXISTS LOCAL FORCE
:BASIC BP CURSES.AVAIL
:CATALOG BP CURSES.AVAIL LOCAL FORCE
```

The installer rebuilds the **shared** `libu2callc.so` that every UniData
session loads, preserving any other CallC add-ons whose objects are
already staged in the work directory (e.g. the git bridge). Coordinating
several packages' native objects into that one library is the package
manager's role; this script covers udt_curses on its own or beside
objects already present.

## How it works

`src/curscb.c` wraps ncurses (`initscr`, `getch` with `keypad`,
`getmouse`, …) as CallC functions. UniData's CallC marshals every
argument and return value as a string, so integers travel as text and
`CURSKEY` returns the decoded key *name* rather than a raw byte (binary
would be truncated at the first NUL). `keypad(TRUE)` makes ncurses
assemble terminal escape sequences into named keys using the terminfo
database, which is why decoding is correct across terminal types where
UniData's built-in handling is not.

## Layout

```
src/curscb.c     the ncurses CallC bridge (C)
install.sh       build + install into libu2callc.so
BP/CALLC.EXISTS  generic "is this CallC function registered?" probe
BP/CURSES.AVAIL  "is udt_curses installed?" (wraps CALLC.EXISTS)
BP/CURSES.INS    $INCLUDE: DEFFUN declarations + the API reference
BP/CURSES.DEMO   worked example: probe, then a live key/mouse screen
PKG              package descriptor (mv-package)
```

## Status

Proven on UniData 8.3.2 TE: screen output, `KEYIN`-by-name
(`a UP ENTER TAB PGUP F1 HOME q`), mouse (`col:row:evt`), timed reads,
and coexistence with the git CallC bridge in the same library.

## Licence

GPL-2.0-only. Copyright (C) 2026 Gordon Heydon.
