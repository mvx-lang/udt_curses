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
| `CALLC CURSCURSOR("0")` | cursor visibility (`"0"` hide, `"1"` normal) |
| `CALLC CURSCOLOR(spec)` | text colour — `"GREEN"`, `"WHITE BLUE"`, `"BRIGHT GREEN"`, `"OFF"` |
| `CALLC CURSBKGD(spec)` | screen background (back-colour-erase) |
| `CALLC CURSMOVE("r c")` | move the cursor (0-based) |
| `CALLC CURSADDSTR(t)` | write text at the cursor |
| `CALLC CURSCLEAR("")` / `CURSCLREOL("")` / `CURSREFRESH("")` | clear screen / clear to EOL / flush |
| `CALLC CURSTIMEOUT("ms")` | read timeout for the next key (`"-1"` blocks) |
| `CALLC CURSKEY("")` | one keystroke, as a **logical name** |
| `CALLC CURSMOUSE("")` | last mouse event: `col : @VM : row : @VM : button : @VM : event` |

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

## Demos

`DEMO.BP/` holds the MVX terminal demos ported to the curses API — the same
programs, with `KEYIN()`/`@(x,y)`/`COLOR()`/`MOUSE()` swapped for the
`CALLC CURS…` calls:

- **[SNAKE](DEMO.BP/SNAKE)** — arrows steer, food grows and speeds the
  snake, walls or your tail end it. Timed `CURSKEY`, colour, dynamic-array
  body.
- **[FSDEMO](DEMO.BP/FSDEMO)** — Midnight-Commander dress: cyan menu bar,
  blue field, function-key bar. Exercises HOME/END/PGUP/PGDN and colour.
- **[MOUSE-DEMO](DEMO.BP/MOUSE-DEMO)** — click or drag to draw, coloured by
  button; the status line echoes col/row/button/event.

```
:CREATE.FILE DIR DEMO.BP
:BASIC DEMO.BP SNAKE
:RUN DEMO.BP SNAKE
```

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

UniData loads exactly one `libu2callc.so`, so native add-ons cannot each
own it — they are aggregated. `install.sh` stages this package's
contribution (`udt-callc/`) into `$UDTHOME/callc.d/curses/` and then
rebuilds the shared library from **every** contribution present, so
installing curses never clobbers another add-on (e.g. the git bridge) and
removing `callc.d/curses` + rebuilding drops it cleanly. The package
manager ([mv_package](https://github.com/mvx-lang/mv_package)) does the
same staging and rebuild when it installs the package — this script is the
standalone path.

## How it works

`udt-callc/curscb.c` wraps ncurses (`initscr`, `getch` with `keypad`,
`getmouse`, …) as CallC functions. UniData's CallC marshals every
argument and return value as a string, so integers travel as text and
`CURSKEY` returns the decoded key *name* rather than a raw byte (binary
would be truncated at the first NUL). `keypad(TRUE)` makes ncurses
assemble terminal escape sequences into named keys using the terminfo
database, which is why decoding is correct across terminal types where
UniData's built-in handling is not.

## Layout

```
udt-callc/curscb.c  the ncurses CallC bridge (C)
udt-callc/funcs     this package's cfuncdef fragment (its CallC declarations)
install.sh          stage udt-callc/ into $UDTHOME/callc.d and rebuild the lib
BP/CALLC.EXISTS     generic "is this CallC function registered?" probe
BP/CURSES.AVAIL     "is udt_curses installed?" (wraps CALLC.EXISTS)
BP/CURSES.INS       $INCLUDE: DEFFUN declarations + the API reference
BP/CURSES.DEMO      worked example: probe, then a live key/mouse screen
DEMO.BP/            the MVX terminal demos ported: SNAKE, FSDEMO, MOUSE-DEMO
PKG                 package descriptor (mv-package)
```

The `udt-callc/` directory is the package's native contribution in the
form mv_package's UniData builder consumes: C sources (or pre-built
objects for a binary release), a `funcs` cfuncdef fragment, and an
optional `libs` line of extra linker flags.

## Status

Proven on UniData 8.3.2 TE: screen output, `KEYIN`-by-name
(`a UP ENTER TAB PGUP F1 HOME q`), mouse (`col:row:evt`), timed reads,
and coexistence with the git CallC bridge in the same library.

## Licence

GPL-2.0-only. Copyright (C) 2026 Gordon Heydon.
