/************************************************

  methods.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Fri Oct  1 17:25:07 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "ident.h"
#include "env.h"
#include "node.h"
#include "methods.h"

void method_free();

#define CACHE_SIZE 577
#if 0
#define EXPR1(c,m) (((int)(c)*(m))>>0)
#else
#define EXPR1(c,m) ((int)(c)^(m))
#endif

#define TRIAL 3

struct hash_entry {		/* method hash table. */
    ID mid;			/* method's id */
    struct RClass *class;	/* receiver's class */
    struct RClass *origin;	/* where method defined  */
    struct SMethod *method;
    int undef;
};

static struct hash_entry cache[CACHE_SIZE];

static struct SMethod*
search_method(class, id, origin)
    struct RClass *class, **origin;
    ID id;
{
    struct SMethod *body;
    NODE *list;

    while (!st_lookup(class->m_tbl, id, &body)) {
	class = class->super;
	if (class == Qnil) return Qnil;
    }

    if (body->origin)
	*origin = body->origin;
    else
	*origin = class;
    return body;
}

NODE*
rb_get_method_body(class, id, envset)
    struct RClass *class;
    ID id;
    int envset;
{
    int pos, i;
    struct SMethod *method;

    /* is it in the method cache? */
    pos = EXPR1(class, id) % CACHE_SIZE;
    if (cache[pos].class != class || cache[pos].mid != id) {
	/* not in the cache */
	struct SMethod *body;
	struct RClass *origin;

	if ((body = search_method(class, id, &origin)) == Qnil) {
	    return Qnil;
	}
	/* store in cache */
	cache[pos].mid = id;
	cache[pos].class = class;
	cache[pos].origin = origin;
	cache[pos].method = body;
	cache[pos].undef = body->undef;
    }

    method = cache[pos].method;
    if (cache[pos].undef) return Qnil;
    if (envset) {
	the_env->last_func = method->id;
	the_env->last_class = cache[pos].origin;
    }
    return method->node;
}

void
rb_alias(class, name, def)
    struct RClass *class;
    ID name, def;
{
    struct SMethod *body;

    if (st_lookup(class->m_tbl, name, &body)) {
	if (verbose) {
	    Warning("redefine %s", rb_id2name(name));
	}
	rb_clear_cache(body);
	method_free(body);
    }
    body = search_method(class, def, &body);
    body->count++;
    st_insert(class->m_tbl, name, body);
}

void
rb_clear_cache(body)
    struct SMethod *body;
{
    int i;

    for (i = 0; i< CACHE_SIZE; i++ ) {
	if (cache[i].method == body) {
	    cache[i].class = Qnil;
	    cache[i].mid = Qnil;
	}
    }
}

void
rb_clear_cache2(class)
    struct RClass *class;
{
    int i;

    for (i = 0; i< CACHE_SIZE; i++ ) {
	if (cache[i].origin == class) {
	    cache[i].class = Qnil;
	    cache[i].mid = Qnil;
	}
    }
}

void
method_free(body)
    struct SMethod *body;
{
    body->count--;
    if (body->count == 0) {
	freenode(body->node);
	free(body);
    }
}
