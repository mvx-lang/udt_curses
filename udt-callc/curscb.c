/* curses for MultiValue — Copyright (C) 2026 Gordon Heydon.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License, version 2, as
 * published by the Free Software Foundation.  There is NO WARRANTY, to
 * the extent permitted by law; see the LICENSE file for details.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 * curscb.c — ncurses bindings for UniData, reached through CallC.
 *
 * UniData's own terminal handling is unreliable over modern Unix
 * terminals (xterm/tmux/ssh); ncurses is not.  These wrappers are
 * compiled into libu2callc.so and declared in cfuncdef, so BASIC can
 * drive a full-screen ncurses session and — the point of the exercise —
 * read keys by logical NAME the way MVX's KEYIN() does, with colour,
 * cursor control and mouse to match MVX's COLOR()/@(...)/MOUSE().
 *
 * CallC convention (see the git bindings alongside these): every
 * argument and every return value is a string (char *).  Integers travel
 * as decimal text and are parsed here; a string return of short ASCII
 * marshals reliably (unlike binary, which strlen would truncate — so the
 * key NAME is returned, never a raw byte).  Each function takes exactly
 * one char* argument even when it ignores it, because a zero-argument
 * CallC entry is awkward to declare; unused args are named `a`.
 */

#include <curses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Scratch for string returns.  A CallC return is copied out immediately by
 * the caller, so a single static buffer per return is safe (BASIC is
 * single-threaded through the InterCall/CallC path). */
static char g_ret[128];

/* Last mouse event, decoded by CURSKEY when it sees KEY_MOUSE and read back
 * by CURSMOUSE — mirrors MVX, where KEYIN() yields "MOUSE" and MOUSE()
 * returns col/row/button/event. */
static int  g_m_col = 0, g_m_row = 0;
static char g_m_btn[8] = "NONE";   /* LEFT / MIDDLE / RIGHT / NONE */
static char g_m_evt[8] = "";       /* DOWN / UP / DRAG / CLICK / MOVE / WHEELUP / WHEELDN */
static int  g_m_down = 0;          /* a button is currently held (to tell DRAG from MOVE) */

/* ---- capability probe ------------------------------------------------ *
 * Safe to call without a terminal: returns the ncurses version string,
 * e.g. "ncurses 6.1.20180224".  Used by the installer's self-test to
 * confirm the bridge loaded before it writes the availability marker. */
char *CURSVER(char *a)
{
	(void)a;
	const char *v = curses_version();
	snprintf(g_ret, sizeof g_ret, "%s", v ? v : "");
	return g_ret;
}

/* ---- colour ---------------------------------------------------------- *
 * Colour pairs are allocated on demand and cached, so we never exceed the
 * terminal's COLOR_PAIRS and callers name colours, not pair numbers.  A
 * default (terminal) background is fg/bg = -1 via use_default_colors(). */
static short g_pair[81];           /* cache keyed by (fg+1)*9+(bg+1), fg/bg in -1..7 */
static int   g_npair = 0;

static int color_of(const char *n)
{
	if (!strcmp(n, "BLACK"))   return COLOR_BLACK;
	if (!strcmp(n, "RED"))     return COLOR_RED;
	if (!strcmp(n, "GREEN"))   return COLOR_GREEN;
	if (!strcmp(n, "YELLOW"))  return COLOR_YELLOW;
	if (!strcmp(n, "BLUE"))    return COLOR_BLUE;
	if (!strcmp(n, "MAGENTA")) return COLOR_MAGENTA;
	if (!strcmp(n, "CYAN"))    return COLOR_CYAN;
	if (!strcmp(n, "WHITE"))   return COLOR_WHITE;
	return -1;                 /* unknown -> default */
}

static short pair_for(int fg, int bg)
{
	int key = (fg + 1) * 9 + (bg + 1);
	if (key < 0 || key >= (int)(sizeof g_pair / sizeof g_pair[0])) return 0;
	if (g_pair[key]) return g_pair[key];
	if (g_npair + 1 >= COLOR_PAIRS) return 0;   /* out of pairs -> default */
	g_npair++;
	init_pair((short)g_npair, (short)fg, (short)bg);
	g_pair[key] = (short)g_npair;
	return g_pair[key];
}

/* Parse a colour spec — "GREEN", "WHITE BLUE" (fg bg), "BRIGHT GREEN",
 * "OFF"/"NORMAL"/"" — into a curses attribute. */
static chtype attr_of(const char *spec)
{
	char buf[64], *tok, *save = NULL;
	int fg = -1, bg = -1, seen = 0, bold = 0;

	if (!spec || !*spec) return A_NORMAL;
	snprintf(buf, sizeof buf, "%s", spec);
	for (char *p = buf; *p; p++) *p = (char)toupper((unsigned char)*p);
	if (!strcmp(buf, "OFF") || !strcmp(buf, "NORMAL")) return A_NORMAL;

	for (tok = strtok_r(buf, " ", &save); tok; tok = strtok_r(NULL, " ", &save)) {
		if (!strcmp(tok, "BRIGHT") || !strcmp(tok, "BOLD")) { bold = 1; continue; }
		if (seen == 0)      { fg = color_of(tok); seen = 1; }
		else if (seen == 1) { bg = color_of(tok); seen = 2; }
	}
	return COLOR_PAIR(pair_for(fg, bg)) | (bold ? A_BOLD : 0);
}

/* CURSCOLOR("GREEN") / "WHITE BLUE" (fg bg) / "BRIGHT GREEN" / "OFF".
 * Sets the attributes used by subsequent CURSADDSTR — like MVX COLOR(). */
char *CURSCOLOR(char *spec)
{
	attrset(attr_of(spec));
	return "";
}

/* Set the screen background (colour used to fill on clear, and behind text
 * with no explicit colour) — like MVX's back-colour-erase, e.g. a full blue
 * field.  Takes the same spec as CURSCOLOR. */
char *CURSBKGD(char *spec)
{
	bkgd(' ' | attr_of(spec));
	return "";
}

/* ---- screen lifecycle ------------------------------------------------ */

/* Enter curses mode: character-at-a-time, no echo, keypad decoding (so the
 * arrows/function keys arrive as KEY_* rather than raw escape sequences),
 * mouse reporting, and colour if the terminal has it.  nonl() keeps Enter
 * distinct from newline. */
char *CURSINIT(char *a)
{
	(void)a;
	initscr();
	cbreak();
	noecho();
	nonl();
	keypad(stdscr, TRUE);
	mousemask(ALL_MOUSE_EVENTS | REPORT_MOUSE_POSITION, NULL);
	if (has_colors()) {
		start_color();
		use_default_colors();
	}
	g_npair = 0;
	memset(g_pair, 0, sizeof g_pair);
	refresh();
	return "";
}

/* Leave curses mode and restore the terminal.  Idempotent enough — a
 * second endwin() is harmless. */
char *CURSEND(char *a)
{
	(void)a;
	endwin();
	return "";
}

/* "rows<space>cols" of the current screen, so BASIC can lay out without
 * hard-coding 24x80. */
char *CURSDIM(char *a)
{
	(void)a;
	snprintf(g_ret, sizeof g_ret, "%d %d", LINES, COLS);
	return g_ret;
}

/* Cursor visibility: "0" hide, "1" normal, "2" very visible (block). */
char *CURSCURSOR(char *n)
{
	curs_set(n ? atoi(n) : 1);
	return "";
}

/* ---- output ---------------------------------------------------------- */

/* Move the cursor.  Argument is "row col" (0-based, curses convention). */
char *CURSMOVE(char *rc)
{
	int y = 0, x = 0;
	if (rc)
		sscanf(rc, "%d %d", &y, &x);
	move(y, x);
	return "";
}

/* Write text at the cursor. */
char *CURSADDSTR(char *s)
{
	addstr(s ? s : "");
	return "";
}

/* Clear the screen (deferred until the next refresh). */
char *CURSCLEAR(char *a)
{
	(void)a;
	clear();
	return "";
}

/* Clear from the cursor to the end of the line — like MVX's @(-4). */
char *CURSCLREOL(char *a)
{
	(void)a;
	clrtoeol();
	return "";
}

/* Flush buffered output to the terminal. */
char *CURSREFRESH(char *a)
{
	(void)a;
	refresh();
	return "";
}

/* ---- input ----------------------------------------------------------- */

/* Set the read timeout for CURSKEY, in milliseconds: a non-negative value
 * waits up to that long and then yields "" (no key); "-1" blocks until a key
 * arrives.  Mirrors MVX's timed KEYIN and keeps a poll loop from spinning. */
char *CURSTIMEOUT(char *ms)
{
	timeout(ms ? atoi(ms) : -1);
	return "";
}

/* One decoded keystroke as a logical NAME, matching MVX's KEYIN():
 *   - printable ASCII returns as itself ("a", "Z", "7", " ");
 *   - named specials return their name (UP, F3, ENTER, ESC, ...);
 *   - a mouse event returns "MOUSE"; the details are then read with
 *     CURSMOUSE, exactly as MVX pairs KEYIN()=="MOUSE" with MOUSE().
 * An empty return means "no key" (ERR / timeout). */
static void set_ret(const char *s) { snprintf(g_ret, sizeof g_ret, "%s", s); }

char *CURSKEY(char *a)
{
	(void)a;
	int c = getch();

	if (c >= KEY_F(1) && c <= KEY_F(12)) {
		snprintf(g_ret, sizeof g_ret, "F%d", c - KEY_F(0));
		return g_ret;
	}

	switch (c) {
	case ERR:              g_ret[0] = 0;            break;
	case KEY_UP:           set_ret("UP");           break;
	case KEY_DOWN:         set_ret("DOWN");         break;
	case KEY_LEFT:         set_ret("LEFT");         break;
	case KEY_RIGHT:        set_ret("RIGHT");        break;
	case KEY_HOME:         set_ret("HOME");         break;
	case KEY_END:          set_ret("END");          break;
	case KEY_NPAGE:        set_ret("PGDN");         break;
	case KEY_PPAGE:        set_ret("PGUP");         break;
	case KEY_IC:           set_ret("INS");          break;
	case KEY_DC:           set_ret("DEL");          break;
	case KEY_BACKSPACE:
	case 8: case 127:      set_ret("BS");           break;
	case KEY_BTAB:         set_ret("BTAB");         break;
	case '\t':             set_ret("TAB");          break;
	case '\r': case '\n':
	case KEY_ENTER:        set_ret("ENTER");        break;
	case 27:               set_ret("ESC");          break;
	case KEY_MOUSE: {
		MEVENT ev;
		set_ret("MOUSE");
		if (getmouse(&ev) == OK) {
			g_m_col = ev.x + 1;   /* 1-based for BASIC, like MVX */
			g_m_row = ev.y + 1;
			if      (ev.bstate & (BUTTON1_PRESSED|BUTTON1_RELEASED|BUTTON1_CLICKED)) strcpy(g_m_btn, "LEFT");
			else if (ev.bstate & (BUTTON2_PRESSED|BUTTON2_RELEASED|BUTTON2_CLICKED)) strcpy(g_m_btn, "MIDDLE");
			else if (ev.bstate & (BUTTON3_PRESSED|BUTTON3_RELEASED|BUTTON3_CLICKED)) strcpy(g_m_btn, "RIGHT");

			if      (ev.bstate & (BUTTON1_PRESSED|BUTTON2_PRESSED|BUTTON3_PRESSED))    { strcpy(g_m_evt, "DOWN"); g_m_down = 1; }
			else if (ev.bstate & (BUTTON1_RELEASED|BUTTON2_RELEASED|BUTTON3_RELEASED)) { strcpy(g_m_evt, "UP");   g_m_down = 0; }
			else if (ev.bstate & (BUTTON1_CLICKED|BUTTON2_CLICKED|BUTTON3_CLICKED))    strcpy(g_m_evt, "CLICK");
			else if (ev.bstate & BUTTON4_PRESSED)  strcpy(g_m_evt, "WHEELUP");
			else if (ev.bstate & BUTTON5_PRESSED)  strcpy(g_m_evt, "WHEELDN");
			else { strcpy(g_m_evt, g_m_down ? "DRAG" : "MOVE"); if (!g_m_down) strcpy(g_m_btn, "NONE"); }
		}
		break;
	}
	default:
		if (c >= 32 && c < 127) {         /* printable ASCII */
			g_ret[0] = (char)c;
			g_ret[1] = 0;
		} else {                          /* anything else: raw code */
			snprintf(g_ret, sizeof g_ret, "%d", c);
		}
	}
	return g_ret;
}

/* The last mouse event seen by CURSKEY, as "col<VM>row<VM>button<VM>event"
 * (VM = CHAR(253)) — matching MVX's MOUSE(): button is LEFT/MIDDLE/RIGHT/
 * NONE, event is DOWN/UP/DRAG/CLICK/MOVE/WHEELUP/WHEELDN. */
char *CURSMOUSE(char *a)
{
	(void)a;
	snprintf(g_ret, sizeof g_ret, "%d\xFD%d\xFD%s\xFD%s",
	         g_m_col, g_m_row, g_m_btn, g_m_evt);
	return g_ret;
}
