/*
 * ext/curses/curses.c
 * 
 * by MAEDA Shugo (ender@pic-internet.or.jp)
 * modified by Yukihiro Matsumoto (matz@netlab.co.jp)
 */

#ifdef HAVE_NCURSES_H
# include <ncurses.h>
#else
# ifdef HAVE_NCURSES_CURSES_H
#  include <ncurses/curses.h>
#else
# ifdef HAVE_CURSES_COLR_CURSES_H
#  include <varargs.h>
#  include <curses_colr/curses.h>
# else
#  include <curses.h>
#  if (defined(__bsdi__) || defined(__NetBSD__) || defined(__APPLE__) ) && !defined(_maxx)
#   define _maxx maxx
#  endif
#  if (defined(__bsdi__) || defined(__NetBSD__) || defined(__APPLE__)) && !defined(_maxy)
#   define _maxy maxy
#  endif
#  if (defined(__bsdi__) || defined(__NetBSD__) || defined(__APPLE__)) && !defined(_begx)
#   define _begx begx
#  endif
#  if (defined(__bsdi__) || defined(__NetBSD__) || defined(__APPLE__)) && !defined(_begy)
#   define _begy begy
#  endif
# endif
#endif
#endif

#include "stdio.h"
#include "ruby.h"
#include "rubyio.h"

static VALUE mCurses;
static VALUE cWindow;

VALUE rb_stdscr;

struct windata {
    WINDOW *window;
};

static void
no_window()
{
    rb_raise(rb_eRuntimeError, "already closed window");
}

#define GetWINDOW(obj, winp) {\
    Data_Get_Struct(obj, struct windata, winp);\
    if (winp->window == 0) no_window();\
}

#define CHECK(c) c

static void
free_window(winp)
    struct windata *winp;
{
    if (winp->window && winp->window != stdscr) delwin(winp->window);
    winp->window = 0;
    free(winp);
}

static VALUE
prep_window(class, window)
    VALUE class;
    WINDOW *window;
{
    VALUE obj;
    struct windata *winp;

    if (window == NULL) {
	rb_raise(rb_eRuntimeError, "failed to create window");
    }

    obj = Data_Make_Struct(class, struct windata, 0, free_window, winp);
    winp->window = window;
    
    return obj;    
}

/*-------------------------- module Curses --------------------------*/

/* def init_screen */
static VALUE
curses_init_screen()
{
    initscr();
    if (stdscr == 0) {
	rb_raise(rb_eRuntimeError, "cannot initialize curses");
    }
    clear();
    rb_stdscr = prep_window(cWindow, stdscr);
    return Qnil;
}

/* def stdscr */
static VALUE
curses_stdscr()
{
    if (rb_stdscr == 0) curses_init_screen();
    return rb_stdscr;
}

/* def close_screen */
static VALUE
curses_close_screen()
{
#ifdef HAVE_ISENDWIN
    if (!isendwin())
#endif
	endwin();
    return Qnil;
}

static void
curses_finalize()
{
    if (stdscr
#ifdef HAVE_ISENDWIN
	&& !isendwin()
#endif
	)
	endwin();
}

/* def closed? */
static VALUE
curses_closed()
{
#ifdef HAVE_ISENDWIN
    if (isendwin()) {
	return Qtrue;
    }
    return Qfalse;
#else
    rb_notimplement();
#endif
}

/* def clear */
static VALUE
curses_clear(obj)
    VALUE obj;
{
    wclear(stdscr);
    return Qnil;
}

/* def refresh */
static VALUE
curses_refresh(obj)
    VALUE obj;
{
    refresh();
    return Qnil;
}

/* def doupdate */
static VALUE
curses_doupdate(obj)
    VALUE obj;
{
#ifdef HAVE_DOUPDATE
    doupdate();
#else
    refresh();
#endif
    return Qnil;
}

/* def echo */
static VALUE
curses_echo(obj)
    VALUE obj;
{
    echo();
    return Qnil;
}

/* def noecho */
static VALUE
curses_noecho(obj)
    VALUE obj;
{
    noecho();
    return Qnil;
}

/* def raw */
static VALUE
curses_raw(obj)
    VALUE obj;
{
    raw();
    return Qnil;
}

/* def noraw */
static VALUE
curses_noraw(obj)
    VALUE obj;
{
    noraw();
    return Qnil;
}

/* def cbreak */
static VALUE
curses_cbreak(obj)
    VALUE obj;
{
    cbreak();
    return Qnil;
}

/* def nocbreak */
static VALUE
curses_nocbreak(obj)
    VALUE obj;
{
    nocbreak();
    return Qnil;
}

/* def nl */
static VALUE
curses_nl(obj)
    VALUE obj;
{
    nl();
    return Qnil;
}

/* def nonl */
static VALUE
curses_nonl(obj)
    VALUE obj;
{
    nonl();
    return Qnil;
}

/* def beep */
static VALUE
curses_beep(obj)
    VALUE obj;
{
#ifdef HAVE_BEEP
    beep();
#endif
    return Qnil;
}

/* def flash */
static VALUE
curses_flash(obj)
    VALUE obj;
{
#ifdef HAVE_FLASH
    flash();
#endif
    return Qnil;
}

/* def ungetch */
static VALUE
curses_ungetch(obj, ch)
    VALUE obj;
    VALUE ch;
{
#ifdef HAVE_UNGETCH
    ungetch(NUM2INT(ch));
#else
    rb_notimplement();
#endif
    return Qnil;
}

/* def setpos(y, x) */
static VALUE
curses_setpos(obj, y, x)
    VALUE obj;
    VALUE y;
    VALUE x;
{
    move(NUM2INT(y), NUM2INT(x));
    return Qnil;
}

/* def standout */
static VALUE
curses_standout(obj)
    VALUE obj;
{
    standout();
    return Qnil;
}

/* def standend */
static VALUE
curses_standend(obj)
    VALUE obj;
{
    standend();
    return Qnil;
}

/* def inch */
static VALUE
curses_inch(obj)
    VALUE obj;
{
    return CHR2FIX(inch());
}

/* def addch(ch) */
static VALUE
curses_addch(obj, ch)
    VALUE obj;
    VALUE ch;
{
    addch(NUM2CHR(ch));
    return Qnil;
}

/* def insch(ch) */
static VALUE
curses_insch(obj, ch)
    VALUE obj;
    VALUE ch;
{
    insch(NUM2CHR(ch));
    return Qnil;
}

/* def addstr(str) */
static VALUE
curses_addstr(obj, str)
    VALUE obj;
    VALUE str;
{
    if (!NIL_P(str)) {
	addstr(STR2CSTR(str));
    }
    return Qnil;
}

/* def getch */
static VALUE
curses_getch(obj)
    VALUE obj;
{
    rb_read_check(stdin);
    return CHR2FIX(getch());
}

/* def getstr */
static VALUE
curses_getstr(obj)
    VALUE obj;
{
    char rtn[1024]; /* This should be big enough.. I hope */

    rb_read_check(stdin);
    getstr(rtn);
    return rb_tainted_str_new2(rtn);
}

/* def delch */
static VALUE
curses_delch(obj)
    VALUE obj;
{
    delch();
    return Qnil;
}

/* def delelteln */
static VALUE
curses_deleteln(obj)
    VALUE obj;
{
#ifdef HAVE_DELETELN
    deleteln();
#endif
    return Qnil;
}

static VALUE
curses_lines()
{
    return INT2FIX(LINES);
}

static VALUE
curses_cols()
{
    return INT2FIX(COLS);
}

/*-------------------------- class Window --------------------------*/

/* def new(h, w, top, left) */
static VALUE
window_s_new(class, h, w, top, left)
    VALUE class;
    VALUE h;
    VALUE w;
    VALUE top;
    VALUE left;
{
    VALUE win;
    WINDOW *window;
    VALUE args[4];
    
    window = newwin(NUM2INT(h), NUM2INT(w), NUM2INT(top), NUM2INT(left));
    wclear(window);
    win = prep_window(class, window);
    args[0] = h; args[1] = w; args[2] = top; args[3] = left;

    return win;
}

/* def subwin(h, w, top, left) */
static VALUE
window_subwin(obj, h, w, top, left)
    VALUE obj;
    VALUE h;
    VALUE w;
    VALUE top;
    VALUE left;
{
    struct windata *winp;
    WINDOW *window;
    VALUE win;
    VALUE args[4];

    GetWINDOW(obj, winp);
    window = subwin(winp->window, NUM2INT(h), NUM2INT(w),
		                  NUM2INT(top), NUM2INT(left));
    win = prep_window(cWindow, window);
    args[0] = h; args[1] = w; args[2] = top; args[3] = left;

    return win;
}

/* def close */
static VALUE
window_close(obj)
    VALUE obj;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    delwin(winp->window);
    winp->window = 0;

    return Qnil;
}

/* def clear */
static VALUE
window_clear(obj)
    VALUE obj;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    wclear(winp->window);
    
    return Qnil;
}

/* def refresh */
static VALUE
window_refresh(obj)
    VALUE obj;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    wrefresh(winp->window);
    
    return Qnil;
}

/* def box(vert, hor) */
static VALUE
window_box(obj, vert, hor)
    VALUE obj;
    VALUE vert;
    VALUE hor;
{
    struct windata *winp; 
   
    GetWINDOW(obj, winp);
    box(winp->window, NUM2CHR(vert), NUM2CHR(hor));
    
    return Qnil;
}


/* def move(y, x) */
static VALUE
window_move(obj, y, x)
    VALUE obj;
    VALUE y;
    VALUE x;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    mvwin(winp->window, NUM2INT(y), NUM2INT(x));

    return Qnil;
}

/* def setpos(y, x) */
static VALUE
window_setpos(obj, y, x)
    VALUE obj;
    VALUE y;
    VALUE x;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    wmove(winp->window, NUM2INT(y), NUM2INT(x));
    return Qnil;
}

/* def cury */
static VALUE
window_cury(obj)
    VALUE obj;
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
    getyx(winp->window, y, x);
    return INT2FIX(y);
}

/* def curx */
static VALUE
window_curx(obj)
    VALUE obj;
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
    getyx(winp->window, y, x);
    return INT2FIX(x);
}

/* def maxy */
static VALUE
window_maxy(obj)
    VALUE obj;
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
#ifdef getmaxy
    return INT2FIX(getmaxy(winp->window));
#else
#ifdef getmaxyx
    getmaxyx(winp->window, y, x);
    return INT2FIX(y);
#else
    return INT2FIX(winp->window->_maxy+1);
#endif
#endif
}

/* def maxx */
static VALUE
window_maxx(obj)
    VALUE obj;
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
#ifdef getmaxx
    return INT2FIX(getmaxx(winp->window));
#else
#ifdef getmaxyx
    getmaxyx(winp->window, y, x);
    return INT2FIX(x);
#else
    return INT2FIX(winp->window->_maxx+1);
#endif
#endif
}

/* def begy */
static VALUE
window_begy(obj)
    VALUE obj;
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
#ifdef getbegyx
    getbegyx(winp->window, y, x);
    return INT2FIX(y);
#else
    return INT2FIX(winp->window->_begy);
#endif
}

/* def begx */
static VALUE
window_begx(obj)
    VALUE obj;
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
#ifdef getbegyx
    getbegyx(winp->window, y, x);
    return INT2FIX(x);
#else
    return INT2FIX(winp->window->_begx);
#endif
}

/* def standout */
static VALUE
window_standout(obj)
    VALUE obj;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    wstandout(winp->window);
    return Qnil;
}

/* def standend */
static VALUE
window_standend(obj)
    VALUE obj;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    wstandend(winp->window);
    return Qnil;
}

/* def inch */
static VALUE
window_inch(obj)
    VALUE obj;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    return CHR2FIX(winch(winp->window));
}

/* def addch(ch) */
static VALUE
window_addch(obj, ch)
    VALUE obj;
    VALUE ch;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    waddch(winp->window, NUM2CHR(ch));
    
    return Qnil;
}

/* def insch(ch) */
static VALUE
window_insch(obj, ch)
    VALUE obj;
    VALUE ch;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    winsch(winp->window, NUM2CHR(ch));
    
    return Qnil;
}

/* def addstr(str) */
static VALUE
window_addstr(obj, str)
    VALUE obj;
    VALUE str;
{
    if (!NIL_P(str)) {
	struct windata *winp;

	GetWINDOW(obj, winp);
	waddstr(winp->window, STR2CSTR(str));
    }
    return Qnil;
}

/* def <<(str) */
static VALUE
window_addstr2(obj, str)
    VALUE obj;
    VALUE str;
{
    window_addstr(obj, str);
    return obj;
}

/* def getch */
static VALUE
window_getch(obj)
    VALUE obj;
{
    struct windata *winp;
    
    rb_read_check(stdin);
    GetWINDOW(obj, winp);
    return CHR2FIX(wgetch(winp->window));
}

/* def getstr */
static VALUE
window_getstr(obj)
    VALUE obj;
{
    struct windata *winp;
    char rtn[1024]; /* This should be big enough.. I hope */
    
    GetWINDOW(obj, winp);
    rb_read_check(stdin);
    wgetstr(winp->window, rtn);
    return rb_tainted_str_new2(rtn);
}

/* def delch */
static VALUE
window_delch(obj)
    VALUE obj;
{
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    wdelch(winp->window);
    return Qnil;
}

/* def delelteln */
static VALUE
window_deleteln(obj)
    VALUE obj;
{
#ifdef HAVE_WDELETELN
    struct windata *winp;
    
    GetWINDOW(obj, winp);
    wdeleteln(winp->window);
#endif
    return Qnil;
}

/*------------------------- Initialization -------------------------*/
void
Init_curses()
{
    mCurses = rb_define_module("Curses");
    rb_define_module_function(mCurses, "init_screen", curses_init_screen, 0);
    rb_define_module_function(mCurses, "close_screen", curses_close_screen, 0);
    rb_define_module_function(mCurses, "closed?", curses_closed, 0);
    rb_define_module_function(mCurses, "stdscr", curses_stdscr, 0);
    rb_define_module_function(mCurses, "refresh", curses_refresh, 0);
    rb_define_module_function(mCurses, "doupdate", curses_doupdate, 0);
    rb_define_module_function(mCurses, "clear", curses_clear, 0);
    rb_define_module_function(mCurses, "echo", curses_echo, 0);
    rb_define_module_function(mCurses, "noecho", curses_noecho, 0);
    rb_define_module_function(mCurses, "raw", curses_raw, 0);
    rb_define_module_function(mCurses, "noraw", curses_noraw, 0);
    rb_define_module_function(mCurses, "cbreak", curses_cbreak, 0);
    rb_define_module_function(mCurses, "nocbreak", curses_nocbreak, 0);
    rb_define_alias(mCurses, "crmode", "cbreak");
    rb_define_alias(mCurses, "nocrmode", "nocbreak");
    rb_define_module_function(mCurses, "nl", curses_nl, 0);
    rb_define_module_function(mCurses, "nonl", curses_nonl, 0);
    rb_define_module_function(mCurses, "beep", curses_beep, 0);
    rb_define_module_function(mCurses, "flash", curses_flash, 0);
    rb_define_module_function(mCurses, "ungetch", curses_ungetch, 1);
    rb_define_module_function(mCurses, "setpos", curses_setpos, 2);
    rb_define_module_function(mCurses, "standout", curses_standout, 0);
    rb_define_module_function(mCurses, "standend", curses_standend, 0);
    rb_define_module_function(mCurses, "inch", curses_inch, 0);
    rb_define_module_function(mCurses, "addch", curses_addch, 1);
    rb_define_module_function(mCurses, "insch", curses_insch, 1);
    rb_define_module_function(mCurses, "addstr", curses_addstr, 1);
    rb_define_module_function(mCurses, "getch", curses_getch, 0);
    rb_define_module_function(mCurses, "getstr", curses_getstr, 0);
    rb_define_module_function(mCurses, "delch", curses_delch, 0);
    rb_define_module_function(mCurses, "deleteln", curses_deleteln, 0);
    rb_define_module_function(mCurses, "lines", curses_lines, 0);
    rb_define_module_function(mCurses, "cols", curses_cols, 0);
    
    cWindow = rb_define_class_under(mCurses, "Window", rb_cObject);
    rb_define_singleton_method(cWindow, "new", window_s_new, 4);
    rb_define_method(cWindow, "subwin", window_subwin, 4);
    rb_define_method(cWindow, "close", window_close, 0);
    rb_define_method(cWindow, "clear", window_clear, 0);
    rb_define_method(cWindow, "refresh", window_refresh, 0);
    rb_define_method(cWindow, "box", window_box, 2);
    rb_define_method(cWindow, "move", window_move, 2);
    rb_define_method(cWindow, "setpos", window_setpos, 2);
    rb_define_method(cWindow, "cury", window_cury, 0);
    rb_define_method(cWindow, "curx", window_curx, 0);
    rb_define_method(cWindow, "maxy", window_maxy, 0);
    rb_define_method(cWindow, "maxx", window_maxx, 0);
    rb_define_method(cWindow, "begy", window_begy, 0);
    rb_define_method(cWindow, "begx", window_begx, 0);
    rb_define_method(cWindow, "standout", window_standout, 0);
    rb_define_method(cWindow, "standend", window_standend, 0);
    rb_define_method(cWindow, "inch", window_inch, 0);
    rb_define_method(cWindow, "addch", window_addch, 1);
    rb_define_method(cWindow, "insch", window_insch, 1);
    rb_define_method(cWindow, "addstr", window_addstr, 1);
    rb_define_method(cWindow, "<<", window_addstr2, 1);
    rb_define_method(cWindow, "getch", window_getch, 0);
    rb_define_method(cWindow, "getstr", window_getstr, 0);
    rb_define_method(cWindow, "delch", window_delch, 0);
    rb_define_method(cWindow, "deleteln", window_deleteln, 0);

    rb_set_end_proc(curses_finalize, 0);
}
