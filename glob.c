/************************************************

  glob.c -

  $Author$
  $Date$
  created at: Mon Sep 12 18:56:43 JST 1994

************************************************/

#include "ruby.h"
#include "fnmatch.h"
#include <sys/param.h>

char *strdup();

VALUE C_Glob;

struct glob_data {
    char **globs;
};

static ID id_data;

static void
glob_free(data)
    struct glob_data *data;
{
    char **globs = data->globs;
    while (*globs) {
	free(*globs);
	globs++;
    }
    free(data->globs);
}

#define isdelim(c) ((c)==' '||(c)=='\t'||(c)=='\n'||(c)=='\0')

char *strchr();
char *strdup();

static int
expand_brace(s, data, len)
    char *s;
    struct glob_data *data;
    int len;
{
    char org[MAXPATHLEN], path[MAXPATHLEN];
    char *pre, *post, *head, *p, *t;

    strcpy(org, s);
    pre  = strchr(org, '{');
    if (pre) post = strchr(pre, '}');
    if (!pre || !post) {
	data->globs[len++] = strdup(s);
	REALLOC_N(data->globs, char*, len+1);
	return len;
    }

    memcpy(path, org, pre - org);
    p = org + (pre - org) + 1;
    head = path + (pre - org);

    while (p < post) {
	t = p;
	while (t < post) {
	    if (*t == ',') break;
	    t++;
	}
	memcpy(head, p, t-p);
	strcpy(head+(t-p), post+1);
	len = expand_brace(path, data, len);
	p = t + 1;
    }
    return len;
}

static VALUE
glob_new0(class, str)
    VALUE class;
    struct RString *str;
{
    VALUE new;
    struct glob_data *data;
    char *p1, *p2, *pend, *s;
    int len = 0;

    new = obj_alloc(class);
    Make_Data_Struct(new, id_data, struct glob_data, Qnil, glob_free, data);
    data->globs = ALLOC_N(char*, 1);

    p1 = p2 = str->ptr;
    pend = p1 + str->len;
    while (p1 < pend) {
	char s[MAXPATHLEN];
	int d;

	while (isdelim(*p1)) p1++;
	p2 = p1;
	while (!isdelim(*p2)) p2++;
	d = p2 - p1;
	memcpy(s, p1, d);
	s[d] = '\0';
	len = expand_brace(s, data, len);
	p1 = p2;
    }
    data->globs[len] = Qnil;

    return new;
}

VALUE
glob_new(str)
    struct RString *str;
{
    return glob_new0(C_Glob, str);
}

char **glob_filename();

static VALUE
Fglob_each(glob)
    VALUE glob;
{
    struct glob_data *data;
    char **patv, **fnames, **ff;

    Get_Data_Struct(glob, id_data, struct glob_data, data);
    for (patv = data->globs; *patv; patv++) {
	if (!glob_pattern_p(*patv)) {
	    rb_yield(str_new2(*patv));
	    continue;
	}
	fnames = ff = glob_filename(*patv);
	while (*ff) {
	    rb_yield(str_new2(*ff));
	    free(*ff);
	    ff++;
	}
	free(fnames);
    }
    return Qnil;
}

VALUE
Fglob_match(glob, str)
    VALUE glob;
    struct RString *str;
{
    struct glob_data *data;
    char **patv;

    Check_Type(str, T_STRING);
    Get_Data_Struct(glob, id_data, struct glob_data, data);
    patv = data->globs;
    while (*patv) {
	if (fnmatch(*patv, str->ptr, 0) != FNM_NOMATCH)
	    return TRUE;
	patv++;
    }
    return FALSE;
}

extern VALUE M_Enumerable;

Init_Glob()
{
    C_Glob = rb_define_class("Glob", C_Object);
    rb_include_module(C_Glob, M_Enumerable);

    rb_define_single_method(C_Glob, "new", glob_new0, 1);

    rb_define_method(C_Glob, "each", Fglob_each, 0);
    rb_define_method(C_Glob, "=~", Fglob_match, 1);

    id_data = rb_intern("data");
}
