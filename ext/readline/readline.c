/* readline.c -- GNU Readline module
   Copyright (C) 1997-1998  Shugo Maeda */

#include <errno.h>
#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>

#include "ruby.h"
#include "rubysig.h"

static VALUE mReadline;

#define TOLOWER(c) (isupper(c) ? tolower(c) : c)

#define COMPLETION_PROC "completion_proc"
#define COMPLETION_CASE_FOLD "completion_case_fold"

#ifndef READLINE_42_OR_LATER
# define rl_filename_completion_function filename_completion_function
# define rl_username_completion_function username_completion_function
# define rl_completion_matches completion_matches
#endif

static int
readline_event()
{
    CHECK_INTS;
    rb_thread_schedule();
    return 0;
}

static VALUE
readline_readline(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE tmp, add_hist, result;
    char *prompt = NULL;
    char *buff;

    if (rb_scan_args(argc, argv, "02", &tmp, &add_hist) > 0) {
	prompt = STR2CSTR(tmp);
    }

    if (!isatty(0) && errno == EBADF) rb_raise(rb_eIOError, "stdin closed");

    buff = readline(prompt);
    if (RTEST(add_hist) && buff) {
	add_history(buff);
    }
    if (buff)
	result = rb_str_new2(buff);
    else
	result = Qnil;
    if (buff) free(buff);
    return result;
}

static VALUE
readline_s_set_completion_proc(self, proc)
    VALUE self;
    VALUE proc;
{
    if (!rb_respond_to(proc, rb_intern("call")))
	rb_raise(rb_eArgError, "argument have to respond to `call'");
    return rb_iv_set(mReadline, COMPLETION_PROC, proc);
}

static VALUE
readline_s_get_completion_proc(self)
    VALUE self;
{
    return rb_iv_get(mReadline, COMPLETION_PROC);
}

static VALUE
readline_s_set_completion_case_fold(self, val)
    VALUE self;
    VALUE val;
{
    return rb_iv_set(mReadline, COMPLETION_CASE_FOLD, val);
}

static VALUE
readline_s_get_completion_case_fold(self)
    VALUE self;
{
    return rb_iv_get(mReadline, COMPLETION_CASE_FOLD);
}

static char **
readline_attempted_completion_function(text, start, end)
    char *text;
    int start;
    int end;
{
    VALUE proc, ary, temp;
    char **result;
    int case_fold;
    int i, matches;

    proc = rb_iv_get(mReadline, COMPLETION_PROC);
    if (NIL_P(proc))
	return NULL;
    rl_attempted_completion_over = 1;
    case_fold = RTEST(rb_iv_get(mReadline, COMPLETION_CASE_FOLD));
    ary = rb_funcall(proc, rb_intern("call"), 1, rb_str_new2(text));
    if (TYPE(ary) != T_ARRAY)
	ary = rb_Array(ary);
    matches = RARRAY(ary)->len;
    if (matches == 0)
	return NULL;
    result = ALLOC_N(char *, matches + 2);
    for (i = 0; i < matches; i++) {
	temp = rb_obj_as_string(RARRAY(ary)->ptr[i]);
	result[i + 1] = ALLOC_N(char, RSTRING(temp)->len + 1);
	strcpy(result[i + 1], RSTRING(temp)->ptr);
    }
    result[matches + 1] = NULL;

    if (matches == 1) {
	result[0] = result[1];
	result[1] = NULL;
    } else {
	register int i = 1;
	int low = 100000;

	while (i < matches) {
	    register int c1, c2, si;

	    if (case_fold) {
		for (si = 0;
		     (c1 = TOLOWER(result[i][si])) &&
			 (c2 = TOLOWER(result[i + 1][si]));
		     si++)
		    if (c1 != c2) break;
	    } else {
		for (si = 0;
		     (c1 = result[i][si]) &&
			 (c2 = result[i + 1][si]);
		     si++)
		    if (c1 != c2) break;
	    }

	    if (low > si) low = si;
	    i++;
	}
	result[0] = ALLOC_N(char, low + 1);
	strncpy(result[0], result[1], low);
	result[0][low] = '\0';
    }

    return result;
}

static VALUE
readline_s_vi_editing_mode(self)
    VALUE self;
{
    rl_vi_editing_mode(1,0);
    return Qnil;
}

static VALUE
readline_s_emacs_editing_mode(self)
    VALUE self;
{
    rl_emacs_editing_mode(1,0);
    return Qnil;
}

static VALUE
readline_s_set_completion_append_character(self, str)
    VALUE self, str;
{
    if (NIL_P(str)) {
	rl_completion_append_character = '\0';
    } else {
	Check_Type(str, T_STRING);

	rl_completion_append_character = RSTRING(str)->ptr[0];
    }

    return self;
}

static VALUE
readline_s_get_completion_append_character(self)
    VALUE self;
{
    VALUE str;

    if (rl_completion_append_character == '\0')
	return Qnil;

    str = rb_str_new("", 1);
    RSTRING(str)->ptr[0] = rl_completion_append_character;

    return str;
}

static VALUE
hist_to_s(self)
    VALUE self;
{
    return rb_str_new2("HISTORY");
}

static VALUE
hist_get(self, index)
    VALUE self;
    VALUE index;
{
    HISTORY_STATE *state;
    int i;

    state = history_get_history_state();
    i = NUM2INT(index);
    if (i < 0 || i > state->length - 1) {
	rb_raise(rb_eIndexError, "Invalid index");
    }
    return rb_str_new2(state->entries[i]->line);
}

static VALUE
hist_set(self, index, str)
    VALUE self;
    VALUE index;
    VALUE str;
{
    HISTORY_STATE *state;
    int i;

    state = history_get_history_state();
    i = NUM2INT(index);
    if (i < 0 || i > state->length - 1) {
	rb_raise(rb_eIndexError, "Invalid index");
    }
    replace_history_entry(i, STR2CSTR(str), NULL);
    return str;
}

static VALUE
hist_push(self, str)
    VALUE self;
    VALUE str;
{
    add_history(STR2CSTR(str));
    return self;
}

static VALUE
hist_push_method(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE str;
    
    while (argc--) {
	str = *argv++;
	add_history(STR2CSTR(str));
    }
    return self;
}

static VALUE
hist_pop(self)
    VALUE self;
{
    HISTORY_STATE *state;
    HIST_ENTRY *entry;

    state = history_get_history_state();
    if (state->length > 0) {
	entry = remove_history(state->length - 1);
	return rb_str_new2(entry->line);
    } else {
	return Qnil;
    }
}

static VALUE
hist_shift(self)
    VALUE self;
{
    HISTORY_STATE *state;
    HIST_ENTRY *entry;

    state = history_get_history_state();
    if (state->length > 0) {
	entry = remove_history(0);
	return rb_str_new2(entry->line);
    } else {
	return Qnil;
    }
}

static VALUE
hist_each(self)
    VALUE self;
{
    HISTORY_STATE *state;
    int i;

    state = history_get_history_state();
    for (i = 0; i < state->length; i++) {
	rb_yield(rb_str_new2(state->entries[i]->line));
    }
    return self;
}

static VALUE
hist_length(self)
    VALUE self;
{
    HISTORY_STATE *state;

    state = history_get_history_state();
    return INT2NUM(state->length);
}

static VALUE
hist_empty_p(self)
    VALUE self;
{
    HISTORY_STATE *state;

    state = history_get_history_state();
    if (state->length == 0)
	return Qtrue;
    else
	return Qfalse;
}

static VALUE
hist_delete_at(self, index)
    VALUE self;
    VALUE index;
{
    HISTORY_STATE *state;
    HIST_ENTRY *entry;
    int i;

    state = history_get_history_state();
    i = NUM2INT(index);
    if (i < 0 || i > state->length - 1) {
	rb_raise(rb_eIndexError, "Invalid index");
    }
    entry = remove_history(NUM2INT(index));
    return rb_str_new2(entry->line);
}

static VALUE
filename_completion_proc_call(self, str)
    VALUE self;
    VALUE str;
{
    VALUE result;
    char **matches;
    int i;

    matches = rl_completion_matches(STR2CSTR(str),
				    rl_filename_completion_function);
    if (matches) {
	result = rb_ary_new();
	for (i = 0; matches[i]; i++) {
	    rb_ary_push(result, rb_str_new2(matches[i]));
	    free(matches[i]);
	}
	free(matches);
	if (RARRAY(result)->len >= 2)
	    rb_ary_shift(result);
    }
    else {
	result = Qnil;
    }
    return result;
}

static VALUE
username_completion_proc_call(self, str)
    VALUE self;
    VALUE str;
{
    VALUE result;
    char **matches;
    int i;

    matches = rl_completion_matches(STR2CSTR(str),
				    rl_username_completion_function);
    if (matches) {
	result = rb_ary_new();
	for (i = 0; matches[i]; i++) {
	    rb_ary_push(result, rb_str_new2(matches[i]));
	    free(matches[i]);
	}
	free(matches);
	if (RARRAY(result)->len >= 2)
	    rb_ary_shift(result);
    }
    else {
	result = Qnil;
    }
    return result;
}

void
Init_readline()
{
    VALUE histary, fcomp, ucomp;

    using_history();

    mReadline = rb_define_module("Readline");
    rb_define_module_function(mReadline, "readline",
			      readline_readline, -1);
    rb_define_singleton_method(mReadline, "completion_proc=",
			       readline_s_set_completion_proc, 1);
    rb_define_singleton_method(mReadline, "completion_proc",
			       readline_s_get_completion_proc, 0);
    rb_define_singleton_method(mReadline, "completion_case_fold=",
			       readline_s_set_completion_case_fold, 1);
    rb_define_singleton_method(mReadline, "completion_case_fold",
			       readline_s_get_completion_case_fold, 0);
    rb_define_singleton_method(mReadline, "vi_editing_mode",
			       readline_s_vi_editing_mode, 0);
    rb_define_singleton_method(mReadline, "emacs_editing_mode",
			       readline_s_emacs_editing_mode, 0);
    rb_define_singleton_method(mReadline, "completion_append_character=",
			       readline_s_set_completion_append_character, 1);
    rb_define_singleton_method(mReadline, "completion_append_character",
			       readline_s_get_completion_append_character, 0);

    histary = rb_obj_alloc(rb_cObject);
    rb_extend_object(histary, rb_mEnumerable);
    rb_define_singleton_method(histary,"to_s", hist_to_s, 0);
    rb_define_singleton_method(histary,"[]", hist_get, 1);
    rb_define_singleton_method(histary,"[]=", hist_set, 2);
    rb_define_singleton_method(histary,"<<", hist_push, 1);
    rb_define_singleton_method(histary,"push", hist_push_method, -1);
    rb_define_singleton_method(histary,"pop", hist_pop, 0);
    rb_define_singleton_method(histary,"shift", hist_shift, 0);
    rb_define_singleton_method(histary,"each", hist_each, 0);
    rb_define_singleton_method(histary,"length", hist_length, 0);
    rb_define_singleton_method(histary,"empty?", hist_empty_p, 0);
    rb_define_singleton_method(histary,"delete_at", hist_delete_at, 1);
    rb_define_const(mReadline, "HISTORY", histary);

    fcomp = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(fcomp, "call",
			       filename_completion_proc_call, 1);
    rb_define_const(mReadline, "FILENAME_COMPLETION_PROC", fcomp);

    ucomp = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(ucomp, "call",
			       username_completion_proc_call, 1);
    rb_define_const(mReadline, "USERNAME_COMPLETION_PROC", ucomp);

    rl_attempted_completion_function
	= (CPPFunction *) readline_attempted_completion_function;
    rl_event_hook = readline_event;
    rl_clear_signals();
}
