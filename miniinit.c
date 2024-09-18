/**********************************************************************

  miniinit.c -

  $Author$
  created at: Thu Jul 11 22:09:57 JST 2013

  Copyright (C) 2013 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"

/* loadpath.c */
const char ruby_exec_prefix[] = "";
const char ruby_initial_load_paths[] = "";

/* localeinit.c */
VALUE
rb_locale_charmap(VALUE klass)
{
    /* never used */
    return Qnil;
}

int
rb_locale_charmap_index(void)
{
    return -1;
}

int
Init_enc_set_filesystem_encoding(void)
{
    return rb_enc_to_index(rb_default_external_encoding());
}

void rb_encdb_declare(const char *name);
int rb_encdb_alias(const char *alias, const char *orig);
void
Init_enc(void)
{
    rb_encdb_declare("ASCII-8BIT");
    rb_encdb_declare("US-ASCII");
    rb_encdb_declare("UTF-8");
    rb_encdb_alias("BINARY", "ASCII-8BIT");
    rb_encdb_alias("ASCII", "US-ASCII");
}

/* miniruby does not support dynamic loading. */
void
Init_ext(void)
{
}

static void builtin_loaded(const char *feature_name, VALUE iseq);
#define BUILTIN_LOADED(feature_name, iseq) builtin_loaded(feature_name, (VALUE)(iseq))

#include "mini_builtin.c"

static struct st_table *loaded_builtin_table;

static void
builtin_loaded(const char *feature_name, VALUE iseq)
{
    st_insert(loaded_builtin_table, (st_data_t)feature_name, (st_data_t)iseq);
    rb_vm_register_global_object(iseq);
}

static int
each_builtin_i(st_data_t key, st_data_t val, st_data_t dmy)
{
    const char *feature = (const char *)key;
    const rb_iseq_t *iseq = (const rb_iseq_t *)val;

    rb_yield_values(2, rb_str_new2(feature), rb_iseqw_new(iseq));

    return ST_CONTINUE;
}

/* :nodoc: */
static VALUE
each_builtin(VALUE self)
{
    st_foreach(loaded_builtin_table, each_builtin_i, 0);
    return Qnil;
}

void
Init_builtin(void)
{
    rb_define_singleton_method(rb_cRubyVM, "each_builtin", each_builtin, 0);
    loaded_builtin_table = st_init_strtable();
}

void
Init_builtin_features(void)
{
    // register for ruby
    builtin_iseq_load("gem_prelude", NULL);
}

void
rb_free_loaded_builtin_table(void)
{
    if (loaded_builtin_table)
        st_free_table(loaded_builtin_table);
}
