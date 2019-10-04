#include <ruby.h>

#ifndef numberof
#define numberof(array) (int)(sizeof(array) / sizeof((array)[0]))
#endif

static VALUE
scan_args_lead(int argc, VALUE *argv, VALUE self)
{
    VALUE args[2];
    int n = rb_scan_args(argc, argv, "1", args+1);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_opt(int argc, VALUE *argv, VALUE self)
{
    VALUE args[2];
    int n = rb_scan_args(argc, argv, "01", args+1);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "11", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

/* var */
static VALUE
scan_args_var(int argc, VALUE *argv, VALUE self)
{
    VALUE args[2];
    int n = rb_scan_args(argc, argv, "*", args+1);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_var(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "1*", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_opt_var(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "01*", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt_var(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "11*", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

/* trail */
static VALUE
scan_args_opt_trail(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "011", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt_trail(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "111", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_var_trail(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "*1", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_var_trail(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "1*1", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_opt_var_trail(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "01*1", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt_var_trail(int argc, VALUE *argv, VALUE self)
{
    VALUE args[5];
    int n = rb_scan_args(argc, argv, "11*1", args+1, args+2, args+3, args+4);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

/* hash */
static VALUE
scan_args_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[2];
    int n = rb_scan_args(argc, argv, ":", args+1);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "1:", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_opt_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "01:", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "11:", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_var_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n = rb_scan_args(argc, argv, "*:", args+1, args+2);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_var_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "1*:", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_opt_var_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "01*:", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt_var_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[5];
    int n = rb_scan_args(argc, argv, "11*:", args+1, args+2, args+3, args+4);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_opt_trail_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "011:", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt_trail_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[5];
    int n = rb_scan_args(argc, argv, "111:", args+1, args+2, args+3, args+4);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_var_trail_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args(argc, argv, "*1:", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_var_trail_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[5];
    int n = rb_scan_args(argc, argv, "1*1:", args+1, args+2, args+3, args+4);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_opt_var_trail_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[5];
    int n = rb_scan_args(argc, argv, "01*1:", args+1, args+2, args+3, args+4);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_lead_opt_var_trail_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[6];
    int n = rb_scan_args(argc, argv, "11*1:", args+1, args+2, args+3, args+4, args+5);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_k_lead_opt_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args_kw(RB_SCAN_ARGS_KEYWORDS, argc, argv, "11:", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

static VALUE
scan_args_n_lead_opt_hash(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n = rb_scan_args_kw(RB_SCAN_ARGS_LAST_HASH_KEYWORDS, argc, argv, "11:", args+1, args+2, args+3);
    args[0] = INT2NUM(n);
    return rb_ary_new_from_values(numberof(args), args);
}

void
Init_scan_args(void)
{
    VALUE module = rb_define_module("Bug");
    module = rb_define_module_under(module, "ScanArgs");
    rb_define_singleton_method(module, "lead", scan_args_lead, -1);
    rb_define_singleton_method(module, "opt", scan_args_opt, -1);
    rb_define_singleton_method(module, "lead_opt", scan_args_lead_opt, -1);
    rb_define_singleton_method(module, "var", scan_args_var, -1);
    rb_define_singleton_method(module, "lead_var", scan_args_lead_var, -1);
    rb_define_singleton_method(module, "opt_var", scan_args_opt_var, -1);
    rb_define_singleton_method(module, "lead_opt_var", scan_args_lead_opt_var, -1);
    rb_define_singleton_method(module, "opt_trail", scan_args_opt_trail, -1);
    rb_define_singleton_method(module, "lead_opt_trail", scan_args_lead_opt_trail, -1);
    rb_define_singleton_method(module, "var_trail", scan_args_var_trail, -1);
    rb_define_singleton_method(module, "lead_var_trail", scan_args_lead_var_trail, -1);
    rb_define_singleton_method(module, "opt_var_trail", scan_args_opt_var_trail, -1);
    rb_define_singleton_method(module, "lead_opt_var_trail", scan_args_lead_opt_var_trail, -1);
    rb_define_singleton_method(module, "hash", scan_args_hash, -1);
    rb_define_singleton_method(module, "lead_hash", scan_args_lead_hash, -1);
    rb_define_singleton_method(module, "opt_hash", scan_args_opt_hash, -1);
    rb_define_singleton_method(module, "lead_opt_hash", scan_args_lead_opt_hash, -1);
    rb_define_singleton_method(module, "var_hash", scan_args_var_hash, -1);
    rb_define_singleton_method(module, "lead_var_hash", scan_args_lead_var_hash, -1);
    rb_define_singleton_method(module, "opt_var_hash", scan_args_opt_var_hash, -1);
    rb_define_singleton_method(module, "lead_opt_var_hash", scan_args_lead_opt_var_hash, -1);
    rb_define_singleton_method(module, "opt_trail_hash", scan_args_opt_trail_hash, -1);
    rb_define_singleton_method(module, "lead_opt_trail_hash", scan_args_lead_opt_trail_hash, -1);
    rb_define_singleton_method(module, "var_trail_hash", scan_args_var_trail_hash, -1);
    rb_define_singleton_method(module, "lead_var_trail_hash", scan_args_lead_var_trail_hash, -1);
    rb_define_singleton_method(module, "opt_var_trail_hash", scan_args_opt_var_trail_hash, -1);
    rb_define_singleton_method(module, "lead_opt_var_trail_hash", scan_args_lead_opt_var_trail_hash, -1);
    rb_define_singleton_method(module, "k_lead_opt_hash", scan_args_k_lead_opt_hash, -1);
    rb_define_singleton_method(module, "n_lead_opt_hash", scan_args_n_lead_opt_hash, -1);
}
