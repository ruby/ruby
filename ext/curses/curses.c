/* -*- C -*-
 * $Id$
 *
 * ext/curses/curses.c
 *
 * by MAEDA Shugo (ender@pic-internet.or.jp)
 * modified by Yukihiro Matsumoto (matz@netlab.co.jp),
 *         Toki Yoshinori,
 *         Hitoshi Takahashi,
 *         and Takaaki Tateishi (ttate@kt.jaist.ac.jp)
 *
 * maintainers:
 * - Takaaki Tateishi (ttate@kt.jaist.ac.jp)
 */

#include "ruby.h"
#include "ruby/io.h"

#if defined(HAVE_NCURSES_H)
# include <ncurses.h>
#elif defined(HAVE_NCURSES_CURSES_H)
# include <ncurses/curses.h>
#elif defined(HAVE_CURSES_COLR_CURSES_H)
# ifdef HAVE_STDARG_PROTOTYPES
#  include <stdarg.h>
# else
#  include <varargs.h>
# endif
# include <curses_colr/curses.h>
#else
# include <curses.h>
# if defined(__bsdi__) || defined(__NetBSD__) || defined(__APPLE__)
#  if !defined(_maxx)
#  define _maxx maxx
#  endif
#  if !defined(_maxy)
#  define _maxy maxy
#  endif
#  if !defined(_begx)
#  define _begx begx
#  endif
#  if !defined(_begy)
#  define _begy begy
#  endif
# endif
#endif

#ifdef HAVE_INIT_COLOR
# define USE_COLOR 1
#endif

/* supports only ncurses mouse routines */
#ifdef NCURSES_MOUSE_VERSION
# define USE_MOUSE 1
#endif

#define NUM2CH NUM2CHR
#define CH2FIX CHR2FIX

static VALUE mCurses;
static VALUE mKey;
static VALUE cWindow;
#ifdef USE_MOUSE
static VALUE cMouseEvent;
#endif

static VALUE rb_stdscr;

struct windata {
    WINDOW *window;
};

static VALUE window_attroff(VALUE obj, VALUE attrs);
static VALUE window_attron(VALUE obj, VALUE attrs);
static VALUE window_attrset(VALUE obj, VALUE attrs);

static void
no_window(void)
{
    rb_raise(rb_eRuntimeError, "already closed window");
}

#define GetWINDOW(obj, winp) do {\
    if (!OBJ_TAINTED(obj) && rb_safe_level() >= 4)\
	rb_raise(rb_eSecurityError, "Insecure: operation on untainted window");\
    Data_Get_Struct((obj), struct windata, (winp));\
    if ((winp)->window == 0) no_window();\
} while (0)

static void
free_window(struct windata *winp)
{
    if (winp->window && winp->window != stdscr) delwin(winp->window);
    winp->window = 0;
    xfree(winp);
}

static VALUE
prep_window(VALUE class, WINDOW *window)
{
    VALUE obj;
    struct windata *winp;

    if (window == NULL) {
	rb_raise(rb_eRuntimeError, "failed to create window");
    }

    obj = rb_obj_alloc(class);
    Data_Get_Struct(obj, struct windata, winp);
    winp->window = window;

    return obj;
}

/*-------------------------- module Curses --------------------------*/

/* def init_screen */
static VALUE
curses_init_screen(void)
{
    rb_secure(4);
    if (rb_stdscr) return rb_stdscr;
    initscr();
    if (stdscr == 0) {
	rb_raise(rb_eRuntimeError, "can't initialize curses");
    }
    clear();
    rb_stdscr = prep_window(cWindow, stdscr);
    return rb_stdscr;
}

/* def stdscr */
#define curses_stdscr curses_init_screen

/* def close_screen */
static VALUE
curses_close_screen(void)
{
    curses_stdscr();
#ifdef HAVE_ISENDWIN
    if (!isendwin())
#endif
	endwin();
    rb_stdscr = 0;
    return Qnil;
}

static void
curses_finalize(VALUE dummy)
{
    if (stdscr
#ifdef HAVE_ISENDWIN
	&& !isendwin()
#endif
	)
	endwin();
    rb_stdscr = 0;
    rb_gc_unregister_address(&rb_stdscr);
}

#ifdef HAVE_ISENDWIN
/* def closed? */
static VALUE
curses_closed(void)
{
    curses_stdscr();
    if (isendwin()) {
	return Qtrue;
    }
    return Qfalse;
}
#else
#define curses_closed rb_f_notimplement
#endif

/* def clear */
static VALUE
curses_clear(VALUE obj)
{
    curses_stdscr();
    wclear(stdscr);
    return Qnil;
}

/* def clrtoeol */
static VALUE
curses_clrtoeol(void)
{
    curses_stdscr();
    clrtoeol();
    return Qnil;
}

/* def refresh */
static VALUE
curses_refresh(VALUE obj)
{
    curses_stdscr();
    refresh();
    return Qnil;
}

/* def doupdate */
static VALUE
curses_doupdate(VALUE obj)
{
    curses_stdscr();
#ifdef HAVE_DOUPDATE
    doupdate();
#else
    refresh();
#endif
    return Qnil;
}

/* def echo */
static VALUE
curses_echo(VALUE obj)
{
    curses_stdscr();
    echo();
    return Qnil;
}

/* def noecho */
static VALUE
curses_noecho(VALUE obj)
{
    curses_stdscr();
    noecho();
    return Qnil;
}

/* def raw */
static VALUE
curses_raw(VALUE obj)
{
    curses_stdscr();
    raw();
    return Qnil;
}

/* def noraw */
static VALUE
curses_noraw(VALUE obj)
{
    curses_stdscr();
    noraw();
    return Qnil;
}

/* def cbreak */
static VALUE
curses_cbreak(VALUE obj)
{
    curses_stdscr();
    cbreak();
    return Qnil;
}

/* def nocbreak */
static VALUE
curses_nocbreak(VALUE obj)
{
    curses_stdscr();
    nocbreak();
    return Qnil;
}

/* def nl */
static VALUE
curses_nl(VALUE obj)
{
    curses_stdscr();
    nl();
    return Qnil;
}

/* def nonl */
static VALUE
curses_nonl(VALUE obj)
{
    curses_stdscr();
    nonl();
    return Qnil;
}

/* def beep */
static VALUE
curses_beep(VALUE obj)
{
#ifdef HAVE_BEEP
    curses_stdscr();
    beep();
#endif
    return Qnil;
}

/* def flash */
static VALUE
curses_flash(VALUE obj)
{
#ifdef HAVE_FLASH
    curses_stdscr();
    flash();
#endif
    return Qnil;
}

static int
curses_char(VALUE c)
{
    if (FIXNUM_P(c)) {
	return NUM2INT(c);
    }
    else {
	int cc;

	StringValue(c);
	if (RSTRING_LEN(c) == 0 || RSTRING_LEN(c) > 1) {
	    rb_raise(rb_eArgError, "string not corresponding a character");
	}
	cc = RSTRING_PTR(c)[0];
	if (cc > 0x7f) {
	    rb_raise(rb_eArgError, "no multibyte string supported (yet)");
	}
	return cc;
    }
}

#ifdef HAVE_UNGETCH
/* def ungetch */
static VALUE
curses_ungetch(VALUE obj, VALUE ch)
{
    int c = curses_char(ch);
    curses_stdscr();
    ungetch(c);
    return Qnil;
}
#else
#define curses_ungetch rb_f_notimplement
#endif

/* def setpos(y, x) */
static VALUE
curses_setpos(VALUE obj, VALUE y, VALUE x)
{
    curses_stdscr();
    move(NUM2INT(y), NUM2INT(x));
    return Qnil;
}

/* def standout */
static VALUE
curses_standout(VALUE obj)
{
    curses_stdscr();
    standout();
    return Qnil;
}

/* def standend */
static VALUE
curses_standend(VALUE obj)
{
    curses_stdscr();
    standend();
    return Qnil;
}

/* def inch */
static VALUE
curses_inch(VALUE obj)
{
    curses_stdscr();
    return CH2FIX(inch());
}

/* def addch(ch) */
static VALUE
curses_addch(VALUE obj, VALUE ch)
{
    curses_stdscr();
    addch(NUM2CH(ch));
    return Qnil;
}

/* def insch(ch) */
static VALUE
curses_insch(VALUE obj, VALUE ch)
{
    curses_stdscr();
    insch(NUM2CH(ch));
    return Qnil;
}

/* def addstr(str) */
static VALUE
curses_addstr(VALUE obj, VALUE str)
{
    StringValue(str);
    str = rb_str_export_locale(str);
    curses_stdscr();
    if (!NIL_P(str)) {
	addstr(StringValueCStr(str));
    }
    return Qnil;
}

static VALUE
getch_func(void *arg)
{
    int *ip = (int *)arg;
    *ip = getch();
    return Qnil;
}

/* def getch */
static VALUE
curses_getch(VALUE obj)
{
    int c;

    curses_stdscr();
    rb_thread_blocking_region(getch_func, (void *)&c, RUBY_UBF_IO, 0);
    if (c == EOF) return Qnil;
    if (rb_isprint(c)) {
	char ch = (char)c;

	return rb_locale_str_new(&ch, 1);
    }
    return UINT2NUM(c);
}

/* This should be big enough.. I hope */
#define GETSTR_BUF_SIZE 1024

static VALUE
getstr_func(void *arg)
{
    char *rtn = (char *)arg;
#if defined(HAVE_GETNSTR)
    getnstr(rtn,GETSTR_BUF_SIZE-1);
#else
    getstr(rtn);
#endif
    return Qnil;
}

/* def getstr */
static VALUE
curses_getstr(VALUE obj)
{
    char rtn[GETSTR_BUF_SIZE];

    curses_stdscr();
    rb_thread_blocking_region(getstr_func, (void *)rtn, RUBY_UBF_IO, 0);
    return rb_locale_str_new_cstr(rtn);
}

/* def delch */
static VALUE
curses_delch(VALUE obj)
{
    curses_stdscr();
    delch();
    return Qnil;
}

/* def delelteln */
static VALUE
curses_deleteln(VALUE obj)
{
    curses_stdscr();
#if defined(HAVE_DELETELN) || defined(deleteln)
    deleteln();
#endif
    return Qnil;
}

/* def insertln */
static VALUE
curses_insertln(VALUE obj)
{
    curses_stdscr();
#if defined(HAVE_INSERTLN) || defined(insertln)
    insertln();
#endif
    return Qnil;
}

/* def keyname */
static VALUE
curses_keyname(VALUE obj, VALUE c)
{
#ifdef HAVE_KEYNAME
    int cc = curses_char(c);
    const char *name;

    curses_stdscr();
    name = keyname(cc);
    if (name) {
	return rb_str_new_cstr(name);
    }
    else {
	return Qnil;
    }
#else
    return Qnil;
#endif
}

static VALUE
curses_lines(void)
{
    return INT2FIX(LINES);
}

static VALUE
curses_cols(void)
{
    return INT2FIX(COLS);
}

/**
 * Sets Cursor Visibility.
 * 0: invisible
 * 1: visible
 * 2: very visible
 */
static VALUE
curses_curs_set(VALUE obj, VALUE visibility)
{
#ifdef HAVE_CURS_SET
    int n;
    curses_stdscr();
    return (n = curs_set(NUM2INT(visibility)) != ERR) ? INT2FIX(n) : Qnil;
#else
    return Qnil;
#endif
}

static VALUE
curses_scrl(VALUE obj, VALUE n)
{
    /* may have to raise exception on ERR */
#ifdef HAVE_SCRL
    curses_stdscr();
    return (scrl(NUM2INT(n)) == OK) ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

static VALUE
curses_setscrreg(VALUE obj, VALUE top, VALUE bottom)
{
    /* may have to raise exception on ERR */
#ifdef HAVE_SETSCRREG
    curses_stdscr();
    return (setscrreg(NUM2INT(top), NUM2INT(bottom)) == OK) ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

static VALUE
curses_attroff(VALUE obj, VALUE attrs)
{
    curses_stdscr();
    return window_attroff(rb_stdscr,attrs);
    /* return INT2FIX(attroff(NUM2INT(attrs))); */
}

static VALUE
curses_attron(VALUE obj, VALUE attrs)
{
    curses_stdscr();
    return window_attron(rb_stdscr,attrs);
    /* return INT2FIX(attroff(NUM2INT(attrs))); */
}

static VALUE
curses_attrset(VALUE obj, VALUE attrs)
{
    curses_stdscr();
    return window_attrset(rb_stdscr,attrs);
    /* return INT2FIX(attroff(NUM2INT(attrs))); */
}

static VALUE
curses_bkgdset(VALUE obj, VALUE ch)
{
#ifdef HAVE_BKGDSET
    curses_stdscr();
    bkgdset(NUM2CH(ch));
#endif
    return Qnil;
}

static VALUE
curses_bkgd(VALUE obj, VALUE ch)
{
#ifdef HAVE_BKGD
    curses_stdscr();
    return (bkgd(NUM2CH(ch)) == OK) ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

#if defined(HAVE_USE_DEFAULT_COLORS)
static VALUE
curses_use_default_colors(VALUE obj)
{
    curses_stdscr();
    use_default_colors();
    return Qnil;
}
#else
#define curses_use_default_colors rb_f_notimplement
#endif

#if defined(HAVE_TABSIZE)
static VALUE
curses_tabsize_set(VALUE obj, VALUE val)
{
    TABSIZE = NUM2INT(val);
    return INT2NUM(TABSIZE);
}
#else
#define curses_tabsize_set rb_f_notimplement
#endif

#if defined(HAVE_TABSIZE)
static VALUE
curses_tabsize_get(VALUE ojb)
{
    return INT2NUM(TABSIZE);
}
#else
#define curses_tabsize_get rb_f_notimplement
#endif

#if defined(HAVE_ESCDELAY)
static VALUE
curses_escdelay_set(VALUE obj, VALUE val)
{
    ESCDELAY = NUM2INT(val);
    return INT2NUM(ESCDELAY);
}
#else
#define curses_escdelay_set rb_f_notimplement
#endif

#if defined(HAVE_ESCDELAY)
static VALUE
curses_escdelay_get(VALUE obj)
{
    return INT2NUM(ESCDELAY);
}
#else
#define curses_escdelay_get rb_f_notimplement
#endif

static VALUE
curses_resizeterm(VALUE obj, VALUE lin, VALUE col)
{
#if defined(HAVE_RESIZETERM)
    curses_stdscr();
    return (resizeterm(NUM2INT(lin),NUM2INT(col)) == OK) ? Qtrue : Qfalse;
#else
    return Qnil;
#endif
}

#ifdef USE_COLOR
static VALUE
curses_start_color(VALUE obj)
{
    /* may have to raise exception on ERR */
    curses_stdscr();
    return (start_color() == OK) ? Qtrue : Qfalse;
}

static VALUE
curses_init_pair(VALUE obj, VALUE pair, VALUE f, VALUE b)
{
    /* may have to raise exception on ERR */
    curses_stdscr();
    return (init_pair(NUM2INT(pair),NUM2INT(f),NUM2INT(b)) == OK) ? Qtrue : Qfalse;
}

static VALUE
curses_init_color(VALUE obj, VALUE color, VALUE r, VALUE g, VALUE b)
{
    /* may have to raise exception on ERR */
    curses_stdscr();
    return (init_color(NUM2INT(color),NUM2INT(r),
		       NUM2INT(g),NUM2INT(b)) == OK) ? Qtrue : Qfalse;
}

static VALUE
curses_has_colors(VALUE obj)
{
    curses_stdscr();
    return has_colors() ? Qtrue : Qfalse;
}

static VALUE
curses_can_change_color(VALUE obj)
{
    curses_stdscr();
    return can_change_color() ? Qtrue : Qfalse;
}

#if defined(HAVE_COLORS)
static VALUE
curses_colors(VALUE obj)
{
    return INT2FIX(COLORS);
}
#else
#define curses_colors rb_f_notimplement
#endif

static VALUE
curses_color_content(VALUE obj, VALUE color)
{
    short r,g,b;

    curses_stdscr();
    color_content(NUM2INT(color),&r,&g,&b);
    return rb_ary_new3(3,INT2FIX(r),INT2FIX(g),INT2FIX(b));
}


#if defined(HAVE_COLOR_PAIRS)
static VALUE
curses_color_pairs(VALUE obj)
{
    return INT2FIX(COLOR_PAIRS);
}
#else
#define curses_color_pairs rb_f_notimplement
#endif

static VALUE
curses_pair_content(VALUE obj, VALUE pair)
{
    short f,b;

    curses_stdscr();
    pair_content(NUM2INT(pair),&f,&b);
    return rb_ary_new3(2,INT2FIX(f),INT2FIX(b));
}

static VALUE
curses_color_pair(VALUE obj, VALUE attrs)
{
    return INT2FIX(COLOR_PAIR(NUM2INT(attrs)));
}

static VALUE
curses_pair_number(VALUE obj, VALUE attrs)
{
    curses_stdscr();
    return INT2FIX(PAIR_NUMBER(NUM2INT(attrs)));
}
#endif /* USE_COLOR */

#ifdef USE_MOUSE
struct mousedata {
    MEVENT *mevent;
};

static void
no_mevent(void)
{
    rb_raise(rb_eRuntimeError, "no such mouse event");
}

#define GetMOUSE(obj, data) do {\
    if (!OBJ_TAINTED(obj) && rb_safe_level() >= 4)\
	rb_raise(rb_eSecurityError, "Insecure: operation on untainted mouse");\
    Data_Get_Struct((obj), struct mousedata, (data));\
    if ((data)->mevent == 0) no_mevent();\
} while (0)

static void
curses_mousedata_free(struct mousedata *mdata)
{
    if (mdata->mevent)
	xfree(mdata->mevent);
}

static VALUE
curses_getmouse(VALUE obj)
{
    struct mousedata *mdata;
    VALUE val;

    curses_stdscr();
    val = Data_Make_Struct(cMouseEvent,struct mousedata,
			   0,curses_mousedata_free,mdata);
    mdata->mevent = (MEVENT*)xmalloc(sizeof(MEVENT));
    return (getmouse(mdata->mevent) == OK) ? val : Qnil;
}

static VALUE
curses_ungetmouse(VALUE obj, VALUE mevent)
{
    struct mousedata *mdata;

    curses_stdscr();
    GetMOUSE(mevent,mdata);
    return (ungetmouse(mdata->mevent) == OK) ? Qtrue : Qfalse;
}

static VALUE
curses_mouseinterval(VALUE obj, VALUE interval)
{
    curses_stdscr();
    return mouseinterval(NUM2INT(interval)) ? Qtrue : Qfalse;
}

static VALUE
curses_mousemask(VALUE obj, VALUE mask)
{
    curses_stdscr();
    return INT2NUM(mousemask(NUM2UINT(mask),NULL));
}

#define DEFINE_MOUSE_GET_MEMBER(func_name,mem) \
static VALUE func_name (VALUE mouse) \
{ \
    struct mousedata *mdata; \
    GetMOUSE(mouse, mdata); \
    return (UINT2NUM(mdata->mevent -> mem)); \
}

DEFINE_MOUSE_GET_MEMBER(curs_mouse_id, id)
DEFINE_MOUSE_GET_MEMBER(curs_mouse_x, x)
DEFINE_MOUSE_GET_MEMBER(curs_mouse_y, y)
DEFINE_MOUSE_GET_MEMBER(curs_mouse_z, z)
DEFINE_MOUSE_GET_MEMBER(curs_mouse_bstate, bstate)
#undef define_curs_mouse_member
#endif /* USE_MOUSE */

#ifdef HAVE_TIMEOUT
static VALUE
curses_timeout(VALUE obj, VALUE delay)
{
    curses_stdscr();
    timeout(NUM2INT(delay));
    return Qnil;
}
#else
#define curses_timeout rb_f_notimplement
#endif

#ifdef HAVE_DEF_PROG_MODE
static VALUE
curses_def_prog_mode(VALUE obj)
{
    curses_stdscr();
    return def_prog_mode() == OK ? Qtrue : Qfalse;
}
#else
#define curses_def_prog_mode rb_f_notimplement
#endif

#ifdef HAVE_RESET_PROG_MODE
static VALUE
curses_reset_prog_mode(VALUE obj)
{
    curses_stdscr();
    return reset_prog_mode() == OK ? Qtrue : Qfalse;
}
#else
#define curses_reset_prog_mode rb_f_notimplement
#endif

/*-------------------------- class Window --------------------------*/

/* def self.allocate */
static VALUE
window_s_allocate(VALUE class)
{
    struct windata *winp;

    return Data_Make_Struct(class, struct windata, 0, free_window, winp);
}

/* def initialize(h, w, top, left) */
static VALUE
window_initialize(VALUE obj, VALUE h, VALUE w, VALUE top, VALUE left)
{
    struct windata *winp;
    WINDOW *window;

    rb_secure(4);
    curses_init_screen();
    Data_Get_Struct(obj, struct windata, winp);
    if (winp->window) delwin(winp->window);
    window = newwin(NUM2INT(h), NUM2INT(w), NUM2INT(top), NUM2INT(left));
    wclear(window);
    winp->window = window;

    return obj;
}

/* def subwin(height, width, top, left) */
static VALUE
window_subwin(VALUE obj, VALUE height, VALUE width, VALUE top, VALUE left)
{
    struct windata *winp;
    WINDOW *window;
    VALUE win;
    int h, w, t, l;

    h = NUM2INT(height);
    w = NUM2INT(width);
    t = NUM2INT(top);
    l = NUM2INT(left);
    GetWINDOW(obj, winp);
    window = subwin(winp->window, h, w, t, l);
    win = prep_window(rb_obj_class(obj), window);

    return win;
}

/* def close */
static VALUE
window_close(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    delwin(winp->window);
    winp->window = 0;

    return Qnil;
}

/* def clear */
static VALUE
window_clear(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    wclear(winp->window);

    return Qnil;
}

/* def clrtoeol */
static VALUE
window_clrtoeol(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    wclrtoeol(winp->window);

    return Qnil;
}

/* def refresh */
static VALUE
window_refresh(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    wrefresh(winp->window);

    return Qnil;
}

/* def noutrefresh */
static VALUE
window_noutrefresh(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
#ifdef HAVE_DOUPDATE
    wnoutrefresh(winp->window);
#else
    wrefresh(winp->window);
#endif

    return Qnil;
}

/* def move(y, x) */
static VALUE
window_move(VALUE obj, VALUE y, VALUE x)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    mvwin(winp->window, NUM2INT(y), NUM2INT(x));

    return Qnil;
}

/* def setpos(y, x) */
static VALUE
window_setpos(VALUE obj, VALUE y, VALUE x)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    wmove(winp->window, NUM2INT(y), NUM2INT(x));
    return Qnil;
}

/* def cury */
static VALUE
window_cury(VALUE obj)
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
    getyx(winp->window, y, x);
    return INT2FIX(y);
}

/* def curx */
static VALUE
window_curx(VALUE obj)
{
    struct windata *winp;
    int x, y;

    GetWINDOW(obj, winp);
    getyx(winp->window, y, x);
    return INT2FIX(x);
}

/* def maxy */
static VALUE
window_maxy(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
#if defined(getmaxy)
    return INT2FIX(getmaxy(winp->window));
#elif defined(getmaxyx)
    {
	int x, y;
	getmaxyx(winp->window, y, x);
	return INT2FIX(y);
    }
#else
    return INT2FIX(winp->window->_maxy+1);
#endif
}

/* def maxx */
static VALUE
window_maxx(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
#if defined(getmaxx)
    return INT2FIX(getmaxx(winp->window));
#elif defined(getmaxyx)
    {
	int x, y;
	getmaxyx(winp->window, y, x);
	return INT2FIX(x);
    }
#else
    return INT2FIX(winp->window->_maxx+1);
#endif
}

/* def begy */
static VALUE
window_begy(VALUE obj)
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
window_begx(VALUE obj)
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

/* def box(vert, hor) */
static VALUE
window_box(int argc, VALUE *argv, VALUE self)
{
    struct windata *winp;
    VALUE vert, hor, corn;

    rb_scan_args(argc, argv, "21", &vert, &hor, &corn);

    GetWINDOW(self, winp);
    box(winp->window, NUM2CH(vert), NUM2CH(hor));

    if (!NIL_P(corn)) {
	int cur_x, cur_y, x, y;
	chtype c;

	c = NUM2CH(corn);
	getyx(winp->window, cur_y, cur_x);
	x = NUM2INT(window_maxx(self)) - 1;
	y = NUM2INT(window_maxy(self)) - 1;
	wmove(winp->window, 0, 0);
	waddch(winp->window, c);
	wmove(winp->window, y, 0);
	waddch(winp->window, c);
	wmove(winp->window, y, x);
	waddch(winp->window, c);
	wmove(winp->window, 0, x);
	waddch(winp->window, c);
	wmove(winp->window, cur_y, cur_x);
    }

    return Qnil;
}

/* def standout */
static VALUE
window_standout(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    wstandout(winp->window);
    return Qnil;
}

/* def standend */
static VALUE
window_standend(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    wstandend(winp->window);
    return Qnil;
}

/* def inch */
static VALUE
window_inch(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    return CH2FIX(winch(winp->window));
}

/* def addch(ch) */
static VALUE
window_addch(VALUE obj, VALUE ch)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    waddch(winp->window, NUM2CH(ch));

    return Qnil;
}

/* def insch(ch) */
static VALUE
window_insch(VALUE obj, VALUE ch)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    winsch(winp->window, NUM2CH(ch));

    return Qnil;
}

/* def addstr(str) */
static VALUE
window_addstr(VALUE obj, VALUE str)
{
    if (!NIL_P(str)) {
	struct windata *winp;

	StringValue(str);
	str = rb_str_export_locale(str);
	GetWINDOW(obj, winp);
	waddstr(winp->window, StringValueCStr(str));
    }
    return Qnil;
}

/* def <<(str) */
static VALUE
window_addstr2(VALUE obj, VALUE str)
{
    window_addstr(obj, str);
    return obj;
}

struct wgetch_arg {
    WINDOW *win;
    int c;
};

static VALUE
wgetch_func(void *_arg)
{
    struct wgetch_arg *arg = (struct wgetch_arg *)_arg;
    arg->c = wgetch(arg->win);
    return Qnil;
}

/* def getch */
static VALUE
window_getch(VALUE obj)
{
    struct windata *winp;
    struct wgetch_arg arg;
    int c;

    GetWINDOW(obj, winp);
    arg.win = winp->window;
    rb_thread_blocking_region(wgetch_func, (void *)&arg, RUBY_UBF_IO, 0);
    c = arg.c;
    if (c == EOF) return Qnil;
    if (rb_isprint(c)) {
	char ch = (char)c;

	return rb_locale_str_new(&ch, 1);
    }
    return UINT2NUM(c);
}

struct wgetstr_arg {
    WINDOW *win;
    char rtn[GETSTR_BUF_SIZE];
};

static VALUE
wgetstr_func(void *_arg)
{
    struct wgetstr_arg *arg = (struct wgetstr_arg *)_arg;
#if defined(HAVE_WGETNSTR)
    wgetnstr(arg->win, arg->rtn, GETSTR_BUF_SIZE-1);
#else
    wgetstr(arg->win, arg->rtn);
#endif
    return Qnil;
}

/* def getstr */
static VALUE
window_getstr(VALUE obj)
{
    struct windata *winp;
    struct wgetstr_arg arg;

    GetWINDOW(obj, winp);
    arg.win = winp->window;
    rb_thread_blocking_region(wgetstr_func, (void *)&arg, RUBY_UBF_IO, 0);
    return rb_locale_str_new_cstr(arg.rtn);
}

/* def delch */
static VALUE
window_delch(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    wdelch(winp->window);
    return Qnil;
}

/* def delelteln */
static VALUE
window_deleteln(VALUE obj)
{
#if defined(HAVE_WDELETELN) || defined(wdeleteln)
    struct windata *winp;

    GetWINDOW(obj, winp);
    wdeleteln(winp->window);
#endif
    return Qnil;
}

/* def insertln */
static VALUE
window_insertln(VALUE obj)
{
#if defined(HAVE_WINSERTLN) || defined(winsertln)
    struct windata *winp;

    GetWINDOW(obj, winp);
    winsertln(winp->window);
#endif
    return Qnil;
}

static VALUE
window_scrollok(VALUE obj, VALUE bf)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    scrollok(winp->window, RTEST(bf) ? TRUE : FALSE);
    return Qnil;
}

static VALUE
window_idlok(VALUE obj, VALUE bf)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    idlok(winp->window, RTEST(bf) ? TRUE : FALSE);
    return Qnil;
}

static VALUE
window_setscrreg(VALUE obj, VALUE top, VALUE bottom)
{
#ifdef HAVE_WSETSCRREG
    struct windata *winp;
    int res;

    GetWINDOW(obj, winp);
    res = wsetscrreg(winp->window, NUM2INT(top), NUM2INT(bottom));
    /* may have to raise exception on ERR */
    return (res == OK) ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

#if defined(USE_COLOR) && defined(HAVE_WCOLOR_SET)
static VALUE
window_color_set(VALUE obj, VALUE col)
{
    struct windata *winp;
    int res;

    GetWINDOW(obj, winp);
    res = wcolor_set(winp->window, NUM2INT(col), NULL);
    return (res == OK) ? Qtrue : Qfalse;
}
#endif /* defined(USE_COLOR) && defined(HAVE_WCOLOR_SET) */

static VALUE
window_scroll(VALUE obj)
{
    struct windata *winp;

    GetWINDOW(obj, winp);
    /* may have to raise exception on ERR */
    return (scroll(winp->window) == OK) ? Qtrue : Qfalse;
}

static VALUE
window_scrl(VALUE obj, VALUE n)
{
#ifdef HAVE_WSCRL
    struct windata *winp;

    GetWINDOW(obj, winp);
    /* may have to raise exception on ERR */
    return (wscrl(winp->window,NUM2INT(n)) == OK) ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

static VALUE
window_attroff(VALUE obj, VALUE attrs)
{
#ifdef HAVE_WATTROFF
    struct windata *winp;

    GetWINDOW(obj,winp);
    return INT2FIX(wattroff(winp->window,NUM2INT(attrs)));
#else
    return Qtrue;
#endif
}

static VALUE
window_attron(VALUE obj, VALUE attrs)
{
#ifdef HAVE_WATTRON
    struct windata *winp;
    VALUE val;

    GetWINDOW(obj,winp);
    val = INT2FIX(wattron(winp->window,NUM2INT(attrs)));
    if (rb_block_given_p()) {
	rb_yield(val);
	wattroff(winp->window,NUM2INT(attrs));
	return val;
    }
    else{
	return val;
    }
#else
    return Qtrue;
#endif
}

static VALUE
window_attrset(VALUE obj, VALUE attrs)
{
#ifdef HAVE_WATTRSET
    struct windata *winp;

    GetWINDOW(obj,winp);
    return INT2FIX(wattrset(winp->window,NUM2INT(attrs)));
#else
    return Qtrue;
#endif
}

static VALUE
window_bkgdset(VALUE obj, VALUE ch)
{
#ifdef HAVE_WBKGDSET
    struct windata *winp;

    GetWINDOW(obj,winp);
    wbkgdset(winp->window, NUM2CH(ch));
#endif
    return Qnil;
}

static VALUE
window_bkgd(VALUE obj, VALUE ch)
{
#ifdef HAVE_WBKGD
    struct windata *winp;

    GetWINDOW(obj,winp);
    return (wbkgd(winp->window, NUM2CH(ch)) == OK) ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

static VALUE
window_getbkgd(VALUE obj)
{
#ifdef HAVE_WGETBKGD
    chtype c;
    struct windata *winp;

    GetWINDOW(obj,winp);
    return (c = getbkgd(winp->window) != ERR) ? CH2FIX(c) : Qnil;
#else
    return Qnil;
#endif
}

static VALUE
window_resize(VALUE obj, VALUE lin, VALUE col)
{
#if defined(HAVE_WRESIZE)
    struct windata *winp;

    GetWINDOW(obj,winp);
    return wresize(winp->window, NUM2INT(lin), NUM2INT(col)) == OK ? Qtrue : Qfalse;
#else
    return Qnil;
#endif
}


#ifdef HAVE_KEYPAD
static VALUE
window_keypad(VALUE obj, VALUE val)
{
    struct windata *winp;

    GetWINDOW(obj,winp);
    /* keypad() of NetBSD's libcurses returns no value */
#if defined(__NetBSD__) && !defined(NCURSES_VERSION)
    keypad(winp->window,(RTEST(val) ? TRUE : FALSE));
    return Qnil;
#else
    /* may have to raise exception on ERR */
    return (keypad(winp->window,RTEST(val) ? TRUE : FALSE)) == OK ?
	Qtrue : Qfalse;
#endif
}
#else
#define window_keypad rb_f_notimplement
#endif

#ifdef HAVE_NODELAY
static VALUE
window_nodelay(VALUE obj, VALUE val)
{
    struct windata *winp;
    GetWINDOW(obj,winp);

    /* nodelay() of NetBSD's libcurses returns no value */
#if defined(__NetBSD__) && !defined(NCURSES_VERSION)
    nodelay(winp->window, RTEST(val) ? TRUE : FALSE);
    return Qnil;
#else
    return nodelay(winp->window,RTEST(val) ? TRUE : FALSE) == OK ? Qtrue : Qfalse;
#endif
}
#else
#define window_nodelay rb_f_notimplement
#endif

#ifdef HAVE_WTIMEOUT
static VALUE
window_timeout(VALUE obj, VALUE delay)
{
    struct windata *winp;
    GetWINDOW(obj,winp);

    wtimeout(winp->window,NUM2INT(delay));
    return Qnil;
}
#else
#define window_timeout rb_f_notimplement
#endif

/*------------------------- Initialization -------------------------*/
void
Init_curses(void)
{
    mCurses    = rb_define_module("Curses");
    mKey       = rb_define_module_under(mCurses, "Key");

    rb_gc_register_address(&rb_stdscr);

#ifdef USE_MOUSE
    cMouseEvent = rb_define_class_under(mCurses,"MouseEvent",rb_cObject);
    rb_undef_method(CLASS_OF(cMouseEvent),"new");
    rb_define_method(cMouseEvent, "eid", curs_mouse_id, 0);
    rb_define_method(cMouseEvent, "x", curs_mouse_x, 0);
    rb_define_method(cMouseEvent, "y", curs_mouse_y, 0);
    rb_define_method(cMouseEvent, "z", curs_mouse_z, 0);
    rb_define_method(cMouseEvent, "bstate", curs_mouse_bstate, 0);
#endif /* USE_MOUSE */

    rb_define_module_function(mCurses, "ESCDELAY=", curses_escdelay_set, 1);
    rb_define_module_function(mCurses, "ESCDELAY", curses_escdelay_get, 0);
    rb_define_module_function(mCurses, "TABSIZE", curses_tabsize_get, 0);
    rb_define_module_function(mCurses, "TABSIZE=", curses_tabsize_set, 1);

    rb_define_module_function(mCurses, "use_default_colors", curses_use_default_colors, 0);
    rb_define_module_function(mCurses, "init_screen", curses_init_screen, 0);
    rb_define_module_function(mCurses, "close_screen", curses_close_screen, 0);
    rb_define_module_function(mCurses, "closed?", curses_closed, 0);
    rb_define_module_function(mCurses, "stdscr", curses_stdscr, 0);
    rb_define_module_function(mCurses, "refresh", curses_refresh, 0);
    rb_define_module_function(mCurses, "doupdate", curses_doupdate, 0);
    rb_define_module_function(mCurses, "clear", curses_clear, 0);
    rb_define_module_function(mCurses, "clrtoeol", curses_clrtoeol, 0);
    rb_define_module_function(mCurses, "echo", curses_echo, 0);
    rb_define_module_function(mCurses, "noecho", curses_noecho, 0);
    rb_define_module_function(mCurses, "raw", curses_raw, 0);
    rb_define_module_function(mCurses, "noraw", curses_noraw, 0);
    rb_define_module_function(mCurses, "cbreak", curses_cbreak, 0);
    rb_define_module_function(mCurses, "nocbreak", curses_nocbreak, 0);
    rb_define_module_function(mCurses, "crmode", curses_nocbreak, 0);
    rb_define_module_function(mCurses, "nocrmode", curses_nocbreak, 0);
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
    rb_define_module_function(mCurses, "insertln", curses_insertln, 0);
    rb_define_module_function(mCurses, "keyname", curses_keyname, 1);
    rb_define_module_function(mCurses, "lines", curses_lines, 0);
    rb_define_module_function(mCurses, "cols", curses_cols, 0);
    rb_define_module_function(mCurses, "curs_set", curses_curs_set, 1);
    rb_define_module_function(mCurses, "scrl", curses_scrl, 1);
    rb_define_module_function(mCurses, "setscrreg", curses_setscrreg, 2);
    rb_define_module_function(mCurses, "attroff", curses_attroff, 1);
    rb_define_module_function(mCurses, "attron", curses_attron, 1);
    rb_define_module_function(mCurses, "attrset", curses_attrset, 1);
    rb_define_module_function(mCurses, "bkgdset", curses_bkgdset, 1);
    rb_define_module_function(mCurses, "bkgd", curses_bkgd, 1);
    rb_define_module_function(mCurses, "resizeterm", curses_resizeterm, 2);
    rb_define_module_function(mCurses, "resize", curses_resizeterm, 2);
#ifdef USE_COLOR
    rb_define_module_function(mCurses, "start_color", curses_start_color, 0);
    rb_define_module_function(mCurses, "init_pair", curses_init_pair, 3);
    rb_define_module_function(mCurses, "init_color", curses_init_color, 4);
    rb_define_module_function(mCurses, "has_colors?", curses_has_colors, 0);
    rb_define_module_function(mCurses, "can_change_color?",
			      curses_can_change_color, 0);
    rb_define_module_function(mCurses, "colors", curses_colors, 0);
    rb_define_module_function(mCurses, "color_content", curses_color_content, 1);
    rb_define_module_function(mCurses, "color_pairs", curses_color_pairs, 0);
    rb_define_module_function(mCurses, "pair_content", curses_pair_content, 1);
    rb_define_module_function(mCurses, "color_pair", curses_color_pair, 1);
    rb_define_module_function(mCurses, "pair_number", curses_pair_number, 1);
#endif /* USE_COLOR */
#ifdef USE_MOUSE
    rb_define_module_function(mCurses, "getmouse", curses_getmouse, 0);
    rb_define_module_function(mCurses, "ungetmouse", curses_ungetmouse, 1);
    rb_define_module_function(mCurses, "mouseinterval", curses_mouseinterval, 1);
    rb_define_module_function(mCurses, "mousemask", curses_mousemask, 1);
#endif /* USE_MOUSE */

    rb_define_module_function(mCurses, "timeout=", curses_timeout, 1);
    rb_define_module_function(mCurses, "def_prog_mode", curses_def_prog_mode, 0);
    rb_define_module_function(mCurses, "reset_prog_mode", curses_reset_prog_mode, 0);

    cWindow = rb_define_class_under(mCurses, "Window", rb_cData);
    rb_define_alloc_func(cWindow, window_s_allocate);
    rb_define_method(cWindow, "initialize", window_initialize, 4);
    rb_define_method(cWindow, "subwin", window_subwin, 4);
    rb_define_method(cWindow, "close", window_close, 0);
    rb_define_method(cWindow, "clear", window_clear, 0);
    rb_define_method(cWindow, "clrtoeol", window_clrtoeol, 0);
    rb_define_method(cWindow, "refresh", window_refresh, 0);
    rb_define_method(cWindow, "noutrefresh", window_noutrefresh, 0);
    rb_define_method(cWindow, "box", window_box, -1);
    rb_define_method(cWindow, "move", window_move, 2);
    rb_define_method(cWindow, "setpos", window_setpos, 2);
#if defined(USE_COLOR) && defined(HAVE_WCOLOR_SET)
    rb_define_method(cWindow, "color_set", window_color_set, 1);
#endif /* USE_COLOR && HAVE_WCOLOR_SET */
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
    rb_define_method(cWindow, "insertln", window_insertln, 0);
    rb_define_method(cWindow, "scroll", window_scroll, 0);
    rb_define_method(cWindow, "scrollok", window_scrollok, 1);
    rb_define_method(cWindow, "idlok", window_idlok, 1);
    rb_define_method(cWindow, "setscrreg", window_setscrreg, 2);
    rb_define_method(cWindow, "scrl", window_scrl, 1);
    rb_define_method(cWindow, "resize", window_resize, 2);
    rb_define_method(cWindow, "keypad", window_keypad, 1);
    rb_define_method(cWindow, "keypad=", window_keypad, 1);

    rb_define_method(cWindow, "attroff", window_attroff, 1);
    rb_define_method(cWindow, "attron", window_attron, 1);
    rb_define_method(cWindow, "attrset", window_attrset, 1);
    rb_define_method(cWindow, "bkgdset", window_bkgdset, 1);
    rb_define_method(cWindow, "bkgd", window_bkgd, 1);
    rb_define_method(cWindow, "getbkgd", window_getbkgd, 0);

    rb_define_method(cWindow, "nodelay=", window_nodelay, 1);
    rb_define_method(cWindow, "timeout=", window_timeout, 1);

#define rb_curses_define_const(c) rb_define_const(mCurses,#c,UINT2NUM(c))

#ifdef USE_COLOR
    rb_curses_define_const(A_ATTRIBUTES);
#ifdef A_NORMAL
    rb_curses_define_const(A_NORMAL);
#endif
    rb_curses_define_const(A_STANDOUT);
    rb_curses_define_const(A_UNDERLINE);
    rb_curses_define_const(A_REVERSE);
    rb_curses_define_const(A_BLINK);
    rb_curses_define_const(A_DIM);
    rb_curses_define_const(A_BOLD);
    rb_curses_define_const(A_PROTECT);
#ifdef A_INVIS /* for NetBSD */
    rb_curses_define_const(A_INVIS);
#endif
    rb_curses_define_const(A_ALTCHARSET);
    rb_curses_define_const(A_CHARTEXT);
#ifdef A_HORIZONTAL
    rb_curses_define_const(A_HORIZONTAL);
#endif
#ifdef A_LEFT
    rb_curses_define_const(A_LEFT);
#endif
#ifdef A_LOW
    rb_curses_define_const(A_LOW);
#endif
#ifdef A_RIGHT
    rb_curses_define_const(A_RIGHT);
#endif
#ifdef A_TOP
    rb_curses_define_const(A_TOP);
#endif
#ifdef A_VERTICAL
    rb_curses_define_const(A_VERTICAL);
#endif
    rb_curses_define_const(A_COLOR);

#ifdef COLORS
    rb_curses_define_const(COLORS);
#endif
    rb_curses_define_const(COLOR_BLACK);
    rb_curses_define_const(COLOR_RED);
    rb_curses_define_const(COLOR_GREEN);
    rb_curses_define_const(COLOR_YELLOW);
    rb_curses_define_const(COLOR_BLUE);
    rb_curses_define_const(COLOR_MAGENTA);
    rb_curses_define_const(COLOR_CYAN);
    rb_curses_define_const(COLOR_WHITE);
#endif /* USE_COLOR */
#ifdef USE_MOUSE
#ifdef BUTTON1_PRESSED
    rb_curses_define_const(BUTTON1_PRESSED);
#endif
#ifdef BUTTON1_RELEASED
    rb_curses_define_const(BUTTON1_RELEASED);
#endif
#ifdef BUTTON1_CLICKED
    rb_curses_define_const(BUTTON1_CLICKED);
#endif
#ifdef BUTTON1_DOUBLE_CLICKED
    rb_curses_define_const(BUTTON1_DOUBLE_CLICKED);
#endif
#ifdef BUTTON1_TRIPLE_CLICKED
    rb_curses_define_const(BUTTON1_TRIPLE_CLICKED);
#endif
#ifdef BUTTON2_PRESSED
    rb_curses_define_const(BUTTON2_PRESSED);
#endif
#ifdef BUTTON2_RELEASED
    rb_curses_define_const(BUTTON2_RELEASED);
#endif
#ifdef BUTTON2_CLICKED
    rb_curses_define_const(BUTTON2_CLICKED);
#endif
#ifdef BUTTON2_DOUBLE_CLICKED
    rb_curses_define_const(BUTTON2_DOUBLE_CLICKED);
#endif
#ifdef BUTTON2_TRIPLE_CLICKED
    rb_curses_define_const(BUTTON2_TRIPLE_CLICKED);
#endif
#ifdef BUTTON3_PRESSED
    rb_curses_define_const(BUTTON3_PRESSED);
#endif
#ifdef BUTTON3_RELEASED
    rb_curses_define_const(BUTTON3_RELEASED);
#endif
#ifdef BUTTON3_CLICKED
    rb_curses_define_const(BUTTON3_CLICKED);
#endif
#ifdef BUTTON3_DOUBLE_CLICKED
    rb_curses_define_const(BUTTON3_DOUBLE_CLICKED);
#endif
#ifdef BUTTON3_TRIPLE_CLICKED
    rb_curses_define_const(BUTTON3_TRIPLE_CLICKED);
#endif
#ifdef BUTTON4_PRESSED
    rb_curses_define_const(BUTTON4_PRESSED);
#endif
#ifdef BUTTON4_RELEASED
    rb_curses_define_const(BUTTON4_RELEASED);
#endif
#ifdef BUTTON4_CLICKED
    rb_curses_define_const(BUTTON4_CLICKED);
#endif
#ifdef BUTTON4_DOUBLE_CLICKED
    rb_curses_define_const(BUTTON4_DOUBLE_CLICKED);
#endif
#ifdef BUTTON4_TRIPLE_CLICKED
    rb_curses_define_const(BUTTON4_TRIPLE_CLICKED);
#endif
#ifdef BUTTON_SHIFT
    rb_curses_define_const(BUTTON_SHIFT);
#endif
#ifdef BUTTON_CTRL
    rb_curses_define_const(BUTTON_CTRL);
#endif
#ifdef BUTTON_ALT
    rb_curses_define_const(BUTTON_ALT);
#endif
#ifdef ALL_MOUSE_EVENTS
    rb_curses_define_const(ALL_MOUSE_EVENTS);
#endif
#ifdef REPORT_MOUSE_POSITION
    rb_curses_define_const(REPORT_MOUSE_POSITION);
#endif
#endif /* USE_MOUSE */

#if defined(KEY_MOUSE) && defined(USE_MOUSE)
    rb_curses_define_const(KEY_MOUSE);
    rb_define_const(mKey, "MOUSE", INT2NUM(KEY_MOUSE));
#endif
#ifdef KEY_MIN
    rb_curses_define_const(KEY_MIN);
    rb_define_const(mKey, "MIN", INT2NUM(KEY_MIN));
#endif
#ifdef KEY_BREAK
    rb_curses_define_const(KEY_BREAK);
    rb_define_const(mKey, "BREAK", INT2NUM(KEY_BREAK));
#endif
#ifdef KEY_DOWN
    rb_curses_define_const(KEY_DOWN);
    rb_define_const(mKey, "DOWN", INT2NUM(KEY_DOWN));
#endif
#ifdef KEY_UP
    rb_curses_define_const(KEY_UP);
    rb_define_const(mKey, "UP", INT2NUM(KEY_UP));
#endif
#ifdef KEY_LEFT
    rb_curses_define_const(KEY_LEFT);
    rb_define_const(mKey, "LEFT", INT2NUM(KEY_LEFT));
#endif
#ifdef KEY_RIGHT
    rb_curses_define_const(KEY_RIGHT);
    rb_define_const(mKey, "RIGHT", INT2NUM(KEY_RIGHT));
#endif
#ifdef KEY_HOME
    rb_curses_define_const(KEY_HOME);
    rb_define_const(mKey, "HOME", INT2NUM(KEY_HOME));
#endif
#ifdef KEY_BACKSPACE
    rb_curses_define_const(KEY_BACKSPACE);
    rb_define_const(mKey, "BACKSPACE", INT2NUM(KEY_BACKSPACE));
#endif
#ifdef KEY_F
    /* KEY_F(n) : 0 <= n <= 63 */
    {
	int i;
	char c[8];
	for (i=0; i<64; i++) {
	    sprintf(c, "KEY_F%d", i);
	    rb_define_const(mCurses, c, INT2NUM(KEY_F(i)));
	    sprintf(c, "F%d", i);
	    rb_define_const(mKey, c, INT2NUM(KEY_F(i)));
	}
    }
#endif
#ifdef KEY_DL
    rb_curses_define_const(KEY_DL);
    rb_define_const(mKey, "DL", INT2NUM(KEY_DL));
#endif
#ifdef KEY_IL
    rb_curses_define_const(KEY_IL);
    rb_define_const(mKey, "IL", INT2NUM(KEY_IL));
#endif
#ifdef KEY_DC
    rb_curses_define_const(KEY_DC);
    rb_define_const(mKey, "DC", INT2NUM(KEY_DC));
#endif
#ifdef KEY_IC
    rb_curses_define_const(KEY_IC);
    rb_define_const(mKey, "IC", INT2NUM(KEY_IC));
#endif
#ifdef KEY_EIC
    rb_curses_define_const(KEY_EIC);
    rb_define_const(mKey, "EIC", INT2NUM(KEY_EIC));
#endif
#ifdef KEY_CLEAR
    rb_curses_define_const(KEY_CLEAR);
    rb_define_const(mKey, "CLEAR", INT2NUM(KEY_CLEAR));
#endif
#ifdef KEY_EOS
    rb_curses_define_const(KEY_EOS);
    rb_define_const(mKey, "EOS", INT2NUM(KEY_EOS));
#endif
#ifdef KEY_EOL
    rb_curses_define_const(KEY_EOL);
    rb_define_const(mKey, "EOL", INT2NUM(KEY_EOL));
#endif
#ifdef KEY_SF
    rb_curses_define_const(KEY_SF);
    rb_define_const(mKey, "SF", INT2NUM(KEY_SF));
#endif
#ifdef KEY_SR
    rb_curses_define_const(KEY_SR);
    rb_define_const(mKey, "SR", INT2NUM(KEY_SR));
#endif
#ifdef KEY_NPAGE
    rb_curses_define_const(KEY_NPAGE);
    rb_define_const(mKey, "NPAGE", INT2NUM(KEY_NPAGE));
#endif
#ifdef KEY_PPAGE
    rb_curses_define_const(KEY_PPAGE);
    rb_define_const(mKey, "PPAGE", INT2NUM(KEY_PPAGE));
#endif
#ifdef KEY_STAB
    rb_curses_define_const(KEY_STAB);
    rb_define_const(mKey, "STAB", INT2NUM(KEY_STAB));
#endif
#ifdef KEY_CTAB
    rb_curses_define_const(KEY_CTAB);
    rb_define_const(mKey, "CTAB", INT2NUM(KEY_CTAB));
#endif
#ifdef KEY_CATAB
    rb_curses_define_const(KEY_CATAB);
    rb_define_const(mKey, "CATAB", INT2NUM(KEY_CATAB));
#endif
#ifdef KEY_ENTER
    rb_curses_define_const(KEY_ENTER);
    rb_define_const(mKey, "ENTER", INT2NUM(KEY_ENTER));
#endif
#ifdef KEY_SRESET
    rb_curses_define_const(KEY_SRESET);
    rb_define_const(mKey, "SRESET", INT2NUM(KEY_SRESET));
#endif
#ifdef KEY_RESET
    rb_curses_define_const(KEY_RESET);
    rb_define_const(mKey, "RESET", INT2NUM(KEY_RESET));
#endif
#ifdef KEY_PRINT
    rb_curses_define_const(KEY_PRINT);
    rb_define_const(mKey, "PRINT", INT2NUM(KEY_PRINT));
#endif
#ifdef KEY_LL
    rb_curses_define_const(KEY_LL);
    rb_define_const(mKey, "LL", INT2NUM(KEY_LL));
#endif
#ifdef KEY_A1
    rb_curses_define_const(KEY_A1);
    rb_define_const(mKey, "A1", INT2NUM(KEY_A1));
#endif
#ifdef KEY_A3
    rb_curses_define_const(KEY_A3);
    rb_define_const(mKey, "A3", INT2NUM(KEY_A3));
#endif
#ifdef KEY_B2
    rb_curses_define_const(KEY_B2);
    rb_define_const(mKey, "B2", INT2NUM(KEY_B2));
#endif
#ifdef KEY_C1
    rb_curses_define_const(KEY_C1);
    rb_define_const(mKey, "C1", INT2NUM(KEY_C1));
#endif
#ifdef KEY_C3
    rb_curses_define_const(KEY_C3);
    rb_define_const(mKey, "C3", INT2NUM(KEY_C3));
#endif
#ifdef KEY_BTAB
    rb_curses_define_const(KEY_BTAB);
    rb_define_const(mKey, "BTAB", INT2NUM(KEY_BTAB));
#endif
#ifdef KEY_BEG
    rb_curses_define_const(KEY_BEG);
    rb_define_const(mKey, "BEG", INT2NUM(KEY_BEG));
#endif
#ifdef KEY_CANCEL
    rb_curses_define_const(KEY_CANCEL);
    rb_define_const(mKey, "CANCEL", INT2NUM(KEY_CANCEL));
#endif
#ifdef KEY_CLOSE
    rb_curses_define_const(KEY_CLOSE);
    rb_define_const(mKey, "CLOSE", INT2NUM(KEY_CLOSE));
#endif
#ifdef KEY_COMMAND
    rb_curses_define_const(KEY_COMMAND);
    rb_define_const(mKey, "COMMAND", INT2NUM(KEY_COMMAND));
#endif
#ifdef KEY_COPY
    rb_curses_define_const(KEY_COPY);
    rb_define_const(mKey, "COPY", INT2NUM(KEY_COPY));
#endif
#ifdef KEY_CREATE
    rb_curses_define_const(KEY_CREATE);
    rb_define_const(mKey, "CREATE", INT2NUM(KEY_CREATE));
#endif
#ifdef KEY_END
    rb_curses_define_const(KEY_END);
    rb_define_const(mKey, "END", INT2NUM(KEY_END));
#endif
#ifdef KEY_EXIT
    rb_curses_define_const(KEY_EXIT);
    rb_define_const(mKey, "EXIT", INT2NUM(KEY_EXIT));
#endif
#ifdef KEY_FIND
    rb_curses_define_const(KEY_FIND);
    rb_define_const(mKey, "FIND", INT2NUM(KEY_FIND));
#endif
#ifdef KEY_HELP
    rb_curses_define_const(KEY_HELP);
    rb_define_const(mKey, "HELP", INT2NUM(KEY_HELP));
#endif
#ifdef KEY_MARK
    rb_curses_define_const(KEY_MARK);
    rb_define_const(mKey, "MARK", INT2NUM(KEY_MARK));
#endif
#ifdef KEY_MESSAGE
    rb_curses_define_const(KEY_MESSAGE);
    rb_define_const(mKey, "MESSAGE", INT2NUM(KEY_MESSAGE));
#endif
#ifdef KEY_MOVE
    rb_curses_define_const(KEY_MOVE);
    rb_define_const(mKey, "MOVE", INT2NUM(KEY_MOVE));
#endif
#ifdef KEY_NEXT
    rb_curses_define_const(KEY_NEXT);
    rb_define_const(mKey, "NEXT", INT2NUM(KEY_NEXT));
#endif
#ifdef KEY_OPEN
    rb_curses_define_const(KEY_OPEN);
    rb_define_const(mKey, "OPEN", INT2NUM(KEY_OPEN));
#endif
#ifdef KEY_OPTIONS
    rb_curses_define_const(KEY_OPTIONS);
    rb_define_const(mKey, "OPTIONS", INT2NUM(KEY_OPTIONS));
#endif
#ifdef KEY_PREVIOUS
    rb_curses_define_const(KEY_PREVIOUS);
    rb_define_const(mKey, "PREVIOUS", INT2NUM(KEY_PREVIOUS));
#endif
#ifdef KEY_REDO
    rb_curses_define_const(KEY_REDO);
    rb_define_const(mKey, "REDO", INT2NUM(KEY_REDO));
#endif
#ifdef KEY_REFERENCE
    rb_curses_define_const(KEY_REFERENCE);
    rb_define_const(mKey, "REFERENCE", INT2NUM(KEY_REFERENCE));
#endif
#ifdef KEY_REFRESH
    rb_curses_define_const(KEY_REFRESH);
    rb_define_const(mKey, "REFRESH", INT2NUM(KEY_REFRESH));
#endif
#ifdef KEY_REPLACE
    rb_curses_define_const(KEY_REPLACE);
    rb_define_const(mKey, "REPLACE", INT2NUM(KEY_REPLACE));
#endif
#ifdef KEY_RESTART
    rb_curses_define_const(KEY_RESTART);
    rb_define_const(mKey, "RESTART", INT2NUM(KEY_RESTART));
#endif
#ifdef KEY_RESUME
    rb_curses_define_const(KEY_RESUME);
    rb_define_const(mKey, "RESUME", INT2NUM(KEY_RESUME));
#endif
#ifdef KEY_SAVE
    rb_curses_define_const(KEY_SAVE);
    rb_define_const(mKey, "SAVE", INT2NUM(KEY_SAVE));
#endif
#ifdef KEY_SBEG
    rb_curses_define_const(KEY_SBEG);
    rb_define_const(mKey, "SBEG", INT2NUM(KEY_SBEG));
#endif
#ifdef KEY_SCANCEL
    rb_curses_define_const(KEY_SCANCEL);
    rb_define_const(mKey, "SCANCEL", INT2NUM(KEY_SCANCEL));
#endif
#ifdef KEY_SCOMMAND
    rb_curses_define_const(KEY_SCOMMAND);
    rb_define_const(mKey, "SCOMMAND", INT2NUM(KEY_SCOMMAND));
#endif
#ifdef KEY_SCOPY
    rb_curses_define_const(KEY_SCOPY);
    rb_define_const(mKey, "SCOPY", INT2NUM(KEY_SCOPY));
#endif
#ifdef KEY_SCREATE
    rb_curses_define_const(KEY_SCREATE);
    rb_define_const(mKey, "SCREATE", INT2NUM(KEY_SCREATE));
#endif
#ifdef KEY_SDC
    rb_curses_define_const(KEY_SDC);
    rb_define_const(mKey, "SDC", INT2NUM(KEY_SDC));
#endif
#ifdef KEY_SDL
    rb_curses_define_const(KEY_SDL);
    rb_define_const(mKey, "SDL", INT2NUM(KEY_SDL));
#endif
#ifdef KEY_SELECT
    rb_curses_define_const(KEY_SELECT);
    rb_define_const(mKey, "SELECT", INT2NUM(KEY_SELECT));
#endif
#ifdef KEY_SEND
    rb_curses_define_const(KEY_SEND);
    rb_define_const(mKey, "SEND", INT2NUM(KEY_SEND));
#endif
#ifdef KEY_SEOL
    rb_curses_define_const(KEY_SEOL);
    rb_define_const(mKey, "SEOL", INT2NUM(KEY_SEOL));
#endif
#ifdef KEY_SEXIT
    rb_curses_define_const(KEY_SEXIT);
    rb_define_const(mKey, "SEXIT", INT2NUM(KEY_SEXIT));
#endif
#ifdef KEY_SFIND
    rb_curses_define_const(KEY_SFIND);
    rb_define_const(mKey, "SFIND", INT2NUM(KEY_SFIND));
#endif
#ifdef KEY_SHELP
    rb_curses_define_const(KEY_SHELP);
    rb_define_const(mKey, "SHELP", INT2NUM(KEY_SHELP));
#endif
#ifdef KEY_SHOME
    rb_curses_define_const(KEY_SHOME);
    rb_define_const(mKey, "SHOME", INT2NUM(KEY_SHOME));
#endif
#ifdef KEY_SIC
    rb_curses_define_const(KEY_SIC);
    rb_define_const(mKey, "SIC", INT2NUM(KEY_SIC));
#endif
#ifdef KEY_SLEFT
    rb_curses_define_const(KEY_SLEFT);
    rb_define_const(mKey, "SLEFT", INT2NUM(KEY_SLEFT));
#endif
#ifdef KEY_SMESSAGE
    rb_curses_define_const(KEY_SMESSAGE);
    rb_define_const(mKey, "SMESSAGE", INT2NUM(KEY_SMESSAGE));
#endif
#ifdef KEY_SMOVE
    rb_curses_define_const(KEY_SMOVE);
    rb_define_const(mKey, "SMOVE", INT2NUM(KEY_SMOVE));
#endif
#ifdef KEY_SNEXT
    rb_curses_define_const(KEY_SNEXT);
    rb_define_const(mKey, "SNEXT", INT2NUM(KEY_SNEXT));
#endif
#ifdef KEY_SOPTIONS
    rb_curses_define_const(KEY_SOPTIONS);
    rb_define_const(mKey, "SOPTIONS", INT2NUM(KEY_SOPTIONS));
#endif
#ifdef KEY_SPREVIOUS
    rb_curses_define_const(KEY_SPREVIOUS);
    rb_define_const(mKey, "SPREVIOUS", INT2NUM(KEY_SPREVIOUS));
#endif
#ifdef KEY_SPRINT
    rb_curses_define_const(KEY_SPRINT);
    rb_define_const(mKey, "SPRINT", INT2NUM(KEY_SPRINT));
#endif
#ifdef KEY_SREDO
    rb_curses_define_const(KEY_SREDO);
    rb_define_const(mKey, "SREDO", INT2NUM(KEY_SREDO));
#endif
#ifdef KEY_SREPLACE
    rb_curses_define_const(KEY_SREPLACE);
    rb_define_const(mKey, "SREPLACE", INT2NUM(KEY_SREPLACE));
#endif
#ifdef KEY_SRIGHT
    rb_curses_define_const(KEY_SRIGHT);
    rb_define_const(mKey, "SRIGHT", INT2NUM(KEY_SRIGHT));
#endif
#ifdef KEY_SRSUME
    rb_curses_define_const(KEY_SRSUME);
    rb_define_const(mKey, "SRSUME", INT2NUM(KEY_SRSUME));
#endif
#ifdef KEY_SSAVE
    rb_curses_define_const(KEY_SSAVE);
    rb_define_const(mKey, "SSAVE", INT2NUM(KEY_SSAVE));
#endif
#ifdef KEY_SSUSPEND
    rb_curses_define_const(KEY_SSUSPEND);
    rb_define_const(mKey, "SSUSPEND", INT2NUM(KEY_SSUSPEND));
#endif
#ifdef KEY_SUNDO
    rb_curses_define_const(KEY_SUNDO);
    rb_define_const(mKey, "SUNDO", INT2NUM(KEY_SUNDO));
#endif
#ifdef KEY_SUSPEND
    rb_curses_define_const(KEY_SUSPEND);
    rb_define_const(mKey, "SUSPEND", INT2NUM(KEY_SUSPEND));
#endif
#ifdef KEY_UNDO
    rb_curses_define_const(KEY_UNDO);
    rb_define_const(mKey, "UNDO", INT2NUM(KEY_UNDO));
#endif
#ifdef KEY_RESIZE
    rb_curses_define_const(KEY_RESIZE);
    rb_define_const(mKey, "RESIZE", INT2NUM(KEY_RESIZE));
#endif
#ifdef KEY_MAX
    rb_curses_define_const(KEY_MAX);
    rb_define_const(mKey, "MAX", INT2NUM(KEY_MAX));
#endif
    {
	int c;
	char name[] = "KEY_CTRL_x";
	for (c = 'A'; c <= 'Z'; c++) {
	    name[sizeof(name) - 2] = c;
	    rb_define_const(mCurses, name, INT2FIX(c - 'A' + 1));
	}
    }
#undef rb_curses_define_const

    rb_set_end_proc(curses_finalize, 0);
}
